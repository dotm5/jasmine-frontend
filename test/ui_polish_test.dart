import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/configs.dart';
import 'package:jasmine/configs/login.dart';
import 'package:jasmine/configs/network_api_host.dart';
import 'package:jasmine/configs/network_cdn_host.dart';
import 'package:jasmine/configs/theme.dart' as app_theme;
import 'package:jasmine/screens/about_screen.dart';
import 'package:jasmine/screens/app_screen.dart';
import 'package:jasmine/screens/components/content_error.dart';
import 'package:jasmine/screens/components/content_loading.dart';
import 'package:jasmine/screens/components/error_types.dart';
import 'package:jasmine/screens/local_build_screen.dart';
import 'package:jasmine/screens/settings_screen.dart';
import 'package:jasmine/screens/user_screen.dart';

// All responses are local fixtures. No network, real account or native backend.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  const channel = MethodChannel('methods');
  const captureDir = String.fromEnvironment('UI_CAPTURE_DIR');
  const captureFont = String.fromEnvironment('UI_CAPTURE_FONT');
  final calls = <Map<String, dynamic>>[];
  var signedIn = false;
  var loginError = false;
  final properties = <String, String>{};
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    // Opt-in, local visual review only; no font is bundled in the application.
    if (captureDir.isNotEmpty && captureFont.isNotEmpty) {
      final bytes = await File(captureFont).readAsBytes();
      for (final family in ['UiReview', 'Roboto']) {
        await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  setUp(() {
    calls.clear();
    signedIn = false;
    loginError = false;
    properties
      ..clear()
      ..addAll({'checkVersionPeriod': '-1'});
    app_theme.theme = '0';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'invoke') return null;
          final query = Map<String, dynamic>.from(
            jsonDecode(call.arguments as String),
          );
          calls.add(query);
          Object response = '';
          switch (query['method']) {
            case 'load_property':
              response = properties[query['params']] ?? '';
            case 'save_property':
              final data = jsonDecode(query['params'] as String) as Map;
              properties[data['k']] = data['v'];
            case 'app_config':
            case 'config_links':
              response = '{}';
            case 'load_download_thread':
              response = '2';
            case 'ping':
            case 'ping_cdn':
              response = '120';
            case 'pro_info_all':
              response = jsonEncode({
                'pro_info_af': {'is_pro': false, 'expire': 0},
                'pro_info_pat': {'is_pro': false},
              });
            case 'pre_login':
              response = jsonEncode({
                'pre_set': signedIn || loginError,
                'pre_login': signedIn && !loginError,
                'message': loginError ? 'fixture login failure' : '',
                'self_info':
                    signedIn
                        ? {
                          'uid': 42,
                          'username': '一个很长的阅读者昵称用于验证窄屏布局',
                          'email': '',
                          'emailverified': '0',
                          'photo': '?v=0?v=',
                          'fname': '',
                          'gender': '',
                          'message': '',
                          'coin': 0,
                          'album_favorites': 0,
                          's': '',
                          'level_name': '',
                          'level': 1,
                          'nextLevelExp': 0,
                          'exp': '0',
                          'expPercent': 0.0,
                          'badges': [],
                          'album_favorites_max': 100,
                        }
                        : null,
              });
            case 'favorite':
              response = jsonEncode({
                'total': 0,
                'count': 0,
                'list': [],
                'folder_list': [],
              });
            case 'daily':
              response = '已签到';
          }
          return jsonEncode({'response_data': response, 'error_message': ''});
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget app(Widget home, {bool dark = false, double scale = 1}) {
    var theme = dark ? app_theme.darkTheme : app_theme.lightTheme;
    if (captureDir.isNotEmpty && captureFont.isNotEmpty) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'UiReview'),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'UiReview'),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: boundaryKey, child: child!),
          ),
      home: home,
    );
  }

  Future<void> size(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> configure(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // rootBundle font/version loading uses actual asynchronous I/O.
    await tester.runAsync(() => initConfigs(context));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captureDir.isEmpty) return;
    final previousShadows = debugDisableShadows;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    void repaint(RenderObject node) {
      node.markNeedsPaint();
      node.visitChildren(repaint);
    }

    try {
      debugDisableShadows = false;
      repaint(boundary);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory(captureDir);
          await dir.create(recursive: true);
          await File(
            '${dir.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    } finally {
      debugDisableShadows = previousShadows;
      repaint(boundary);
      await tester.pumpAndSettle();
    }
  }

  for (final dark in [false, true]) {
    testWidgets('bookshelf and routes, dark=$dark', (tester) async {
      await size(tester, const Size(390, 844));
      await configure(tester);
      await tester.pumpWidget(app(const UserScreen(), dark: dark));
      await tester.pumpAndSettle();
      expect(find.text('书架'), findsOneWidget);
      expect(find.text('收藏夹'), findsOneWidget);
      expect(find.text('浏览历史'), findsOneWidget);
      expect(find.text('下载管理'), findsOneWidget);
      expect(find.text('登录 / 注册'), findsOneWidget);
      await capture(tester, 'bookshelf-${dark ? "dark" : "light"}');

      await tester.tap(find.text('收藏夹'));
      await tester.pumpAndSettle();
      expect(find.text('登录后即可使用收藏夹'), findsOneWidget);
      await tester.tap(find.byTooltip('功能与说明'));
      await tester.pumpAndSettle();
      expect(find.byType(LocalBuildScreen), findsOneWidget);
      await capture(tester, 'features-${dark ? "dark" : "light"}');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await capture(tester, 'settings-${dark ? "dark" : "light"}');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关于 Jasmine'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(find.text('暂未获取更新信息'), findsOneWidget);
      await capture(tester, 'about-${dark ? "dark" : "light"}');
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings sections expand at 320px and 1.8x, dark=$dark', (
      tester,
    ) async {
      await size(tester, const Size(320, 700));
      await configure(tester);
      const sections = [
        '网络连接',
        '账号与收藏',
        '阅读体验',
        '外观与显示',
        '下载与导出',
        '数据同步',
        '隐私与内容',
        '启动与其他',
      ];
      for (final section in sections) {
        // Fresh scroll position and expansion state for each category.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          app(const SettingsScreen(), dark: dark, scale: 1.8),
        );
        await tester.pumpAndSettle();
        final target = find.byKey(PageStorageKey(section));
        await tester.scrollUntilVisible(target, 260);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: target, matching: find.text(section)),
        );
        await tester.pumpAndSettle();
        final tile = tester.widget<ExpansionTile>(target);
        expect(tile.children, isNotEmpty);
        expect(
          find.byWidget(tile.children.last),
          findsOneWidget,
          reason: '$section must actually expand',
        );
        expect(tester.takeException(), isNull, reason: section);
      }
    });

    testWidgets('feedback and feature text adapt to small panes, dark=$dark', (
      tester,
    ) async {
      await size(tester, const Size(320, 480));
      await tester.pumpWidget(
        app(const Scaffold(body: ContentLoading()), dark: dark, scale: 2),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(36, 36),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ContentError(
              error: 'SocketException: fixture network failure',
              stackTrace: null,
              onRefresh: () async {},
            ),
          ),
          dark: dark,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.textContaining('SocketException:'), findsNothing);
      await tester.ensureVisible(find.text('查看错误详情'));
      await tester.tap(find.text('查看错误详情'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SocketException:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(const LocalBuildScreen(), dark: dark, scale: 2),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('开源致谢'), 220);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开源致谢'));
      await tester.pumpAndSettle();
      expect(find.textContaining('jmcomic-downloader'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, dark) in [
    (390.0, false),
    (900.0, false),
    (1280.0, false),
    (1280.0, true),
  ]) {
    testWidgets('adaptive full app at $width, dark=$dark', (tester) async {
      await size(tester, Size(width, 900));
      await configure(tester);
      await tester.pumpWidget(app(const AppScreen(), dark: dark));
      await tester.pumpAndSettle();
      final navigation = find.byType(
        width < 600 ? NavigationBar : NavigationRail,
      );
      expect(navigation, findsOneWidget);
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('书架')).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('我的阅读'), findsOneWidget);
      await capture(tester, 'app-$width-${dark ? "dark" : "light"}');
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-column-1')),
        width >= 840 ? findsOneWidget : findsNothing,
      );
      await capture(
        tester,
        'adaptive-settings-$width-${dark ? "dark" : "light"}',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long signed-in name and login error fit narrow screen', (
    tester,
  ) async {
    await size(tester, const Size(320, 700));
    signedIn = true;
    await configure(tester);
    await tester.pumpWidget(app(const UserScreen(), scale: 2));
    await tester.pumpAndSettle();
    expect(find.text('已签到'), findsOneWidget);
    expect(loginStatus, LoginStatus.loginSuccess);
    expect(tester.takeException(), isNull);
    loginError = true;
    await initLogin(tester.element(find.byType(UserScreen)));
    await tester.pumpAndSettle();
    expect(find.text('登录未完成'), findsOneWidget);
    await tester.tap(find.text('查看错误详情'));
    await tester.pumpAndSettle();
    expect(find.text('fixture login failure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry is single-flight and preserves errors; disposal is safe', (
    tester,
  ) async {
    var count = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ContentError(
            error: 'original error',
            stackTrace: null,
            onRefresh: () {
              count++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    expect(find.text('重试中…'), findsOneWidget);
    await tester.tap(find.text('重试中…'));
    expect(count, 1);
    pending.completeError(StateError('retry failure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看错误详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('retry failure'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final disposed = Completer<void>();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ContentError(
            error: 'new error',
            stackTrace: null,
            onRefresh: () => disposed.future,
          ),
        ),
      ),
    );
    await tester.tap(find.text('重新加载'));
    await tester.pumpWidget(const SizedBox());
    disposed.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('feedback supports unbounded vertical parent', (tester) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(
            children: [
              const ContentLoading(),
              ContentError(
                error: 'fixture error',
                stackTrace: null,
                onRefresh: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long network hosts fit and manual cancel keeps picker', (
    tester,
  ) async {
    await size(tester, const Size(320, 700));
    await initApiHost();
    await initCdnHost();
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(
            children: [
              const ApiOptionRow('a-very-long-content-endpoint.example.test'),
              const CdnOptionRow('a-very-long-image-endpoint.example.test'),
              apiHostSetting(),
              cdnHostSetting(),
            ],
          ),
        ),
        scale: 1.8,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['内容线路', '图片线路']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('手动输入'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动输入'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('取消'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
    expect(calls.where((q) => q['method'] == 'save_api_host').length, 1);
    expect(calls.where((q) => q['method'] == 'save_cdn_host').length, 1);
  });

  testWidgets(
    'theme switches with visible controls without interpolation errors',
    (tester) async {
      await tester.pumpWidget(app(const UserScreen()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const UserScreen(), dark: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const UserScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'network classification is case insensitive, other errors stay generic',
    () {
      expect(errorType('TimeoutException'), ERROR_TYPE_NETWORK);
      expect(errorType('Failed host lookup'), ERROR_TYPE_NETWORK);
      expect(errorType('Permission Denied'), ERROR_TYPE_PERMISSION);
      expect(errorType('unknown image format'), '');
    },
  );

  test(
    'disabled buttons and selection controls retain Material state defaults',
    () {
      for (final theme in [app_theme.lightTheme, app_theme.darkTheme]) {
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve({WidgetState.disabled}), isNull);
        expect(style.backgroundColor!.resolve({}), isNotNull);
        expect(theme.switchTheme.thumbColor, isNull);
        expect(theme.checkboxTheme.fillColor, isNull);
        expect(theme.radioTheme.fillColor, isNull);
      }
    },
  );
}
