import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jasmine/screens/components/adaptive_app_scaffold.dart';
import 'package:jasmine/screens/components/responsive_settings_body.dart';
import 'package:jasmine/screens/components/expressive_action_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';
import 'package:jasmine/configs/theme.dart' as app_theme;

void main() {
  testWidgets(
    'unopened search can be disposed without creating a late ticker',
    (tester) async {
      final controller = FloatingSearchBarController();
      await tester.pumpWidget(
        MaterialApp(
          home: FloatingSearchBarScreen(
            controller: controller,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      controller.display();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search opens from controller and back dismisses without leaving page',
    (tester) async {
      final controller = FloatingSearchBarController();
      await tester.pumpWidget(
        MaterialApp(
          theme: app_theme.lightTheme,
          home: FloatingSearchBarScreen(
            controller: controller,
            child: const Scaffold(body: Text('underlying page')),
            panel: const Text('search suggestions'),
          ),
        ),
      );
      controller.display();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'retained query');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('underlying page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('window navigation changes retain content state and selection', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selection = 0;
    var creations = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: app_theme.lightTheme,
        home: StatefulBuilder(
          builder:
              (context, setState) => AdaptiveAppScaffold(
                body: _ContinuityProbe(
                  onInit: () => creations++,
                  controller: controller,
                ),
                selectedIndex: selection,
                onDestinationSelected:
                    (value) => setState(() => selection = value),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.explore), label: '浏览'),
                  NavigationDestination(
                    icon: Icon(Icons.bookmarks),
                    label: '书架',
                  ),
                ],
              ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'keep across resize');
    await tester.tap(find.text('书架'));
    await tester.pumpAndSettle();
    expect(selection, 1);
    expect(find.byType(NavigationBar), findsOneWidget);

    for (final size in [
      const Size(900, 700),
      const Size(1280, 800),
      const Size(700, 320),
      const Size(390, 844),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(controller.text, 'keep across resize');
      expect(creations, 1, reason: 'window resize must not recreate content');
      expect(selection, 1);
      expect(
        find.byType(size.width >= 600 ? NavigationRail : NavigationBar),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'settings use two columns and restore a single column for large text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      Widget page(double scale) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: ResponsiveSettingsBody(
              children: [
                Text('Group A'),
                Text('Group B'),
                Text('Group C'),
                Text('Group D'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(1));
      expect(find.byKey(const ValueKey('settings-column-1')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Group B')).dx,
        greaterThan(tester.getTopLeft(find.text('Group A')).dx),
      );
      await tester.pumpWidget(page(2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-column-1')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search fits keyboard, cutouts, wide windows and retains query', (
    tester,
  ) async {
    final controller = FloatingSearchBarController();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var submitted = '';
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: app_theme.darkTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.fromLTRB(16, 32, 0, 24),
            viewInsets: EdgeInsets.only(bottom: 200),
            textScaler: TextScaler.linear(1.8),
          ),
          child: FloatingSearchBarScreen(
            controller: controller,
            onSubmitted: (value) => submitted = value,
            child: const Scaffold(body: Text('behind search')),
            panel: ListView(children: const [Text('suggestion')]),
          ),
        ),
      ),
    );
    controller.display(modifyInput: 'previous query');
    await tester.pumpAndSettle();
    expect(find.text('previous query'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.text('previous query'), findsOneWidget);
    expect(tester.getSize(find.byType(TextField)).width, lessThan(720));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(submitted, 'previous query');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    controller.display();
    await tester.pumpAndSettle();
    expect(find.text('previous query'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.display();
    controller.hide();
    expect(tester.takeException(), isNull);
  });

  testWidgets('expressive press honors reduce motion and keeps tap semantics', (
    tester,
  ) async {
    var taps = 0;
    Widget page(bool reduce) => MaterialApp(
      theme: app_theme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ExpressiveActionCard(
                icon: Icons.bookmarks,
                title: '收藏夹',
                subtitle: '整理收藏',
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('收藏夹')),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(page(true));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  test(
    'Android predictive back, contrast roles and large actions are configured',
    () {
      for (final theme in [
        app_theme.lightTheme,
        app_theme.darkTheme,
        app_theme.highContrastLightTheme,
        app_theme.highContrastDarkTheme,
      ]) {
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<PredictiveBackPageTransitionsBuilder>(),
        );
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
          greaterThanOrEqualTo(48),
        );
        final scheme = theme.colorScheme;
        for (final pair in [
          (scheme.secondary, scheme.onSecondary),
          (scheme.primaryContainer, scheme.onPrimaryContainer),
          (scheme.secondaryContainer, scheme.onSecondaryContainer),
          (scheme.tertiaryContainer, scheme.onTertiaryContainer),
        ]) {
          final a = pair.$1.computeLuminance();
          final b = pair.$2.computeLuminance();
          final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
        expect(
          theme.appBarTheme.systemOverlayStyle!.statusBarColor,
          Colors.transparent,
        );
      }
    },
  );
}

class _ContinuityProbe extends StatefulWidget {
  final VoidCallback onInit;
  final TextEditingController controller;
  const _ContinuityProbe({required this.onInit, required this.controller});
  @override
  State<_ContinuityProbe> createState() => _ContinuityProbeState();
}

class _ContinuityProbeState extends State<_ContinuityProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: TextField(controller: widget.controller));
}
