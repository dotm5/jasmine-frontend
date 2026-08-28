import 'dart:convert';
import 'package:flutter/material.dart';
import '../basic/commons.dart';
import '../basic/methods.dart';
import '../basic/navigator.dart';
import '../basic/reading_progress.dart';
import '../configs/login.dart';
import 'comic_reader_screen.dart';
import 'comic_search_screen.dart';
import 'components/browser_bottom_sheet.dart';
import 'components/comic_floating_search_bar.dart';
import 'components/comic_list.dart';
import 'components/comic_pager.dart';
import 'components/expressive_page_transitions.dart';
import 'components/floating_search_bar.dart';
import 'components/reading_account_sheet.dart';
import 'components/reading_widgets.dart';
import 'components/types.dart';
import 'download_album_screen.dart';
import 'downloads_screen.dart';
import 'favorites_screen.dart';
import 'view_log_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key, this.searchBarController});
  final FloatingSearchBarController? searchBarController;
  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen>
    with AutomaticKeepAliveClientMixin, RouteAware {
  @override
  bool get wantKeepAlive => true;
  int _tab = 0;
  final _visited = <int>{0};
  final _revisions = [0, 0, 0];
  int _returnRevision = 0;
  int _folder = 0;
  String _sort = 'mr';
  bool _opening = false;
  late Future<ReadingResume?> _resume;
  Future<List<DownloadAlbum>>? _downloads;

  @override
  void initState() {
    super.initState();
    _resume = loadReadingResume();
    loginEvent.subscribe(_loginChanged);
    _loadSort();
  }

  Future<void> _loadSort() async {
    try {
      final value = await methods.loadProperty('favorites_sort');
      if (mounted && (value == 'mr' || value == 'mp')) {
        setState(() {
          _sort = value;
          _revisions[1]++;
        });
      }
    } catch (_) {
      /* Keep the default order if local preferences are unavailable. */
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() => _refresh(preserveLists: true);
  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    loginEvent.unsubscribe(_loginChanged);
    super.dispose();
  }

  void _loginChanged(_) {
    if (mounted) {
      setState(() {
        _folder = 0;
        _revisions[1]++;
      });
    }
  }

  void _refresh({bool preserveLists = false}) {
    if (!mounted) return;
    setState(() {
      _resume = loadReadingResume();
      if (preserveLists) {
        _returnRevision++;
      } else {
        for (var i = 0; i < _revisions.length; i++) {
          _revisions[i]++;
        }
      }
      if (_visited.contains(2)) _downloads = methods.allDownloads();
    });
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(AppPageRoute(builder: (_) => screen));

  Future<void> _continue(ReadingResume resume) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      Future<ChapterResponse> Function(int) loader = methods.chapter;
      List<Series> series = [];
      final downloads = await methods.allDownloads();
      if (downloads.any((e) => e.id == resume.log.id && e.dlStatus == 1)) {
        final create = await methods.downloadById(resume.log.id);
        if (create != null &&
            create.chapters.any((e) => e.id == resume.log.lastViewChapterId)) {
          series =
              create.chapters
                  .map((e) => Series(id: e.id, name: e.name, sort: e.sort))
                  .toList();
          loader = (id) => loadDownloadedChapter(create, id);
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute(
          settings: readerRouteSettings,
          builder:
              (_) => ComicReaderScreen(
                comic: resume.comic,
                series: series,
                chapterId: resume.log.lastViewChapterId,
                initRank: resume.log.lastViewPage,
                loadChapter: loader,
              ),
        ),
      );
    } catch (error) {
      if (mounted) defaultToast(context, '打开失败：$error');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _search() async {
    final controller = widget.searchBarController;
    if (controller == null) {
      _open(const ComicSearchScreen(initKeywords: ''));
      return;
    }
    try {
      searchHistories = await methods.lastSearchHistories(20);
    } catch (_) {
      searchHistories = [];
    }
    if (mounted) controller.display(modifyInput: '');
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<ReadingResume?>(
          future: _resume,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Expanded(child: Text('阅读进度暂未加载')),
                    TextButton(onPressed: _refresh, child: const Text('重试')),
                  ],
                ),
              );
            }
            if (snapshot.data == null) return const SizedBox.shrink();
            final resume = snapshot.requireData!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: ContinueReadingCard(
                comic: resume.comic,
                position: resume.position,
                busy: _opening,
                onContinue: () => _continue(resume),
              ),
            );
          },
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('最近')),
              ButtonSegment(value: 1, label: Text('收藏')),
              ButtonSegment(value: 2, label: Text('已下载')),
            ],
            selected: {_tab},
            onSelectionChanged:
                (selected) => setState(() {
                  _tab = selected.single;
                  _visited.add(_tab);
                  if (_tab == 2) _downloads ??= methods.allDownloads();
                }),
          ),
        ),
        if (_tab == 0)
          ReadingSectionHeading(
            '最近浏览',
            action: TextButton(
              onPressed: () => _open(const ViewLogScreen()),
              child: const Text('管理历史'),
            ),
          ),
        if (_tab == 1) ...[
          ReadingSectionHeading(
            '我的收藏',
            action: TextButton(
              onPressed:
                  loginStatus == LoginStatus.loginSuccess
                      ? () => _open(const FavoritesScreen())
                      : null,
              child: const Text('管理收藏'),
            ),
          ),
          if (loginStatus == LoginStatus.loginSuccess)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(
                      _folder == 0
                          ? '全部收藏'
                          : favData
                                  .where((e) => e.fid == _folder)
                                  .map((e) => e.name)
                                  .firstOrNull ??
                              '文件夹',
                    ),
                    onPressed: () async {
                      final value = await chooseMapDialog<int>(
                        context,
                        title: '选择文件夹',
                        values: {
                          '全部收藏': 0,
                          for (final folder in favData) folder.name: folder.fid,
                        },
                      );
                      if (value != null && mounted) {
                        setState(() {
                          _folder = value;
                          _revisions[1]++;
                        });
                      }
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.sort, size: 18),
                    label: Text(_sort == 'mr' ? '收藏时间' : '更新时间'),
                    onPressed: () async {
                      final value = await chooseMapDialog<String>(
                        context,
                        title: '收藏排序',
                        values: {'收藏时间': 'mr', '更新时间': 'mp'},
                      );
                      if (value != null && mounted) {
                        setState(() {
                          _sort = value;
                          _revisions[1]++;
                        });
                        try {
                          await methods.saveProperty('favorites_sort', value);
                        } catch (error) {
                          if (mounted) defaultToast(context, '排序偏好未保存：$error');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
        if (_tab == 2)
          ReadingSectionHeading(
            '离线阅读',
            action: TextButton(
              onPressed: () => _open(const DownloadsScreen()),
              child: const Text('下载管理'),
            ),
          ),
      ],
    ),
  );

  Widget _panel(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    if (index == 1 && loginStatus != LoginStatus.loginSuccess) {
      return ListView(
        children: [
          _header(),
          ReadingEmptyState(
            icon: Icons.bookmarks_outlined,
            title: '登录后查看收藏',
            message: '最近浏览和已下载内容仍可使用',
            action: FilledButton(
              onPressed:
                  loginStatus == LoginStatus.logging
                      ? null
                      : () => loginDialog(context),
              child: Text(
                loginStatus == LoginStatus.logging ? '正在登录…' : '登录 / 注册',
              ),
            ),
          ),
        ],
      );
    }
    if (index == 2) {
      return FutureBuilder<List<DownloadAlbum>>(
        future: _downloads,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return ListView(
              children: [
                _header(),
                if (snapshot.hasError)
                  ReadingEmptyState(
                    icon: Icons.error_outline,
                    title: '下载列表加载失败',
                    action: TextButton(
                      onPressed: _refresh,
                      child: const Text('重试'),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          }
          final albums =
              snapshot.requireData.where((e) => e.dlStatus == 1).toList();
          return ComicList(
            header: _header(),
            data:
                albums
                    .map(
                      (e) => ComicBasic(
                        id: e.id,
                        author: _author(e.author),
                        description: e.description,
                        name: e.name,
                        image: '',
                      ),
                    )
                    .toList(),
            subtitleBuilder:
                (comic) =>
                    '已下载 · ${albums.firstWhere((e) => e.id == comic.id).imageCount} 页',
            onComicTap: (comic) async {
              await Navigator.of(context).push(
                AppPageRoute(
                  builder:
                      (_) => DownloadAlbumScreen(
                        albums.firstWhere((e) => e.id == comic.id),
                      ),
                ),
              );
            },
            appendList:
                albums.isEmpty
                    ? [
                      const ReadingEmptyState(
                        icon: Icons.download_outlined,
                        title: '还没有已完成的下载',
                        message: '下载漫画后，可在这里离线阅读；进行中的任务请查看下载管理',
                      ),
                    ]
                    : null,
          );
        },
      );
    }
    return ComicPager(
      key: ValueKey('shelf:$index:${_revisions[index]}'),
      refreshRevision: _returnRevision,
      compact: true,
      header: _header(),
      emptyState: ReadingEmptyState(
        icon: index == 0 ? Icons.history_rounded : Icons.bookmarks_outlined,
        title: index == 0 ? '还没有浏览记录' : '这里还没有收藏',
        message: index == 0 ? '打开一本漫画，它就会留在这里' : '将喜欢的漫画加入收藏，慢慢阅读',
      ),
      onPage: (page) async {
        if (index == 0) {
          final response = await methods.pageViewLog(page);
          return InnerComicPage(total: response.total, list: response.content);
        }
        final response = await methods.favorites(_folder, page, _sort);
        if (mounted) setState(() => favData = response.folderList);
        return InnerComicPage(total: response.total, list: response.list);
      },
      longPressMenuItems:
          index == 0
              ? [
                ComicLongPressMenuItem('删除浏览记录', (comic) async {
                  try {
                    await methods.deleteViewLogByComicId(comic.id);
                    _refresh();
                  } catch (error) {
                    if (mounted) defaultToast(context, '删除失败：$error');
                  }
                }),
              ]
              : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: 80,
        title: Text(
          '书架',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '刷新书架',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const BrowserBottomSheetAction(),
          const ReadingAccountButton(),
          IconButton(
            tooltip: '搜索漫画',
            onPressed: _search,
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: IndexedStack(
              index: _tab,
              children: [for (var i = 0; i < 3; i++) _panel(i)],
            ),
          ),
        ),
      ),
    );
  }
}

String _author(String value) {
  try {
    return (jsonDecode(value) as List).join(' / ');
  } catch (_) {
    return value;
  }
}
