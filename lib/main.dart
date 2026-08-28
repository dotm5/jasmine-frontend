import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jasmine/screens/components/mouse_and_touch_scroll_behavior.dart';
import 'package:jasmine/screens/init_screen.dart';
import 'basic/desktop.dart';
import 'basic/navigator.dart';
import 'configs/esc_to_pop.dart';
import 'configs/theme.dart';

void main() async {
  runApp(const Jenny());
}

class Jenny extends StatefulWidget {
  const Jenny({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JennyState();
}

class _JennyState extends State<Jenny> with WidgetsBindingObserver {
  late bool _reduceMotion;

  @override
  void initState() {
    _reduceMotion =
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    WidgetsBinding.instance.addObserver(this);
    onDesktopStart();
    themeEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    onDesktopStop();
    themeEvent.unsubscribe(_setState);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    final value =
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    if (value != _reduceMotion) setState(() => _reduceMotion = value);
  }

  _setState(_) {
    setState(() => {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      scrollBehavior: mouseAndTouchScrollBehavior,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      highContrastTheme: highContrastLightTheme,
      highContrastDarkTheme: highContrastDarkTheme,
      themeAnimationDuration:
          _reduceMotion ? Duration.zero : const Duration(milliseconds: 500),
      themeAnimationCurve: Curves.easeInOutCubicEmphasized,
      navigatorObservers: [routeObserver],
      builder: (BuildContext context, Widget? child) {
        Widget built = child ?? Container();
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          built = Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape &&
                  currentEscToPop()) {
                final navigator = appNavigatorKey.currentState;
                if (navigator != null && navigator.canPop()) {
                  navigator.maybePop();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: built,
          );
        }
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: true,
          ),
          child: built,
        );
      },
      home: const InitScreen(),
    );
  }
}
