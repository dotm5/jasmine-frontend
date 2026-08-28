import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/basic/methods.dart';
import 'package:jasmine/configs/local_build.dart';
import 'package:jasmine/configs/pager_column_number.dart';
import 'package:jasmine/configs/pager_controller_mode.dart';
import 'package:jasmine/configs/pager_cover_rate.dart';
import 'package:jasmine/configs/pager_view_mode.dart';
import 'package:jasmine/screens/components/comic_pager.dart';
import 'package:jasmine/screens/local_build_screen.dart';
import 'package:jasmine/screens/init_screen.dart';

// Synthetic content only. No accounts, API servers, images or original core.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final calls = <Map<String, dynamic>>[];
  final properties = <String, String>{};
  var nativeError = '';

  setUp(() {
    calls.clear();
    properties
      ..clear()
      ..addAll({
        'pager_controller_mode': 'PagerControllerMode.pager',
        'pager_view_mode': 'PagerViewMode.info',
      });
    nativeError = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'invoke');
          final query = Map<String, dynamic>.from(
            jsonDecode(call.arguments as String),
          );
          calls.add(query);
          final method = query['method'];
          final response =
              method == 'load_property'
                  ? properties[query['params']] ?? ''
                  : method == 'daily'
                  ? '打卡成功'
                  : '';
          return jsonEncode({
            'response_data': response,
            'error_message': nativeError,
          });
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> configurePager() async {
    await initPagerControllerMode();
    await initPagerViewMode();
    await initPagerColumnCount();
    await initPagerCoverRate();
  }

  InnerComicPage page(int number) => InnerComicPage(
    total: 13,
    list: [
      ComicSimple(
        id: number,
        author: 'fixture',
        description: '',
        name: 'Fixture $number',
        image: '',
        category: ComicSimpleCategory(),
        categorySub: ComicSimpleCategory(),
        sealed:
            true, // Render a placeholder instead of requesting cover images.
      ),
    ],
  );

  test('bridge preserves rename parameters and daily user ID', () async {
    await methods.renameFavoriteFolder(17, '收藏 & +? 📚');
    expect(calls.last['method'], 'rename_favorite_folder');
    expect(jsonDecode(calls.last['params']), ['17', '收藏 & +? 📚']);
    expect(await methods.daily(42), '打卡成功');
    expect(calls.last, {'method': 'daily', 'params': '42'});
    expect(dailyEndpointAvailable && renameFolderEndpointAvailable, isTrue);
  });

  test(
    'bridge preserves mutation errors instead of reporting success',
    () async {
      nativeError = '暂无可签到记录';
      await expectLater(methods.daily(42), throwsStateError);
      nativeError = 'API action failed';
      await expectLater(
        methods.renameFavoriteFolder(17, 'name'),
        throwsStateError,
      );
    },
  );

  testWidgets('feature page uses user-facing descriptions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LocalBuildScreen()));
    expect(find.text('功能与说明'), findsOneWidget);
    expect(find.text('把阅读留给自己'), findsOneWidget);
    expect(find.text('发现与阅读'), findsOneWidget);
    expect(find.textContaining('Release 协议'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets(
    'native startup errors retain a retry screen, not a network redirect',
    (tester) async {
      nativeError = 'Native backend initialization failed';
      await tester.pumpWidget(const MaterialApp(home: InitScreen()));
      await tester.pumpAndSettle();
      expect(find.text('初始化失败'), findsOneWidget);
      expect(find.textContaining(nativeError), findsOneWidget);
      expect(find.text('网络设置'), findsNothing);
      expect(calls.map((call) => call['method']), ['init_dart']);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(calls.map((call) => call['method']), ['init_dart', 'init_dart']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pager moves beyond page ten and supports jumping', (
    tester,
  ) async {
    await configurePager();
    final requested = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicPager(
            onPage: (n) async {
              requested.add(n);
              return page(n);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var n = 2; n <= 12; n++) {
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
    }
    expect(requested, List.generate(12, (i) => i + 1));
    expect(find.text('第 12 / 13 页'), findsOneWidget);
    await tester.tap(find.text('第 12 / 13 页'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '11');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(requested.last, 11);
    expect(find.text('第 11 / 13 页'), findsOneWidget);
    expect(calls.every((call) => call['method'] == 'load_property'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream mode can jump to page eleven', (tester) async {
    properties['pager_controller_mode'] = 'PagerControllerMode.stream';
    await configurePager();
    final requested = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicPager(
            onPage: (n) async {
              requested.add(n);
              return page(n);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Stream mode prefetches while a short result does not fill the viewport.
    expect(requested.first, 1);
    final beforeJump = requested.length;
    await tester.tap(find.textContaining(RegExp(r'^已加载 \d+ / 13 页$')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '11');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(requested[beforeJump], 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty first page does not divide by zero', (tester) async {
    await configurePager();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicPager(
            onPage: (_) async => InnerComicPage(total: 12, list: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 1 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream request may finish after widget disposal', (
    tester,
  ) async {
    properties['pager_controller_mode'] = 'PagerControllerMode.stream';
    await configurePager();
    final response = Completer<InnerComicPage>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ComicPager(onPage: (_) => response.future)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    response.complete(page(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
