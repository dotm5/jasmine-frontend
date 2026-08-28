import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../basic/commons.dart';
import '../basic/methods.dart';

const _seedColor = Color(0xFF6750A4);

ColorScheme _scheme(Brightness brightness, {bool highContrast = false}) =>
    ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      contrastLevel: highContrast ? 1 : .1,
    );

final ColorScheme _lightColorScheme = _scheme(Brightness.light);
final ColorScheme _darkColorScheme = _scheme(Brightness.dark);
final ColorScheme _highContrastLightColorScheme = _scheme(
  Brightness.light,
  highContrast: true,
);
final ColorScheme _highContrastDarkColorScheme = _scheme(
  Brightness.dark,
  highContrast: true,
);

final ThemeData _lightTheme = _buildAppTheme(
  _lightColorScheme,
  Brightness.light,
);
final ThemeData _darkTheme = _buildAppTheme(_darkColorScheme, Brightness.dark);
final ThemeData _highContrastLightTheme = _buildAppTheme(
  _highContrastLightColorScheme,
  Brightness.light,
);
final ThemeData _highContrastDarkTheme = _buildAppTheme(
  _highContrastDarkColorScheme,
  Brightness.dark,
);

ThemeData get lightTheme => theme != "2" ? _lightTheme : _darkTheme;

ThemeData get darkTheme => theme != "1" ? _darkTheme : _lightTheme;

ThemeData get highContrastLightTheme =>
    theme != "2" ? _highContrastLightTheme : _highContrastDarkTheme;

ThemeData get highContrastDarkTheme =>
    theme != "1" ? _highContrastDarkTheme : _highContrastLightTheme;

const _propertyName = "theme";
late String theme = "0";

Map<String, String> _nameMap = {"0": "跟随系统", "1": "浅色", "2": "深色"};

ThemeData _buildAppTheme(ColorScheme scheme, Brightness brightness) {
  final typography = Typography.material2021();
  // Use fully resolved Material text styles for animated theme/button changes.
  final textTheme = typography.englishLike.merge(
    brightness == Brightness.light ? typography.black : typography.white,
  );
  final navLabelStyle = (textTheme.labelSmall ??
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))
      .copyWith(fontWeight: FontWeight.w600);
  final statusBarIconBrightness =
      brightness == Brightness.light ? Brightness.dark : Brightness.light;
  final statusBarBrightness = statusBarIconBrightness;
  final statusBarOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: statusBarIconBrightness,
    statusBarBrightness: statusBarBrightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    typography: typography,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    dialogBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      systemOverlayStyle: statusBarOverlay,
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomAppBarTheme: BottomAppBarTheme(color: scheme.surface, elevation: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      height: 80,
      labelTextStyle: MaterialStatePropertyAll(navLabelStyle),
      iconTheme: MaterialStateProperty.resolveWith(
        (states) => IconThemeData(
          color:
              states.contains(MaterialState.selected)
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: navLabelStyle.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: navLabelStyle.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      surfaceTintColor: scheme.surfaceTint,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: textTheme.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceVariant,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: scheme.primary),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? null : scheme.secondary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? null : scheme.onSecondary,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 56)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: MaterialStatePropertyAll(
          (textTheme.labelLarge ?? const TextStyle(fontWeight: FontWeight.w600))
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? null : scheme.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? null : scheme.onPrimary,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 56)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: MaterialStatePropertyAll(
          (textTheme.labelLarge ?? const TextStyle(fontWeight: FontWeight.w600))
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? null : scheme.primary,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        overlayColor: MaterialStatePropertyAll(scheme.primary.withOpacity(.12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? null : scheme.primary,
        ),
        textStyle: MaterialStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceVariant,
      selectedColor: scheme.secondaryContainer,
      secondarySelectedColor: scheme.primaryContainer,
      labelStyle: textTheme.bodyMedium,
      secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: const StadiumBorder(),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.onSurface.withOpacity(.2),
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withOpacity(.16),
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      circularTrackColor: scheme.surfaceContainerHighest,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      minVerticalPadding: 12,
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
      },
    ),
    // Material 3 resolves selected, unselected and disabled colors from the
    // color scheme. A constant primary override makes an unchecked control
    // look selected and hides disabled states.
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.8,
    ),
  );
}

Future initTheme() async {
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  theme = await methods.loadProperty(_propertyName);
  if (theme == "") {
    theme = "0";
  }
  themeEvent.broadcast();
}

String themeName() {
  return _nameMap[theme] ?? "-";
}

Future chooseTheme(BuildContext context) async {
  String? choose = await chooseMapDialog(
    context,
    title: "选择主题",
    values: _nameMap.map((key, value) => MapEntry(value, key)),
  );
  if (choose != null) {
    await methods.saveProperty(_propertyName, choose);
    theme = choose;
    themeEvent.broadcast();
  }
}

final themeEvent = Event();

Widget themeSetting(BuildContext context) {
  return StatefulBuilder(
    builder: (BuildContext context, void Function(void Function()) setState) {
      return ListTile(
        onTap: () async {
          await chooseTheme(context);
          setState(() => {});
        },
        title: const Text("主题"),
        subtitle: Text(_nameMap[theme] ?? ""),
      );
    },
  );
}
