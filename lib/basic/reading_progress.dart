import 'dart:convert';
import 'methods.dart';

const lastReadingProperty = 'reading.last_opened_chapter.v1';

class ReadingResume {
  const ReadingResume(this.log, this.chapterName);
  final ViewLog log;
  final String chapterName;

  ComicBasic get comic => ComicBasic(
    id: log.id,
    author: log.author,
    description: log.description,
    name: log.name,
    image: '',
  );

  String get position =>
      '${chapterName.isEmpty ? '' : '$chapterName · '}第 ${log.lastViewPage + 1} 页';
}

Future<ReadingResume?> loadReadingResume({Methods api = methods}) async {
  final property = await api.loadProperty(lastReadingProperty);
  if (property.isEmpty) return null;
  dynamic data;
  try {
    data = jsonDecode(property);
  } on FormatException {
    return null;
  }
  if (data is! Map || data['album_id'] is! int || data['chapter_id'] is! int) {
    return null;
  }
  final log = await api.findViewLog(data['album_id'] as int);
  // A deleted history entry must not reappear because an old pointer survived.
  if (log == null || log.lastViewChapterId <= 0 || log.lastViewPage < 0) {
    return null;
  }
  return ReadingResume(
    log,
    log.lastViewChapterId == data['chapter_id']
        ? (data['chapter_name'] as String? ?? '')
        : '',
  );
}

Future<void> rememberReadingChapter(
  int albumId,
  ChapterResponse chapter, {
  Methods api = methods,
}) async {
  if (chapter.images.isEmpty) return;
  await api.saveProperty(
    lastReadingProperty,
    jsonEncode({
      'album_id': albumId,
      'chapter_id': chapter.id,
      'chapter_name': chapter.name,
    }),
  );
}

List<Series> sortedReadingSeries(
  List<Series> source, {
  bool descending = false,
}) {
  final result = [...source]..sort((a, b) {
    final left = num.tryParse(a.sort);
    final right = num.tryParse(b.sort);
    if (left != null && right != null) return left.compareTo(right);
    if (left != null) return -1;
    if (right != null) return 1;
    return a.sort.compareTo(b.sort);
  });
  return descending ? result.reversed.toList() : result;
}

Future<ChapterResponse> loadDownloadedChapter(
  DownloadCreate create,
  int id,
) async {
  final images = await methods.dlImageByChapterId(id);
  final series =
      create.chapters
          .map((e) => Series(id: e.id, name: e.name, sort: e.sort))
          .toList();
  return ChapterResponse(
    id: id,
    series: series,
    tags: create.album.tags.join(' / '),
    name: series.where((e) => e.id == id).map((e) => e.name).firstOrNull ?? '',
    images: images.map((e) => e.name).toList(),
    seriesId: create.album.id,
    isFavorite: false,
    liked: false,
  );
}
