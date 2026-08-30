import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jasmine/configs/surface_appearance.dart';
import 'package:jasmine/screens/components/adaptive_app_scaffold.dart';
import 'package:jasmine/screens/components/hot_glass.dart';

void main() {
  setUp(() {
    previewSurfaceStyle(AppSurfaceStyle.liquidGlass);
    previewGlassTransmission(SurfaceAppearance.defaultGlassTransmission);
  });

  test('hot glass shader keeps the complete optical feature contract', () {
    final source = File('shaders/hot_glass.frag').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('shaders/hot_glass.frag'));
    expect(source, contains('uniform float u_refraction'));
    expect(source, contains('uniform float u_dispersion'));
    expect(source, contains('redSample.r'));
    expect(source, contains('blueSample.b'));
    expect(source, contains('pow(1.0 - viewDot, 5.0)'));
    expect(source, contains('uniform vec2 u_pointer'));
    expect(source, contains('uniform float u_velocity'));
    expect(source, contains('uniform float u_morph'));
    expect(source, contains('roundedBoxSdf'));
    expect(source, contains('float luminance'));
    expect(source, contains('float contrastRisk'));
    expect(source, contains('uniform float u_flip_y'));
    expect(source, contains('if (u_flip_y > 0.5)'));
    expect(source, contains('float lens = mix(0.10, 0.92'));
    expect(source, contains('0.06 + edge * 0.86'));
  });

  testWidgets('hot glass fallback preserves child interaction and semantics', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HotGlassCluster(
              child: Material(
                type: MaterialType.transparency,
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('玻璃操作'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    await tester.tap(find.text('玻璃操作'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  test('lower transmission produces a denser liquid-glass tint', () {
    const baseAlpha = .07;
    previewGlassTransmission(SurfaceAppearance.minGlassTransmission);
    final dense = surfaceAppearance.value.resolveActiveTintAlpha(baseAlpha);
    previewGlassTransmission(SurfaceAppearance.maxGlassTransmission);
    final clear = surfaceAppearance.value.resolveActiveTintAlpha(baseAlpha);

    expect(dense, greaterThan(clear));
    expect(dense, closeTo(.53, .001));
    expect(clear, closeTo(.09, .001));
  });

  test('transmission previews clamp values to the supported range', () {
    previewGlassTransmission(-1);
    expect(
      surfaceAppearance.value.glassTransmission,
      SurfaceAppearance.minGlassTransmission,
    );
    previewGlassTransmission(2);
    expect(
      surfaceAppearance.value.glassTransmission,
      SurfaceAppearance.maxGlassTransmission,
    );
  });

  testWidgets('material mode removes optical filters and keeps interaction', (
    tester,
  ) async {
    previewSurfaceStyle(AppSurfaceStyle.material3);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HotGlassCluster(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('纯 Material 操作'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('纯 Material 操作'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transmission slider follows the selected surface style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: glassTransmissionSetting())),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);

    previewSurfaceStyle(AppSurfaceStyle.material3);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('large glass groups keep press morph bounded by their geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: HotGlassCluster(
                borderRadius: BorderRadius.circular(28),
                morphStrength: .08,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HotGlassCluster)),
    );
    await tester.pump(const Duration(milliseconds: 260));
    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(HotGlassCluster),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(
      clip.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      lessThan(50),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile destinations share one fused glass shader container', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveAppScaffold(
          body: const SizedBox.expand(),
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.bookmarks), label: '收藏'),
            NavigationDestination(icon: Icon(Icons.history), label: '最近'),
          ],
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
    expect(
      find.ancestor(
        of: find.byType(NavigationBar),
        matching: find.byType(HotGlassCluster),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('material mode uses the standard non-floating navigation bar', (
    tester,
  ) async {
    previewSurfaceStyle(AppSurfaceStyle.material3);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveAppScaffold(
          body: const SizedBox.expand(),
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: '首页'),
            NavigationDestination(icon: Icon(Icons.bookmarks), label: '收藏'),
          ],
        ),
      ),
    );

    expect(find.byType(HotGlassCluster), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isFalse);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
