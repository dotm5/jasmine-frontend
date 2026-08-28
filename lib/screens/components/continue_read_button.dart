import 'package:flutter/material.dart';
import '../../basic/entities.dart';
import '../../basic/reading_progress.dart';

class ContinueReadButton extends StatelessWidget {
  const ContinueReadButton({
    super.key,
    required this.album,
    required this.onChoose,
    required this.viewFuture,
  });
  final Future<ViewLog?> viewFuture;
  final AlbumResponse album;
  final void Function(int chapterId, int page) onChoose;

  @override
  Widget build(BuildContext context) => FutureBuilder<ViewLog?>(
    future: viewFuture,
    builder: (context, snapshot) {
      final waiting = snapshot.connectionState != ConnectionState.done;
      final series = sortedReadingSeries(album.series);
      final progress = snapshot.data;
      final canResume =
          progress != null &&
          progress.lastViewChapterId > 0 &&
          progress.lastViewPage >= 0 &&
          (series.isEmpty
              ? progress.lastViewChapterId == album.id
              : series.any((e) => e.id == progress.lastViewChapterId));
      final chapter =
          canResume && series.isNotEmpty
              ? series.firstWhere((e) => e.id == progress.lastViewChapterId)
              : null;
      final position =
          chapter == null
              ? ''
              : '${chapter.name.isNotEmpty ? chapter.name : '第 ${chapter.sort} 话'} · ';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canResume)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '上次读到 $position第 ${progress.lastViewPage + 1} 页',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (snapshot.hasError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('阅读位置暂未读取，可从头开始', textAlign: TextAlign.center),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed:
                  waiting
                      ? null
                      : () => onChoose(
                        canResume
                            ? progress.lastViewChapterId
                            : (series.isEmpty ? album.id : series.first.id),
                        canResume ? progress.lastViewPage : 0,
                      ),
              icon: Icon(
                waiting
                    ? Icons.hourglass_top_rounded
                    : Icons.auto_stories_rounded,
              ),
              label: Text(
                waiting
                    ? '读取阅读进度…'
                    : canResume
                    ? '继续阅读'
                    : '开始阅读',
              ),
            ),
          ),
        ],
      );
    },
  );
}
