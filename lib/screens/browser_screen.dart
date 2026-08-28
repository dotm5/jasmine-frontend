import 'package:flutter/material.dart';
import '../basic/commons.dart';
import '../basic/comic_seal.dart';
import '../basic/methods.dart';
import '../configs/categories_sort.dart';
import '../configs/login.dart';
import 'comic_info_screen.dart';
import 'components/browser_bottom_sheet.dart';
import 'components/comic_floating_search_bar.dart';
import 'components/comic_pager.dart';
import 'components/expressive_page_transitions.dart';
import 'components/floating_search_bar.dart';
import 'components/reading_account_sheet.dart';
import 'components/reading_widgets.dart';
import 'week_screen.dart';

class BrowserScreenWrapper extends StatefulWidget {
  const BrowserScreenWrapper({super.key, required this.searchBarController});
  final FloatingSearchBarController searchBarController;
  @override
  State<BrowserScreenWrapper> createState() => _BrowserScreenWrapperState();
}

class _BrowserScreenWrapperState extends State<BrowserScreenWrapper> {
  @override
  void initState() {
    super.initState();
    loginEvent.subscribe(_refresh);
  }

  @override
  void dispose() {
    loginEvent.unsubscribe(_refresh);
    super.dispose();
  }

  void _refresh(_) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loginStatus == LoginStatus.loginSuccess) {
      return BrowserScreen(searchBarController: widget.searchBarController);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览'),
        centerTitle: false,
        actions: const [ReadingAccountButton()],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ReadingEmptyState(
            icon: Icons.auto_stories_outlined,
            title: loginStatus == LoginStatus.logging ? '正在登录…' : '发现下一本喜欢的漫画',
            message: '登录后浏览在线内容，本地历史与下载仍可在书架查看',
            action:
                loginStatus == LoginStatus.logging
                    ? const CircularProgressIndicator()
                    : FilledButton.icon(
                      onPressed: () => loginDialog(context),
                      icon: const Icon(Icons.login),
                      label: const Text('登录 / 注册'),
                    ),
          ),
        ),
      ),
    );
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.searchBarController});
  final FloatingSearchBarController searchBarController;
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late Future<CategoriesResponse> _future;
  late Future<List<ComicSimple>> _weekFuture;
  String _slug = '';
  SortBy _sortBy = sortByDefault;
  int _revision = 0;

  Future<CategoriesResponse> _categories() async {
    final response = await methods.categories();
    blockStore = response.blocks;
    sortCategories(response.categories);
    return response;
  }

  Future<List<ComicSimple>> _week() async {
    final data = await methods.week(0);
    if (data.categories.isEmpty || data.types.isEmpty) return [];
    final response = await methods.weekFilter(
      data.categories.first.id,
      data.types.last.id,
      1,
    );
    for (final comic in response.list) {
      comic.sealed = comic.sealed || matchComicSealedByRules(comic);
    }
    return response.list.take(8).toList();
  }

  @override
  void initState() {
    super.initState();
    _future = _categories();
    _weekFuture = _week();
    // Attach the error handler immediately, even while categories are loading.
    _weekFuture.ignore();
    categoriesSortEvent.subscribe(_resort);
  }

  @override
  void dispose() {
    categoriesSortEvent.unsubscribe(_resort);
    super.dispose();
  }

  void _resort(_) {
    if (mounted) {
      setState(() {
        _future = _categories();
        _revision++;
      });
    }
  }

  Future<void> _search() async {
    try {
      searchHistories = await methods.lastSearchHistories(20);
    } catch (_) {
      searchHistories = [];
    }
    if (mounted) widget.searchBarController.display(modifyInput: '');
  }

  void _openWeek() => Navigator.of(
    context,
  ).push(AppPageRoute(builder: (_) => const WeekScreen()));

  Widget _header(List<Categories> categories) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReadingSearchEntry(onTap: _search),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(category.name),
                      selected: _slug == category.slug,
                      onSelected: (_) => setState(() => _slug = category.slug),
                    ),
                  ),
              ],
            ),
          ),
          ReadingSectionHeading(
            '每周必看',
            action: TextButton(
              onPressed: _openWeek,
              child: const Text('查看全部 ›'),
            ),
          ),
          FutureBuilder<List<ComicSimple>>(
            future: _weekFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Row(
                  children: [
                    const Expanded(child: Text('每周内容暂未加载')),
                    TextButton(
                      onPressed: () => setState(() => _weekFuture = _week()),
                      child: const Text('重试'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: LinearProgressIndicator(),
                );
              }
              if (snapshot.requireData.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('本期暂无内容，试试其他期数'),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final width = ((constraints.maxWidth - 24) / 3).clamp(
                    104.0,
                    148.0,
                  );
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  return SizedBox(
                    height: width * 4 / 3 + 16 + 62 * textScale,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: snapshot.requireData.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final comic = snapshot.requireData[index];
                        return SizedBox(
                          width: width,
                          child: ReadingCoverTile(
                            comic: comic,
                            subtitle: '',
                            onTap:
                                () => Navigator.of(context).push(
                                  AppPageRoute(
                                    builder:
                                        (_) => ComicInfoScreen(comic.id, comic),
                                  ),
                                ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
          ReadingSectionHeading(
            '发现漫画',
            action: TextButton.icon(
              onPressed: () async {
                final selected = await chooseSortBy(context);
                if (selected != null && mounted) {
                  setState(() => _sortBy = selected);
                }
              },
              icon: const Icon(Icons.sort_rounded, size: 18),
              label: Text(_sortBy.toString()),
            ),
          ),
        ],
      ),
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
          '浏览',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed:
                () => setState(() {
                  _future = _categories();
                  _weekFuture = _week();
                  _weekFuture.ignore();
                  _revision++;
                }),
          ),
          const BrowserBottomSheetAction(),
          const ReadingAccountButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: FutureBuilder<CategoriesResponse>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      ReadingSearchEntry(onTap: _search),
                      if (snapshot.hasError)
                        ReadingEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: '分类加载失败',
                          action: FilledButton(
                            onPressed: () => _resort(null),
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
                final categories = snapshot.requireData.categories;
                if (!categories.any((category) => category.slug == _slug) &&
                    categories.isNotEmpty) {
                  _slug = categories.first.slug;
                }
                return ComicPager(
                  key: ValueKey('browse:$_slug:$_sortBy:$_revision'),
                  compact: true,
                  header: _header(categories),
                  onPage: (page) async {
                    final response = await methods.comics(_slug, _sortBy, page);
                    return InnerComicPage(
                      total: response.total,
                      list: response.content,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
