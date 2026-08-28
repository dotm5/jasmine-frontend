import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/theme.dart' as app_theme;
import 'package:jasmine/screens/components/expressive_page_transitions.dart';
import 'package:jasmine/screens/components/floating_search_bar.dart';

Future<dynamic> back(
  WidgetTester tester,
  String method, {
  double progress = 0,
  int edge = 0,
  double y = 300,
  bool button = false,
}) async {
  dynamic response;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture' || method == 'updateBackGestureProgress'
            ? <String, Object?>{
              'progress': progress,
              'swipeEdge': edge,
              'touchOffset':
                  button
                      ? null
                      : <double>[
                        edge == 0 ? 5 + progress * 300 : 795 - progress * 300,
                        y,
                      ],
            }
            : null,
      ),
    ),
    (ByteData? value) {
      if (value != null) {
        response = const StandardMethodCodec().decodeEnvelope(value);
      }
    },
  );
  await tester.pump();
  return response;
}

BackGestureSurface surface(WidgetTester tester, Key key) =>
    tester.widget<BackGestureSurface>(
      find
          .ancestor(
            of: find.byKey(key),
            matching: find.byType(BackGestureSurface),
          )
          .first,
    );

class _Probe extends StatefulWidget {
  const _Probe({required this.created});
  final VoidCallback created;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final text = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.created();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('detail'),
    body: ListView(
      children: [
        TextField(controller: text),
        for (var i = 0; i < 60; i++)
          SizedBox(height: 70, child: Text('row $i')),
      ],
    ),
  );
}

void main() {
  const detail = ValueKey('detail');
  late GlobalKey<NavigatorState> navigator;
  var creations = 0;
  Future<void> setup(
    WidgetTester tester, {
    bool reader = false,
    bool reduce = false,
    Widget? page,
  }) async {
    navigator = GlobalKey<NavigatorState>();
    creations = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: app_theme.lightTheme,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: child!,
            ),
        home: const Scaffold(body: Text('home')),
      ),
    );
    navigator.currentState!.push(
      AppPageRoute<void>(
        settings: reader ? readerRouteSettings : null,
        builder: (_) => page ?? _Probe(created: () => creations++),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final edge in [0, 1]) {
    testWidgets(
      'edge $edge tracks progress, direction and vertical drag; cancel retains state',
      (tester) async {
        await setup(tester);
        await tester.enterText(find.byType(TextField), 'keep query');
        final state = tester.state<_ProbeState>(find.byType(_Probe));
        final before = tester.getCenter(find.byKey(detail));
        expect(await back(tester, 'startBackGesture', edge: edge), true);
        for (final p in [.1, .3, .65, 1.0, .4]) {
          await back(
            tester,
            'updateBackGestureProgress',
            progress: p,
            edge: edge,
            y: 380,
          );
          expect(surface(tester, detail).progress, closeTo(p, .0001));
          final center = tester.getCenter(find.byKey(detail));
          expect(
            (center.dx - before.dx) * (edge == 0 ? 1 : -1),
            greaterThan(0),
          );
          expect(center.dy, greaterThan(before.dy));
          expect(find.text('home'), findsOneWidget);
        }
        await back(tester, 'cancelBackGesture');
        await tester.pumpAndSettle();
        expect(navigator.currentState!.canPop(), true);
        expect(navigator.currentState!.userGestureInProgress, false);
        expect(tester.state(find.byType(_Probe)), same(state));
        expect(state.text.text, 'keep query');
        expect(creations, 1);
        expect(tester.getCenter(find.byKey(detail)), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'commit fades from preview and pops exactly once, including full progress',
    (tester) async {
      for (final progress in [.0, .5, 1.0]) {
        await setup(tester);
        await back(tester, 'startBackGesture');
        await back(tester, 'updateBackGestureProgress', progress: progress);
        await back(tester, 'commitBackGesture');
        await tester.pump(const Duration(milliseconds: 60));
        expect(surface(tester, detail).opacity, lessThan(1));
        await tester.pumpAndSettle();
        expect(find.byKey(detail), findsNothing);
        expect(find.text('home'), findsOneWidget);
        expect(navigator.currentState!.canPop(), false);
        expect(navigator.currentState!.userGestureInProgress, false);
        await back(tester, 'commitBackGesture');
        expect(find.text('home'), findsOneWidget);
      }
    },
  );

  testWidgets('button back fades the outgoing page before disposing it', (
    tester,
  ) async {
    await setup(tester);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(surface(tester, detail).opacity, lessThan(1));
    expect(surface(tester, detail).opacity, greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.byKey(detail), findsNothing);
  });

  testWidgets('root and button events are not captured as gestures', (
    tester,
  ) async {
    await setup(tester);
    expect(await back(tester, 'startBackGesture', button: true), false);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await back(tester, 'startBackGesture'), false);
    expect(navigator.currentState!.userGestureInProgress, false);
  });

  testWidgets(
    'reader uses restrained motion and preserves scroll on cancellation',
    (tester) async {
      await setup(tester, reader: true);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final scroll =
          tester.state<ScrollableState>(find.byType(Scrollable)).position;
      final offset = scroll.pixels;
      await back(tester, 'startBackGesture');
      await back(tester, 'updateBackGestureProgress', progress: .6);
      expect(surface(tester, detail).restrained, true);
      await back(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(scroll.pixels, offset);
      expect(creations, 1);
    },
  );

  testWidgets(
    'reduce motion retains semantics without scale or delayed commit',
    (tester) async {
      await setup(tester, reduce: true);
      await back(tester, 'startBackGesture');
      await back(tester, 'updateBackGestureProgress', progress: .7);
      expect(surface(tester, detail).progress, 0);
      await back(tester, 'cancelBackGesture');
      expect(navigator.currentState!.userGestureInProgress, false);
      await back(tester, 'startBackGesture');
      await back(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.byKey(detail), findsNothing);
    },
  );

  testWidgets('PopScope blockers remain authoritative', (tester) async {
    await setup(
      tester,
      page: const PopScope(canPop: false, child: Text('busy')),
    );
    expect(await back(tester, 'startBackGesture'), false);
    await back(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('busy'), findsOneWidget);
    expect(navigator.currentState!.canPop(), true);
  });

  testWidgets(
    'search previews first, cancel keeps query; commit never pops parent',
    (tester) async {
      final controller = FloatingSearchBarController();
      await setup(
        tester,
        page: FloatingSearchBarScreen(
          controller: controller,
          child: const Scaffold(body: Text('search page')),
        ),
      );
      controller.display();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'saved query');
      final field = tester.widget<TextField>(find.byType(TextField));
      final before = tester.getCenter(find.byType(TextField));
      await back(tester, 'startBackGesture', edge: 1);
      await back(tester, 'updateBackGestureProgress', progress: 1, edge: 1);
      expect(tester.getCenter(find.byType(TextField)).dx, lessThan(before.dx));
      expect(navigator.currentState!.userGestureInProgress, false);
      await back(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'saved query');
      expect(field.focusNode!.hasFocus, true);
      expect(tester.getCenter(find.byType(TextField)), before);
      await back(tester, 'startBackGesture');
      await back(tester, 'updateBackGestureProgress', progress: .5);
      await back(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('search page'), findsOneWidget);
      controller.display();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'saved query',
      );
    },
  );

  testWidgets('a dialog above search owns back and leaves the search intact', (
    tester,
  ) async {
    final controller = FloatingSearchBarController();
    await setup(
      tester,
      page: FloatingSearchBarScreen(
        controller: controller,
        child: const Text('search page'),
      ),
    );
    controller.display();
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.byType(TextField)),
      builder: (_) => const AlertDialog(title: Text('dialog')),
    );
    await tester.pumpAndSettle();
    expect(await back(tester, 'startBackGesture'), false);
    await back(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
    'dialog arriving during search preview restores search without committing it',
    (tester) async {
      final controller = FloatingSearchBarController();
      await setup(
        tester,
        page: FloatingSearchBarScreen(
          controller: controller,
          child: const Text('search page'),
        ),
      );
      controller.display();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'retained');
      final before = tester.getCenter(find.byType(TextField));
      await back(tester, 'startBackGesture');
      await back(tester, 'updateBackGestureProgress', progress: .6);
      showDialog<void>(
        context: tester.element(find.byType(TextField)),
        builder: (_) => const AlertDialog(title: Text('incoming dialog')),
      );
      await tester.pumpAndSettle();
      await back(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('incoming dialog'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(TextField)), before);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'retained',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new gesture can interrupt cancel without jumping to full size', (
    tester,
  ) async {
    await setup(tester);
    await back(tester, 'startBackGesture');
    await back(tester, 'updateBackGestureProgress', progress: .6);
    await back(tester, 'cancelBackGesture');
    await tester.pump(const Duration(milliseconds: 30));
    final progress = surface(tester, detail).progress;
    expect(progress, greaterThan(0));
    expect(await back(tester, 'startBackGesture'), true);
    expect(surface(tester, detail).progress, closeTo(progress, .000001));
    await back(tester, 'updateBackGestureProgress', progress: .5);
    await back(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.byKey(detail), findsNothing);
    expect(navigator.currentState!.userGestureInProgress, false);
  });

  for (final settling in [false, true]) {
    testWidgets(
      'incoming route interrupts preview (settling=$settling) without corrupting back stack',
      (tester) async {
        await setup(tester);
        final original = tester.getCenter(find.byKey(detail));
        await back(tester, 'startBackGesture');
        await back(tester, 'updateBackGestureProgress', progress: .7);
        if (settling) await back(tester, 'cancelBackGesture');
        navigator.currentState!.push(
          AppPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('incoming')),
          ),
        );
        await tester.pumpAndSettle();
        expect(navigator.currentState!.userGestureInProgress, false);
        await back(tester, 'commitBackGesture');
        await tester.pumpAndSettle();
        expect(find.text('incoming'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(tester.getCenter(find.byKey(detail)), original);
        expect(surface(tester, detail).opacity, 1);
        expect(creations, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a blocker added during preview cancels instead of discarding state',
    (tester) async {
      final blocked = ValueNotifier(false);
      addTearDown(blocked.dispose);
      await setup(
        tester,
        page: ValueListenableBuilder<bool>(
          valueListenable: blocked,
          builder: (_, value, child) => PopScope(canPop: !value, child: child!),
          child: const Scaffold(key: detail, body: Text('busy')),
        ),
      );
      await back(tester, 'startBackGesture');
      await back(tester, 'updateBackGestureProgress', progress: .7);
      blocked.value = true;
      await tester.pump();
      await back(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('busy'), findsOneWidget);
      expect(surface(tester, detail).progress, 0);
      expect(navigator.currentState!.userGestureInProgress, false);
    },
  );

  testWidgets('reduce motion can change while a return is settling', (
    tester,
  ) async {
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: app_theme.lightTheme,
        builder:
            (context, child) => ValueListenableBuilder<bool>(
              valueListenable: reduced,
              builder:
                  (_, value, _) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(disableAnimations: value),
                    child: child!,
                  ),
            ),
        home: const Scaffold(body: Text('home')),
      ),
    );
    nav.currentState!.push(
      AppPageRoute<void>(
        builder: (_) => const Scaffold(key: detail, body: Text('detail')),
      ),
    );
    await tester.pumpAndSettle();
    await back(tester, 'startBackGesture');
    await back(tester, 'updateBackGestureProgress', progress: .5);
    await back(tester, 'cancelBackGesture');
    reduced.value = true;
    await tester.pumpAndSettle();
    expect(surface(tester, detail).progress, 0);
    expect(nav.currentState!.userGestureInProgress, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated canceled gestures and disposal release navigator ownership',
    (tester) async {
      await setup(tester);
      for (var i = 0; i < 3; i++) {
        expect(await back(tester, 'startBackGesture'), true);
        await back(tester, 'updateBackGestureProgress', progress: .4);
        await back(tester, 'cancelBackGesture');
        await tester.pumpAndSettle();
      }
      await back(tester, 'startBackGesture');
      await back(tester, 'updateBackGestureProgress', progress: .6);
      navigator.currentState!.removeRoute(
        ModalRoute.of(tester.element(find.byKey(detail)))!,
      );
      await tester.pumpAndSettle();
      await back(tester, 'commitBackGesture');
      expect(navigator.currentState!.userGestureInProgress, false);
      expect(find.text('home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
