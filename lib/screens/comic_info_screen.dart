import 'package:flutter/material.dart';
import '../basic/commons.dart';
import '../basic/methods.dart';
import '../basic/navigator.dart';
import '../basic/reading_progress.dart';
import '../configs/ignore_view_log.dart';
import '../configs/login.dart';
import 'comic_download_screen.dart';
import 'comic_reader_screen.dart';
import 'comic_search_screen.dart';
import 'components/comic_comments_list.dart';
import 'components/comic_info_card.dart';
import 'components/comic_list.dart';
import 'components/continue_read_button.dart';
import 'components/expressive_page_transitions.dart';
import 'components/reading_widgets.dart';
import 'components/right_click_pop.dart';

class ComicInfoScreen extends StatefulWidget {
  const ComicInfoScreen(this.comicId, this.simple, {super.key});
  final int comicId;
  final ComicBasic? simple;
  @override
  State<ComicInfoScreen> createState() => _ComicInfoScreenState();
}

class _ComicInfoScreenState extends State<ComicInfoScreen> with RouteAware {
  bool _favouriteLoading = false;
  bool _descriptionExpanded = false;
  bool _tagsExpanded = false;
  bool _descending = false;
  int _tabIndex = 0;
  late Future<AlbumResponse> _albumFuture = methods.album(
    widget.comicId,
    ignoreViewLog: currentIgnoreVewLog(),
  );
  late Future<ViewLog?> _viewFuture = methods.findViewLog(widget.comicId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    if (mounted) {
      setState(() => _viewFuture = methods.findViewLog(widget.comicId));
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _read(AlbumResponse album, int chapterId, int page) {
    Navigator.of(context).push(
      AppPageRoute(
        settings: readerRouteSettings,
        builder:
            (_) => ComicReaderScreen(
              comic: albumToSimple(album, widget.simple),
              series: album.series,
              chapterId: chapterId,
              initRank: page,
              loadChapter: methods.chapter,
            ),
      ),
    );
  }

  void _search(String value) => Navigator.of(
    context,
  ).push(AppPageRoute(builder: (_) => ComicSearchScreen(initKeywords: value)));

  Widget _summary(AlbumResponse album) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ComicInfoCard(
        albumToSimple(album, widget.simple),
        link: true,
        prominent: true,
        actions: [
          TextButton.icon(
            onPressed: _favouriteLoading ? null : () => _changeFavourite(album),
            icon: Icon(
              album.isFavorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
            label: Text(
              _favouriteLoading
                  ? '处理中…'
                  : album.isFavorite
                  ? '已收藏'
                  : '收藏',
            ),
          ),
          TextButton.icon(
            onPressed:
                () => Navigator.of(context).push(
                  AppPageRoute(builder: (_) => ComicDownloadScreen(album)),
                ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载'),
          ),
        ],
      ),
      if (album.tags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in _tagsExpanded ? album.tags : album.tags.take(6))
                ActionChip(label: Text(tag), onPressed: () => _search(tag)),
              if (album.tags.length > 6)
                ActionChip(
                  label: Text(_tagsExpanded ? '收起标签' : '更多标签'),
                  onPressed:
                      () => setState(() => _tagsExpanded = !_tagsExpanded),
                ),
            ],
          ),
        ),
      if (album.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_descriptionExpanded)
                SelectableText(album.description)
              else
                Text(
                  album.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              TextButton.icon(
                onPressed:
                    () => setState(
                      () => _descriptionExpanded = !_descriptionExpanded,
                    ),
                icon: Icon(
                  _descriptionExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(_descriptionExpanded ? '收起简介' : '展开简介'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
    ],
  );

  Widget _tabs(AlbumResponse album) => Column(
    children: [
      TabBar(
        tabs: const [Tab(text: '章节'), Tab(text: '评论'), Tab(text: '推荐')],
        onTap: (value) => setState(() => _tabIndex = value),
      ),
      if (_tabIndex == 0) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ReadingSectionHeading(
            album.series.isEmpty ? '单篇阅读' : '全部章节 · ${album.series.length}',
            action:
                album.series.length > 1
                    ? TextButton.icon(
                      onPressed:
                          () => setState(() => _descending = !_descending),
                      icon: Icon(
                        _descending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 18,
                      ),
                      label: Text(_descending ? '倒序' : '正序'),
                    )
                    : null,
          ),
        ),
        FutureBuilder<ViewLog?>(
          future: _viewFuture,
          builder: (context, snapshot) {
            final series =
                album.series.isEmpty
                    ? [Series(id: album.id, name: album.name, sort: '1')]
                    : sortedReadingSeries(
                      album.series,
                      descending: _descending,
                    );
            return Column(
              children: [
                for (final chapter in series)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Material(
                      color:
                          snapshot.data?.lastViewChapterId == chapter.id
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Text(
                          chapter.name.isEmpty
                              ? '第 ${chapter.sort} 话'
                              : chapter.name,
                        ),
                        subtitle:
                            snapshot.data?.lastViewChapterId == chapter.id
                                ? const Text('上次读到这里')
                                : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _read(album, chapter.id, 0),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ] else if (_tabIndex == 1)
        ComicCommentsList(mode: 'manhua', aid: widget.comicId)
      else if (album.relatedList.isEmpty)
        const ReadingEmptyState(
          icon: Icons.auto_stories_outlined,
          title: '暂无相关漫画',
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ComicList(data: album.relatedList, inScroll: true),
        ),
      const SizedBox(height: 24),
    ],
  );

  @override
  Widget build(BuildContext context) => rightClickPop(
    context: context,
    child: Scaffold(
      appBar: AppBar(title: const Text('漫画详情')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: FutureBuilder<AlbumResponse>(
          future: _albumFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SingleChildScrollView(
                child: ReadingEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '漫画详情加载失败',
                  message: '检查网络后重试，或在书架打开已下载内容',
                  action: FilledButton(
                    onPressed:
                        () => setState(() {
                          _albumFuture = methods.album(
                            widget.comicId,
                            ignoreViewLog: currentIgnoreVewLog(),
                          );
                          _viewFuture = methods.findViewLog(widget.comicId);
                        }),
                    child: const Text('重试'),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    if (widget.simple != null)
                      ComicInfoCard(widget.simple!, prominent: true),
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                ),
              );
            }
            final album = snapshot.requireData;
            return DefaultTabController(
              length: 3,
              initialIndex: _tabIndex,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 840 &&
                      MediaQuery.textScalerOf(context).scale(14) < 23;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 360,
                          child: SingleChildScrollView(child: _summary(album)),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: SingleChildScrollView(child: _tabs(album)),
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(children: [_summary(album), _tabs(album)]),
                  );
                },
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: FutureBuilder<AlbumResponse>(
        future: _albumFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          return Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ContinueReadButton(
                      album: snapshot.requireData,
                      viewFuture: _viewFuture,
                      onChoose:
                          (id, page) => _read(snapshot.requireData, id, page),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Future<void> _changeFavourite(AlbumResponse album) async {
    setState(() => _favouriteLoading = true);
    try {
      await methods.setFavorite(album.id);
      if (!mounted) return;
      setState(() => album.isFavorite = !album.isFavorite);
      defaultToast(context, album.isFavorite ? '已加入收藏' : '已取消收藏');
      if (album.isFavorite && favData.isNotEmpty) {
        final folder = await chooseMapDialog<int>(
          context,
          title: '收藏到文件夹',
          values: {
            for (final folder in favData) folder.name: folder.fid,
            '默认 / 不移动': 0,
          },
        );
        if (folder != null && folder != 0) {
          await methods.comicFavoriteFolderMove(album.id, folder);
          if (mounted) defaultToast(context, '已移动到所选文件夹');
        }
      }
    } catch (error) {
      if (mounted) defaultToast(context, '收藏操作失败：$error');
    } finally {
      if (mounted) setState(() => _favouriteLoading = false);
    }
  }
}
