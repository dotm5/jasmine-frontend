import 'package:jasmine/screens/components/expressive_page_transitions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jasmine/basic/log.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/screens/comic_info_screen.dart';
import 'package:jasmine/screens/components/types.dart';

import 'comic_list.dart';
import 'reading_widgets.dart';

class ComicPager extends StatefulWidget {
  /// Reload retained pages without replacing their scrollable on route return.
  final int refreshRevision;
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;
  final Widget? header;
  final Widget? emptyState;
  final VoidCallback? onReturn;
  final bool compact;

  const ComicPager({
    required this.onPage,
    this.refreshRevision = 0,
    this.longPressMenuItems,
    this.appendList,
    this.header,
    this.emptyState,
    this.onReturn,
    this.compact = false,
    Key? key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicPagerState();
}

class _ComicPagerState extends State<ComicPager> {
  @override
  void initState() {
    currentPagerControllerModeEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    currentPagerControllerModeEvent.unsubscribe(_setState);
    super.dispose();
  }

  _setState(_) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (currentPagerControllerMode) {
      case PagerControllerMode.stream:
        return _StreamPager(
          refreshRevision: widget.refreshRevision,
          onPage: widget.onPage,
          longPressMenuItems: widget.longPressMenuItems,
          appendList: widget.appendList,
          header: widget.header,
          emptyState: widget.emptyState,
          onReturn: widget.onReturn,
          compact: widget.compact,
        );
      case PagerControllerMode.pager:
        return _PagerPager(
          refreshRevision: widget.refreshRevision,
          onPage: widget.onPage,
          longPressMenuItems: widget.longPressMenuItems,
          appendList: widget.appendList,
          header: widget.header,
          emptyState: widget.emptyState,
          onReturn: widget.onReturn,
          compact: widget.compact,
        );
    }
  }
}

class _StreamPager extends StatefulWidget {
  final int refreshRevision;
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;
  final Widget? header;
  final Widget? emptyState;
  final VoidCallback? onReturn;
  final bool compact;

  const _StreamPager({
    Key? key,
    required this.onPage,
    this.refreshRevision = 0,
    this.longPressMenuItems,
    this.appendList,
    this.header,
    this.emptyState,
    this.onReturn,
    this.compact = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _StreamPagerState();
}

class _StreamPagerState extends State<_StreamPager> {
  int _maxPage = 1;
  int _nextPage = 1;
  int _total = 0;
  int _firstPage = 1;
  int _pageSize = 0;
  bool _refreshPending = false;
  bool _refreshFailed = false;

  var _joining = false;
  var _joinSuccess = true;

  Future _join() async {
    if (_joining || !mounted) return;
    try {
      setState(() {
        _joining = true;
      });
      var response = await widget.onPage(_nextPage);
      if (!mounted) return;
      if (_nextPage == 1) {
        _pageSize = response.list.length;
        if (_redirectAid(response.redirectAid, context)) {
          return;
        }
        if (response.total <= 0 || response.list.isEmpty) {
          _maxPage = 1;
        } else {
          _maxPage = (response.total / response.list.length).ceil();
        }
        _total = response.total;
      }
      _nextPage++;
      _data.addAll(response.list);
      setState(() {
        _joinSuccess = true;
      });
    } catch (e, st) {
      debugPrient("$e\n$st");
      if (!mounted) return;
      setState(() {
        _joinSuccess = false;
      });
    } finally {
      _finishRequest();
    }
  }

  @override
  void didUpdateWidget(covariant _StreamPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) _refresh();
  }

  void _finishRequest() {
    if (!mounted) return;
    setState(() => _joining = false);
    if (_refreshPending) _refresh();
  }

  Future<void> _refresh() async {
    if (_joining) {
      _refreshPending = true;
      return;
    }
    _refreshPending = false;
    setState(() => _joining = true);
    try {
      // Keep both the old rows and ScrollController attached until every
      // retained page is ready. Refreshing only page 1 truncates long lists.
      final refreshed = <ComicSimple>[];
      var total = _total;
      var maxPage = _maxPage;
      var firstPage = _firstPage;
      var nextPage = firstPage;
      var pageSize = _pageSize;
      final endPage = _nextPage > firstPage ? _nextPage : firstPage + 1;
      for (var page = firstPage; page < endPage; page++) {
        var response = await widget.onPage(page);
        if (!mounted) return;
        if (page == firstPage) {
          total = response.total;
          if (page == 1 && response.list.isNotEmpty) {
            pageSize = response.list.length;
          }
          maxPage = total > 0 && pageSize > 0 ? (total / pageSize).ceil() : 1;
          if (page > maxPage) {
            // A removed last page should fall back to the last valid page.
            firstPage = page = maxPage;
            response = await widget.onPage(page);
            if (!mounted) return;
          }
        }
        refreshed.addAll(response.list);
        nextPage = page + 1;
        if (page >= maxPage) break;
      }
      setState(() {
        _data
          ..clear()
          ..addAll(refreshed);
        _total = total;
        _maxPage = maxPage;
        _pageSize = pageSize;
        _firstPage = firstPage;
        _nextPage = nextPage;
        _joinSuccess = true;
        _refreshFailed = false;
      });
    } catch (e, st) {
      debugPrient('$e\n$st');
      if (!mounted) return;
      setState(() {
        _joinSuccess = false;
        _refreshFailed = true;
      });
    } finally {
      _finishRequest();
    }
  }

  final List<ComicSimple> _data = [];
  late ScrollController _controller;
  final TextEditingController _textEditController = TextEditingController();

  _jumpPage() {
    if (_total == 0 || _joining) {
      return;
    }
    _textEditController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Card(
            child: TextField(
              controller: _textEditController,
              decoration: const InputDecoration(labelText: "请输入页数："),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'\d+')),
              ],
            ),
          ),
          actions: <Widget>[
            MaterialButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            MaterialButton(
              onPressed: () {
                Navigator.pop(context);
                var text = _textEditController.text;
                if (text.isEmpty || text.length > 7) {
                  return;
                }
                var num = int.parse(text);
                if (num == 0 || num > _maxPage) {
                  return;
                }
                _data.clear();
                _firstPage = num;
                _nextPage = num;
                _join();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _join();
  }

  @override
  void dispose() {
    _textEditController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_joining || _refreshFailed || _nextPage > _maxPage) {
      return;
    }
    if (_controller.position.pixels + 100 >
        _controller.position.maxScrollExtent) {
      _join();
    }
  }

  Widget? _buildLoadingCard() {
    if (_joining) {
      return Card(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: const CupertinoActivityIndicator(radius: 14),
            ),
            const Text('加载中'),
          ],
        ),
      );
    }
    if (!_joinSuccess) {
      return Card(
        child: InkWell(
          onTap: () {
            _refreshFailed ? _refresh() : _join();
          },
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: const Icon(Icons.sync_problem_rounded),
              ),
              const Text('出错, 点击重试'),
            ],
          ),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!widget.compact) _buildPagerBar(),
        Expanded(
          child: ComicList(
            controller: _controller,
            onScroll: _onScroll,
            data: _data,
            header: widget.header,
            onReturn: widget.onReturn,
            appendList: [
              if (_buildLoadingCard() != null) _buildLoadingCard()!,
              if (!_joining && _joinSuccess && _data.isEmpty)
                widget.emptyState ??
                    const ReadingEmptyState(
                      icon: Icons.auto_stories_outlined,
                      title: '这里还没有漫画',
                    ),
              if (!_joining && _joinSuccess && _nextPage <= _maxPage)
                TextButton.icon(
                  onPressed: _join,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('加载更多'),
                ),
              if (widget.compact && _data.isNotEmpty) _buildPagerBar(),
              ...?widget.appendList,
            ],
            longPressMenuItems: widget.longPressMenuItems,
          ),
        ),
      ],
    );
  }

  PreferredSize _buildPagerBar() => PreferredSize(
    preferredSize: const Size.fromHeight(48),
    child: InkWell(
      onTap: _jumpPage,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text('已加载 ${_nextPage - 1} / $_maxPage 页'),
            Text('已加载 ${_data.length} / $_total 项'),
          ],
        ),
      ),
    ),
  );
}

class _PagerPager extends StatefulWidget {
  final int refreshRevision;
  final Future<InnerComicPage> Function(int page) onPage;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final List<Widget>? appendList;
  final Widget? header;
  final Widget? emptyState;
  final VoidCallback? onReturn;
  final bool compact;

  const _PagerPager({
    Key? key,
    required this.onPage,
    this.refreshRevision = 0,
    this.longPressMenuItems,
    this.appendList,
    this.header,
    this.emptyState,
    this.onReturn,
    this.compact = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PagerPagerState();
}

class _PagerPagerState extends State<_PagerPager> {
  int _loadVersion = 0;
  bool _keepDataWhileLoading = false;
  final TextEditingController _textEditController = TextEditingController(
    text: '',
  );
  late int _currentPage = 1;
  late int _maxPage = 1;
  late final List<ComicSimple> _data = [];
  late Future _pageFuture = _load();

  Future<dynamic> _load() async {
    final version = ++_loadVersion;
    final requestedPage = _currentPage;
    var response = await widget.onPage(requestedPage);
    if (!mounted || version != _loadVersion || requestedPage != _currentPage) {
      return;
    }
    setState(() {
      if (_currentPage == 1) {
        if (_redirectAid(response.redirectAid, context)) {
          return;
        }
        if (response.total <= 0 || response.list.isEmpty) {
          _maxPage = 1;
        } else {
          _maxPage = (response.total / response.list.length).ceil();
        }
      }
      _data.clear();
      _data.addAll(response.list);
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _PagerPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision) {
      _keepDataWhileLoading = true;
      _pageFuture = _load();
    }
  }

  @override
  void dispose() {
    _textEditController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _pageFuture,
      builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        return Column(
          children: [
            if (!widget.compact) _buildPagerBar(),
            Expanded(
              child: ComicList(
                header: widget.header,
                onReturn: widget.onReturn,
                appendList: [
                  if (snapshot.hasError)
                    ReadingEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '加载失败',
                      action: TextButton(
                        onPressed:
                            () => setState(() {
                              _pageFuture = _load();
                            }),
                        child: const Text('重试'),
                      ),
                    )
                  else if (!ready)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_data.isEmpty)
                    widget.emptyState ??
                        const ReadingEmptyState(
                          icon: Icons.auto_stories_outlined,
                          title: '这里还没有漫画',
                        ),
                  if (widget.compact &&
                      (ready || _keepDataWhileLoading) &&
                      _data.isNotEmpty)
                    _buildPagerBar(),
                  ...?widget.appendList,
                ],
                data: ready || _keepDataWhileLoading ? _data : const [],
                longPressMenuItems: widget.longPressMenuItems,
              ),
            ),
          ],
        );
      },
    );
  }

  PreferredSize _buildPagerBar() => PreferredSize(
    preferredSize: const Size.fromHeight(56),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          TextButton(
            onPressed: _choosePage,
            child: Text('第 $_currentPage / $_maxPage 页'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed:
                    _currentPage > 1 ? () => _goTo(_currentPage - 1) : null,
                child: const Text('上一页'),
              ),
              TextButton(
                onPressed:
                    _currentPage < _maxPage
                        ? () => _goTo(_currentPage + 1)
                        : null,
                child: const Text('下一页'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _goTo(int page) {
    setState(() {
      _keepDataWhileLoading = false;
      _currentPage = page;
      _pageFuture = _load();
    });
  }

  Future<void> _choosePage() async {
    _textEditController.clear();
    final page = await showDialog<int>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('跳转到指定页'),
            content: TextField(
              controller: _textEditController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: '页码（1–$_maxPage）'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final page = int.tryParse(_textEditController.text);
                  if (page != null && page > 0 && page <= _maxPage) {
                    Navigator.pop(context, page);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
    );
    if (page != null && mounted) _goTo(page);
  }
}

bool _redirectAid(int? redirectAid, BuildContext context) {
  if (redirectAid != null) {
    Navigator.of(context).pushReplacement(
      AppPageRoute(
        builder: (BuildContext context) {
          return ComicInfoScreen(redirectAid, null);
        },
      ),
    );
    return true;
  }
  return false;
}
