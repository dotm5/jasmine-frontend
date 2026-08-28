import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/basic/navigator.dart';
import 'package:jasmine/configs/display_jmcode.dart';
import 'package:jasmine/configs/ignore_view_log.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/configs/search_title_words.dart';
import 'package:jasmine/configs/theme.dart' as app_theme;
import 'package:jasmine/screens/comic_info_screen.dart';
import 'package:jasmine/screens/components/comic_list.dart';
import 'package:jasmine/screens/user_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const channel = MethodChannel('methods');
  final properties = <String, String>{};
  final requestedPages = <int>[];
  Completer<void>? refreshGate;
  var updated = false;
  var refreshFails = false;

  ComicSimple comic(int id) => ComicSimple(
    id: id,
    name: '${updated ? '更新漫画' : '收藏漫画'} $id',
    author: '测试作者',
    description: '',
    image: '',
    category: ComicSimpleCategory(),
    categorySub: ComicSimpleCategory(),
  );

  setUp(() async {
    properties.clear();
    requestedPages.clear();
    refreshGate = null;
    updated = false;
    refreshFails = false;
    favData = [];
    app_theme.theme = '0';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'invoke') return null;
          final query = jsonDecode(call.arguments as String) as Map;
          Object response = '';
          switch (query['method']) {
            case 'load_property':
              response = properties[query['params']] ?? '';
            case 'pre_login':
              response = jsonEncode({
                'pre_set': true,
                'pre_login': true,
                'self_info': {
                  'uid': 42,
                  'username': '测试读者',
                  'email': '',
                  'emailverified': '0',
                  'photo': '',
                  'fname': '',
                  'gender': '',
                  'message': '',
                  'coin': 0,
                  'album_favorites': 60,
                  's': '',
                  'level_name': '',
                  'level': 1,
                  'nextLevelExp': 0,
                  'exp': '0',
                  'expPercent': 0.0,
                  'badges': [],
                  'album_favorites_max': 100,
                },
              });
            case 'pro_info_all':
              response = jsonEncode({
                'pro_info_af': {'is_pro': false, 'expire': 0},
                'pro_info_pat': {'is_pro': false},
              });
            case 'daily':
              response = '已签到';
            case 'favorite':
              response = jsonEncode({
                'total': 0,
                'count': 0,
                'list': [],
                'folder_list': [],
              });
            case 'favorites':
              final params = jsonDecode(query['params'] as String) as Map;
              final page = params['page'] as int;
              requestedPages.add(page);
              await refreshGate?.future;
              if (refreshFails) {
                return jsonEncode({
                  'response_data': '',
                  'error_message': 'fixture refresh failure',
                });
              }
              response = jsonEncode({
                'total': 60,
                'count': 20,
                'folder_list': [],
                'list': [
                  for (var id = (page - 1) * 20 + 1; id <= page * 20; id++)
                    comic(id).toJson(),
                ],
              });
            case 'page_view_log':
              final page = int.parse(query['params'] as String);
              await refreshGate?.future;
              response = jsonEncode({
                'search_query': '',
                'total': 60,
                'content': [
                  for (var id = (page - 1) * 20 + 1; id <= page * 20; id++)
                    comic(id).toJson(),
                ],
              });
            case 'find_view_log':
              response = 'null';
            case 'all_downloads':
              response = '[]';
            case 'album':
              final params = jsonDecode(query['params'] as String) as Map;
              final id = params['id'] as int;
              response = jsonEncode(
                AlbumResponse(
                  id: id,
                  name: '收藏漫画 $id',
                  author: ['测试作者'],
                  images: [],
                  description: '',
                  totalViews: 0,
                  likes: 0,
                  series: [],
                  seriesId: id,
                  commentTotal: 0,
                  tags: [],
                  works: [],
                  relatedList: [],
                  liked: false,
                  isFavorite: true,
                ).toJson(),
              );
            case 'jm_3x4_cover':
            case 'jm_square_cover':
              return Completer<String>().future;
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

  Future<void> openShelf(WidgetTester tester, String tab, String mode) async {
    properties['pager_controller_mode'] = mode;
    await initPagerControllerMode();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: app_theme.lightTheme,
        navigatorObservers: [routeObserver],
        home: const UserScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await initLogin(tester.element(find.byType(UserScreen)));
    await tester.pumpAndSettle();
    expect(loginStatus, LoginStatus.loginSuccess);
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  Finder viewport() =>
      find
          .descendant(
            of: find.byType(ComicList),
            matching: find.byType(Scrollable),
          )
          .hitTestable()
          .first;

  double offset(WidgetTester tester) =>
      tester.state<ScrollableState>(viewport()).position.pixels;

  for (final tab in ['收藏', '最近']) {
    for (final mode in [
      'PagerControllerMode.stream',
      'PagerControllerMode.pager',
    ]) {
      for (final secondPage in [false, true]) {
        testWidgets(
          '$tab $mode preserves ${secondPage ? 'page 2' : 'page 1'} on return and refresh',
          (tester) async {
            await openShelf(tester, tab, mode);
            final stream = mode.endsWith('stream');
            if (secondPage) {
              final position =
                  tester.state<ScrollableState>(viewport()).position;
              position.jumpTo(position.maxScrollExtent);
              await tester.pumpAndSettle();
              if (!stream) {
                await tester.ensureVisible(find.text('下一页'));
                await tester.tap(find.text('下一页'));
                await tester.pumpAndSettle();
                tester.state<ScrollableState>(viewport()).position.jumpTo(0);
                await tester.pumpAndSettle();
              }
            }
            final id = secondPage ? 33 : 13;
            await tester.scrollUntilVisible(
              find.text('收藏漫画 $id'),
              500,
              scrollable: viewport(),
            );
            await tester.pumpAndSettle();
            final before = offset(tester);
            expect(before, greaterThan(1000));
            final rowsBefore =
                tester
                    .widget<ComicList>(
                      find.byType(ComicList).hitTestable().first,
                    )
                    .data
                    .length;
            await tester.tap(find.text('收藏漫画 $id'));
            await tester.pumpAndSettle();
            expect(find.byType(ComicInfoScreen), findsOneWidget);
            refreshGate = Completer<void>();
            updated = true;
            await tester.pageBack();
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump();
            expect(
              offset(tester),
              closeTo(before, 1),
              reason: 'Keep the viewport while refreshing',
            );
            expect(find.text('收藏漫画 $id').hitTestable(), findsOneWidget);
            refreshGate!.complete();
            await tester.pumpAndSettle();
            expect(
              offset(tester),
              closeTo(before, 1),
              reason: 'Returning must not remount the shelf pager',
            );
            expect(find.text('更新漫画 $id').hitTestable(), findsOneWidget);
            expect(
              tester
                  .widget<ComicList>(find.byType(ComicList).hitTestable().first)
                  .data
                  .length,
              rowsBefore,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final mode in [
    'PagerControllerMode.stream',
    'PagerControllerMode.pager',
  ]) {
    testWidgets(
      '$mode keeps cached favorites after refresh failure and recovers',
      (tester) async {
        await openShelf(tester, '收藏', mode);
        await tester.scrollUntilVisible(
          find.text('收藏漫画 13'),
          500,
          scrollable: viewport(),
        );
        await tester.pumpAndSettle();
        final before = offset(tester);
        expect(before, greaterThan(1000));
        await tester.tap(find.text('收藏漫画 13'));
        await tester.pumpAndSettle();
        expect(find.byType(ComicInfoScreen), findsOneWidget);
        refreshFails = true;
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(offset(tester), closeTo(before, 1));
        expect(find.text('收藏漫画 13').hitTestable(), findsOneWidget);
        await tester.tap(find.text('收藏漫画 13'));
        await tester.pumpAndSettle();
        refreshFails = false;
        updated = true;
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(offset(tester), closeTo(before, 1));
        expect(find.text('更新漫画 13').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'return during load-more refreshes all retained pages after it finishes',
    (tester) async {
      await openShelf(tester, '收藏', 'PagerControllerMode.stream');
      requestedPages.clear();
      refreshGate = Completer<void>();
      final position = tester.state<ScrollableState>(viewport()).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(requestedPages, [2]);
      await tester.scrollUntilVisible(
        find.text('收藏漫画 13'),
        -300,
        scrollable: viewport(),
      );
      await tester.pump();
      final before = offset(tester);
      await tester.tap(find.text('收藏漫画 13'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ComicInfoScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 400));
      expect(offset(tester), closeTo(before, 1));
      updated = true;
      refreshGate!.complete();
      await tester.pumpAndSettle();
      expect(requestedPages, [2, 1, 2]);
      expect(offset(tester), closeTo(before, 1));
      expect(
        tester
            .widget<ComicList>(find.byType(ComicList).hitTestable().first)
            .data
            .length,
        40,
      );
      expect(find.text('更新漫画 13').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final tab in ['收藏', '最近']) {
    testWidgets('$tab explicit refresh still starts a fresh first page', (
      tester,
    ) async {
      await openShelf(tester, tab, 'PagerControllerMode.stream');
      await tester.scrollUntilVisible(
        find.text('收藏漫画 13'),
        500,
        scrollable: viewport(),
      );
      await tester.pumpAndSettle();
      expect(offset(tester), greaterThan(1000));
      await tester.tap(find.byTooltip('刷新书架'));
      await tester.pumpAndSettle();
      expect(offset(tester), 0);
      expect(tester.takeException(), isNull);
    });
  }
}
