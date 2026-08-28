import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/basic/navigator.dart';
import 'package:jasmine/basic/reading_progress.dart';
import 'package:jasmine/configs/display_jmcode.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/configs/search_title_words.dart';
import 'package:jasmine/configs/theme.dart' as app_theme;
import 'package:jasmine/screens/browser_screen.dart';
import 'package:jasmine/screens/comic_info_screen.dart';
import 'package:jasmine/screens/components/comic_list.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/components/continue_read_button.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';
import 'package:jasmine/screens/components/reading_widgets.dart';
import 'package:jasmine/screens/user_screen.dart';

// Local bridge fixtures: no emulator, network, account or native image decoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final properties = <String, String>{};
  final calls = <Map<String, dynamic>>[];
  ViewLog? log;
  var weekFailure = false;
  var historyEmpty = false;
  var downloadRows = <Map<String, dynamic>>[];
  late AlbumResponse album;

  ComicSimple comic(int id) => ComicSimple(
    id: id,
    author: '测试作者',
    description: '',
    name: '测试漫画 $id，较长的标题用于检查排版',
    image: '',
    category: ComicSimpleCategory(),
    categorySub: ComicSimpleCategory(),
    sealed: true,
  );

  setUp(() async {
    properties.clear();
    calls.clear();
    log = null;
    weekFailure = false;
    historyEmpty = false;
    downloadRows = [];
    album = AlbumResponse(
      id: 7,
      name: '星轨旅人',
      author: ['测试作者'],
      images: [],
      description: '一段用于测试折叠与展开的漫画简介。' * 20,
      totalViews: 0,
      likes: 0,
      series: [
        Series(id: 22, name: '第二话', sort: '2'),
        Series(id: 11, name: '第一话', sort: '1'),
      ],
      seriesId: 7,
      commentTotal: 0,
      tags: ['冒险', '日常'],
      works: [],
      relatedList: [],
      liked: false,
      isFavorite: false,
    );
    app_theme.theme = '0';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'invoke') return null;
          final query =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          calls.add(query);
          Object response = '';
          switch (query['method']) {
            case 'load_property':
              response = properties[query['params']] ?? '';
            case 'save_property':
              final data = jsonDecode(query['params'] as String) as Map;
              properties[data['k']] = data['v'];
            case 'find_view_log':
              response = jsonEncode(log?.toJson());
            case 'page_view_log':
            case 'comics':
              response = jsonEncode({
                'search_query': '',
                'total': historyEmpty ? 0 : 6,
                'content':
                    historyEmpty
                        ? []
                        : [for (var i = 1; i <= 6; i++) comic(i).toJson()],
              });
            case 'album':
              response = jsonEncode(album.toJson());
            case 'all_downloads':
              response = jsonEncode(downloadRows);
            case 'categories':
              response = jsonEncode({
                'categories': [
                  {'id': 1, 'name': '分类一', 'slug': 'one', 'total_albums': 6},
                  {'id': 2, 'name': '分类二', 'slug': 'two', 'total_albums': 6},
                ],
                'blocks': [],
              });
            case 'week':
              response = jsonEncode({
                'categories': [
                  {'id': 'edition', 'title': '本期', 'time': '本期'},
                ],
                'type': [
                  {'id': 'type', 'title': '精选'},
                ],
              });
            case 'week_filter':
              if (weekFailure)
                return jsonEncode({
                  'response_data': '',
                  'error_message': 'fixture weekly unavailable',
                });
              response = jsonEncode({
                'total': 3,
                'list': [
                  comic(8).toJson(),
                  comic(9).toJson(),
                  comic(10).toJson(),
                ],
              });
            case 'jm_3x4_cover':
            case 'jm_square_cover':
              return Completer<String>().future;
            case 'forum':
              response = jsonEncode({'total': 0, 'list': []});
          }
          return jsonEncode({'response_data': response, 'error_message': ''});
        });
    await initPagerControllerMode();
    await initPagerViewMode();
    await initPagerColumnCount();
    await initPagerCoverRate();
    await initIgnoreVewLog();
    await initSearchTitleWords();
    await initDisplayJmcode();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget app(Widget child, {bool dark = false, double scale = 1}) =>
      MaterialApp(
        theme: dark ? app_theme.darkTheme : app_theme.lightTheme,
        navigatorObservers: [routeObserver],
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
        home: child,
      );

  Future<void> size(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  test('adaptive grid preserves readability and explicit low density', () {
    expect(readingGridColumns(390, 1, 0), 2);
    expect(readingGridColumns(900, 1, 0), 5);
    expect(readingGridColumns(390, 2, 0), 1);
    expect(readingGridColumns(900, 1, 1), 1);
  });

  test(
    'chapter ordering handles nonnumeric sort without mutating the API model',
    () {
      final series = [
        Series(id: 2, name: '', sort: '10'),
        Series(id: 1, name: '', sort: '2'),
      ];
      expect(sortedReadingSeries(series).map((e) => e.id), [1, 2]);
      expect(series.map((e) => e.id), [2, 1]);
      expect(
        () => sortedReadingSeries([
          ...series,
          Series(id: 3, name: '', sort: '番外'),
        ]),
        returnsNormally,
      );
    },
  );

  test(
    'resume is an explicit reading pointer, not the latest detail visit',
    () async {
      log = ViewLog(
        id: 7,
        author: '',
        description: '',
        name: '读过的漫画',
        lastViewTime: 100,
        lastViewChapterId: 22,
        lastViewPage: 17,
      );
      expect(await loadReadingResume(), isNull);
      properties[lastReadingProperty] = jsonEncode({
        'album_id': 7,
        'chapter_id': 22,
        'chapter_name': '第二话',
      });
      expect((await loadReadingResume())?.position, '第二话 · 第 18 页');
      log = null;
      expect(
        await loadReadingResume(),
        isNull,
        reason: 'cleared history invalidates the stored pointer',
      );
      properties[lastReadingProperty] = '{broken';
      expect(await loadReadingResume(), isNull);
    },
  );

  test('empty chapters do not become the last read chapter', () async {
    final chapter = ChapterResponse(
      id: 22,
      series: [],
      tags: '',
      name: '第二话',
      images: [],
      seriesId: 7,
      isFavorite: false,
      liked: false,
    );
    await rememberReadingChapter(7, chapter);
    expect(properties.containsKey(lastReadingProperty), isFalse);
  });

  for (final (width, scale, dark) in [
    (390.0, 1.0, false),
    (390.0, 2.0, true),
    (600.0, 1.3, false),
    (900.0, 1.0, true),
  ]) {
    testWidgets('cover grid lays out without overflow at $width/$scale/$dark', (
      tester,
    ) async {
      await size(tester, width);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ComicList(
              header: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('发现漫画'),
              ),
              data: [for (var i = 0; i < 6; i++) comic(i)],
            ),
          ),
          scale: scale,
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('发现漫画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'start button supports single-chapter albums and waits for progress',
    (tester) async {
      final single = AlbumResponse.fromJson({...album.toJson(), 'series': []});
      final pending = Completer<ViewLog?>();
      final selected = <int>[];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ContinueReadButton(
              album: single,
              viewFuture: pending.future,
              onChoose: (id, page) => selected.addAll([id, page]),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNull,
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始阅读'));
      expect(selected, [7, 0]);
    },
  );

  testWidgets('resume uses real chapter ID and zero-based saved page', (
    tester,
  ) async {
    final saved = ViewLog(
      id: 7,
      name: '',
      author: '',
      description: '',
      lastViewTime: 0,
      lastViewChapterId: 22,
      lastViewPage: 17,
    );
    final selected = <int>[];
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ContinueReadButton(
            album: album,
            viewFuture: Future.value(saved),
            onChoose: (id, page) => selected.addAll([id, page]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上次读到 第二话 · 第 18 页'), findsOneWidget);
    await tester.tap(find.text('继续阅读'));
    expect(selected, [22, 17]);
  });

  testWidgets(
    'removed chapter starts from first available chapter, without reordering API data',
    (tester) async {
      final saved = ViewLog(
        id: 7,
        name: '',
        author: '',
        description: '',
        lastViewTime: 0,
        lastViewChapterId: 99,
        lastViewPage: 17,
      );
      var selected = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ContinueReadButton(
              album: album,
              viewFuture: Future.value(saved),
              onChoose: (id, _) => selected = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始阅读'));
      expect(selected, 11);
      expect(album.series.first.id, 22);
    },
  );

  testWidgets(
    'reader slider previews before committing and disables one-page dragging',
    (tester) async {
      await size(tester, 390);
      var preview = 0;
      var commits = 0;
      Widget controls(int count) => app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: StatefulBuilder(
              builder:
                  (context, setState) => ReaderBottomControls(
                    page: preview,
                    total: count,
                    onChanged: (value) => setState(() => preview = value),
                    onChangeEnd: (_) => commits++,
                    onContents: () {},
                    onSettings: () {},
                  ),
            ),
          ),
        ),
        scale: 2,
      );
      await tester.pumpWidget(controls(32));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider)),
      );
      await gesture.moveBy(const Offset(45, 0));
      await tester.pump();
      expect(preview, greaterThan(0));
      expect(commits, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(tester.takeException(), isNull);
      preview = 0;
      await tester.pumpWidget(controls(1));
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekly failure leaves discovery and real category filters usable',
    (tester) async {
      weekFailure = true;
      await size(tester, 390);
      await tester.pumpWidget(
        app(BrowserScreen(searchBarController: FloatingSearchBarController())),
      );
      await tester.pumpAndSettle();
      expect(find.text('每周内容暂未加载'), findsOneWidget);
      expect(find.text('发现漫画'), findsOneWidget);
      await tester.tap(find.text('分类二'));
      await tester.pumpAndSettle();
      final requests = calls.where((call) => call['method'] == 'comics');
      expect(
        jsonDecode(requests.last['params'] as String)['categories_slug'],
        'two',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logged-out bookshelf keeps local history and downloads accessible',
    (tester) async {
      historyEmpty = true;
      await size(tester, 390);
      await tester.pumpWidget(app(const UserScreen()));
      await tester.pumpAndSettle();
      expect(find.text('还没有浏览记录'), findsOneWidget);
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('登录后查看收藏'), findsOneWidget);
      await tester.tap(find.text('已下载'));
      await tester.pumpAndSettle();
      expect(find.text('还没有已完成的下载'), findsOneWidget);
      expect(calls.where((call) => call['method'] == 'favorites'), isEmpty);
      await tester.tap(find.text('最近'));
      await tester.pumpAndSettle();
      expect(find.text('最近浏览'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 900.0]) {
    testWidgets('detail reading action stays available across tabs at $width', (
      tester,
    ) async {
      await size(tester, width);
      await tester.pumpWidget(app(const ComicInfoScreen(7, null)));
      await tester.pumpAndSettle();
      expect(find.text('开始阅读'), findsOneWidget);
      await tester.ensureVisible(find.text('推荐'));
      await tester.tap(find.text('推荐'));
      await tester.pumpAndSettle();
      expect(find.text('暂无相关漫画'), findsOneWidget);
      expect(find.text('开始阅读'), findsOneWidget);
      expect(calls.where((call) => call['method'] == 'album').length, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in [
    'PagerControllerMode.stream',
    'PagerControllerMode.pager',
  ]) {
    testWidgets('embedded $mode retains header actions on request errors', (
      tester,
    ) async {
      properties['pager_controller_mode'] = mode;
      await initPagerControllerMode();
      var tapped = false;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ComicPager(
              compact: true,
              header: TextButton(
                onPressed: () => tapped = true,
                child: const Text('切换分类'),
              ),
              onPage: (_) => Future.error(StateError('fixture unavailable')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('切换分类'));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
