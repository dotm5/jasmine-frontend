import 'package:flutter/material.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

enum AppSurfaceStyle { liquidGlass, material3 }

@immutable
class SurfaceAppearance {
  const SurfaceAppearance({
    this.style = AppSurfaceStyle.liquidGlass,
    this.glassTransmission = defaultGlassTransmission,
  }) : assert(
         glassTransmission >= minGlassTransmission &&
             glassTransmission <= maxGlassTransmission,
       );

  static const double minGlassTransmission = .20;
  static const double maxGlassTransmission = .85;
  static const double defaultGlassTransmission = .42;

  final AppSurfaceStyle style;

  /// Fraction of the background light allowed through a liquid-glass surface.
  /// Lower values produce a denser, more legible surface.
  final double glassTransmission;

  bool get isLiquidGlass => style == AppSurfaceStyle.liquidGlass;

  SurfaceAppearance copyWith({
    AppSurfaceStyle? style,
    double? glassTransmission,
  }) => SurfaceAppearance(
    style: style ?? this.style,
    glassTransmission: _clampTransmission(
      glassTransmission ?? this.glassTransmission,
    ),
  );

  /// Converts the user-facing transmission control into the tint used above
  /// the refracted backdrop. The control intentionally affects density rather
  /// than disabling the refraction, dispersion or Fresnel edge response.
  double resolveActiveTintAlpha(
    double componentBaseAlpha, {
    bool highContrast = false,
  }) {
    final normalized =
        (glassTransmission - minGlassTransmission) /
        (maxGlassTransmission - minGlassTransmission);
    final density = 1 - normalized.clamp(0.0, 1.0);
    final densityTint = .02 + (.46 - .02) * density;
    return (componentBaseAlpha + densityTint + (highContrast ? .10 : 0.0))
        .clamp(.05, .82);
  }

  double resolveFallbackTintAlpha({bool highContrast = false}) {
    final normalized =
        (glassTransmission - minGlassTransmission) /
        (maxGlassTransmission - minGlassTransmission);
    final density = 1 - normalized.clamp(0.0, 1.0);
    return (.66 + .30 * density + (highContrast ? .04 : 0.0)).clamp(.66, .96);
  }

  static double _clampTransmission(double value) =>
      value.clamp(minGlassTransmission, maxGlassTransmission);
}

const _styleProperty = 'surfaceAppearanceMode';
const _transmissionProperty = 'liquidGlassTransmission';
const _liquidGlassValue = 'liquid_glass';
const _material3Value = 'material3';

final ValueNotifier<SurfaceAppearance> surfaceAppearance = ValueNotifier(
  const SurfaceAppearance(),
);

String surfaceStyleName(AppSurfaceStyle style) => switch (style) {
  AppSurfaceStyle.liquidGlass => '液态玻璃',
  AppSurfaceStyle.material3 => '纯 Material Design 3',
};

String _persistedStyle(AppSurfaceStyle style) => switch (style) {
  AppSurfaceStyle.liquidGlass => _liquidGlassValue,
  AppSurfaceStyle.material3 => _material3Value,
};

AppSurfaceStyle _parseStyle(String value) => switch (value) {
  _material3Value => AppSurfaceStyle.material3,
  _ => AppSurfaceStyle.liquidGlass,
};

Future<void> initSurfaceAppearance() async {
  final storedStyle = await methods.loadProperty(_styleProperty);
  final storedTransmission = await methods.loadProperty(_transmissionProperty);
  final parsedTransmission = double.tryParse(storedTransmission);
  final transmission =
      parsedTransmission != null && parsedTransmission.isFinite
          ? SurfaceAppearance._clampTransmission(parsedTransmission)
          : SurfaceAppearance.defaultGlassTransmission;
  surfaceAppearance.value = SurfaceAppearance(
    style: _parseStyle(storedStyle),
    glassTransmission: transmission,
  );
}

void previewSurfaceStyle(AppSurfaceStyle style) {
  surfaceAppearance.value = surfaceAppearance.value.copyWith(style: style);
}

Future<void> saveSurfaceStyle(AppSurfaceStyle style) async {
  previewSurfaceStyle(style);
  await methods.saveProperty(_styleProperty, _persistedStyle(style));
}

void previewGlassTransmission(double value) {
  surfaceAppearance.value = surfaceAppearance.value.copyWith(
    glassTransmission: value,
  );
}

Future<void> saveGlassTransmission(double value) async {
  previewGlassTransmission(value);
  await methods.saveProperty(
    _transmissionProperty,
    surfaceAppearance.value.glassTransmission.toStringAsFixed(2),
  );
}

Future<void> chooseSurfaceStyle(BuildContext context) async {
  final choice = await chooseMapDialog(
    context,
    title: '选择界面材质',
    values: {
      surfaceStyleName(AppSurfaceStyle.liquidGlass): _liquidGlassValue,
      surfaceStyleName(AppSurfaceStyle.material3): _material3Value,
    },
  );
  if (choice != null) await saveSurfaceStyle(_parseStyle(choice));
}

Widget surfaceStyleSetting(BuildContext context) {
  return ValueListenableBuilder<SurfaceAppearance>(
    valueListenable: surfaceAppearance,
    builder:
        (context, appearance, _) => ListTile(
          leading: Icon(
            appearance.isLiquidGlass
                ? Icons.blur_on_rounded
                : Icons.widgets_outlined,
          ),
          title: const Text('界面材质'),
          subtitle: Text(surfaceStyleName(appearance.style)),
          onTap: () => chooseSurfaceStyle(context),
        ),
  );
}

Widget glassTransmissionSetting() {
  return ValueListenableBuilder<SurfaceAppearance>(
    valueListenable: surfaceAppearance,
    builder: (context, appearance, _) {
      final percent = (appearance.glassTransmission * 100).round();
      return ListTile(
        enabled: appearance.isLiquidGlass,
        leading: const Icon(Icons.opacity_rounded),
        title: Text('液态玻璃透光度 · $percent%'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: appearance.glassTransmission,
              min: SurfaceAppearance.minGlassTransmission,
              max: SurfaceAppearance.maxGlassTransmission,
              divisions: 13,
              label: '$percent%',
              onChanged:
                  appearance.isLiquidGlass ? previewGlassTransmission : null,
              onChangeEnd:
                  appearance.isLiquidGlass ? saveGlassTransmission : null,
            ),
            const Text('越低底色越浓、内容越清晰；越高越能看见背景。'),
          ],
        ),
      );
    },
  );
}
