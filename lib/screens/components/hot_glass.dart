import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../configs/surface_appearance.dart';

/// An opt-in glass surface for UI hotspots, not a replacement for Material 3.
///
/// With Impeller this uses one backdrop shader for the complete child cluster,
/// so adjacent controls share the same refraction and highlight field. Skia and
/// unsupported devices receive a deterministic blur/tint fallback.
class HotGlassCluster extends StatefulWidget {
  const HotGlassCluster({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.fallbackColor,
    this.activeTintAlpha,
    this.activeDarkTintAlpha,
    this.interactive = true,
    this.morphStrength = 0.72,
    this.refraction = 12,
    this.dispersion = 2.2,
    this.fresnel = 1.25,
    this.luminanceBias = 0,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? fallbackColor;

  /// Optional tint used while the runtime shader is active. Keep this below
  /// the fallback opacity so the surface stays transparent without allowing
  /// detailed artwork or text behind a control to compete with its content.
  final double? activeTintAlpha;

  /// Dark surfaces need a denser smoke tint over bright artwork so light
  /// Material foreground roles retain contrast. When omitted, the active
  /// light tint is reused before falling back to the theme default.
  final double? activeDarkTintAlpha;
  final bool interactive;

  /// How far a pressed rounded rectangle moves towards a capsule (or circle
  /// when its bounds are square).
  final double morphStrength;
  final double refraction;
  final double dispersion;
  final double fresnel;
  final double luminanceBias;

  @override
  State<HotGlassCluster> createState() => _HotGlassClusterState();
}

class _HotGlassClusterState extends State<HotGlassCluster>
    with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _cachedProgram;

  final _surfaceKey = GlobalKey();
  final _clock = Stopwatch()..start();
  late final AnimationController _press;
  Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  Offset _pointer = const Offset(0.5, 0.5);
  double _velocity = 0;

  bool get _shaderFilterSupported => ui.ImageFilter.isShaderFilterSupported;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 340),
    );
  }

  Future<ui.FragmentProgram>? _ensureProgram() {
    if (!_shaderFilterSupported) return null;
    return _program ??=
        _cachedProgram ??= ui.FragmentProgram.fromAsset(
          'shaders/hot_glass.frag',
        );
  }

  @override
  void dispose() {
    _shader?.dispose();
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (!widget.interactive) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _press.value = pressed ? 1 : 0;
      return;
    }
    if (pressed) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  void _trackPointer(PointerEvent event, {bool includeVelocity = true}) {
    if (!widget.interactive) return;
    final renderObject =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return;
    final size = renderObject.size;
    if (size.isEmpty) return;
    final next = Offset(
      (event.localPosition.dx / size.width).clamp(0.0, 1.0),
      (event.localPosition.dy / size.height).clamp(0.0, 1.0),
    );
    final nextVelocity =
        includeVelocity
            ? (event.delta.distance / math.max(size.shortestSide * 0.12, 1))
                .clamp(0.0, 1.0)
            : _velocity * 0.72;
    if (mounted) {
      setState(() {
        _pointer = next;
        _velocity = nextVelocity;
      });
    }
  }

  void _trackSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !widget.interactive) return;
    _trackPointer(event, includeVelocity: false);
    final speed = (event.scrollDelta.distance / 72).clamp(0.0, 1.0);
    if (mounted) setState(() => _velocity = speed);
  }

  double get _baseRadius => <double>[
    widget.borderRadius.topLeft.x,
    widget.borderRadius.topRight.x,
    widget.borderRadius.bottomLeft.x,
    widget.borderRadius.bottomRight.x,
  ].reduce(math.max);

  double get _capsuleRadius {
    final renderObject =
        _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) return _baseRadius;
    return math.max(_baseRadius, renderObject.size.shortestSide * 0.5);
  }

  void _configureShader(ui.FragmentShader shader) {
    final dark = Theme.of(context).brightness == Brightness.dark ? 1.0 : 0.0;
    final morph = (_press.value * widget.morphStrength).clamp(0.0, 1.0);
    shader
      ..setFloat(2, _clock.elapsedMicroseconds / Duration.microsecondsPerSecond)
      ..setFloat(3, _press.value)
      ..setFloat(4, _pointer.dx)
      ..setFloat(5, _pointer.dy)
      ..setFloat(6, morph)
      ..setFloat(7, _baseRadius)
      ..setFloat(8, widget.refraction)
      ..setFloat(9, widget.dispersion)
      ..setFloat(10, widget.fresnel)
      ..setFloat(11, widget.luminanceBias)
      ..setFloat(12, dark)
      ..setFloat(13, _velocity)
      ..setFloat(14, 0.28)
      ..setFloat(15, 0.18)
      ..setFloat(16, defaultTargetPlatform == TargetPlatform.android ? 1 : 0);
  }

  Widget _materialSurface() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: _surfaceKey,
      color: widget.fallbackColor ?? scheme.surfaceContainer,
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: .22),
      shape: RoundedRectangleBorder(
        borderRadius: widget.borderRadius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .52)),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.child,
    );
  }

  Widget _surface(SurfaceAppearance appearance, {ui.FragmentShader? shader}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highContrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final active = shader != null;
    final pressValue = _press.value * widget.morphStrength;
    final shape =
        BorderRadius.lerp(
          widget.borderRadius,
          BorderRadius.circular(_capsuleRadius),
          pressValue,
        )!;
    final baseColor = widget.fallbackColor ?? scheme.surface;
    final componentBaseAlpha =
        theme.brightness == Brightness.dark
            ? widget.activeDarkTintAlpha ?? widget.activeTintAlpha ?? 0.11
            : widget.activeTintAlpha ?? 0.07;
    final activeAlpha = appearance.resolveActiveTintAlpha(
      componentBaseAlpha,
      highContrast: highContrast,
    );
    final overlay = baseColor.withValues(
      alpha:
          active
              ? activeAlpha
              : appearance.resolveFallbackTintAlpha(highContrast: highContrast),
    );
    final outline =
        active
            ? Colors.white.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.38 : 0.48,
            )
            : scheme.outlineVariant.withValues(alpha: 0.72);

    ui.ImageFilter filter;
    if (active) {
      _configureShader(shader);
      filter = ui.ImageFilter.shader(shader);
    } else {
      filter = ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16);
    }

    return Listener(
      key: _surfaceKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _trackPointer(event);
        _setPressed(true);
      },
      onPointerMove: _trackPointer,
      onPointerHover: _trackPointer,
      onPointerUp: (event) {
        _trackPointer(event);
        _setPressed(false);
      },
      onPointerCancel: (_) => _setPressed(false),
      onPointerSignal: _trackSignal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.28 : 0.14,
              ),
              blurRadius: active ? 24 : 18,
              spreadRadius: active ? -3 : 0,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: BackdropFilter(
            filter: filter,
            blendMode: BlendMode.srcOver,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: overlay,
                border: Border.all(color: outline),
                borderRadius: shape,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<SurfaceAppearance>(
        valueListenable: surfaceAppearance,
        builder: (context, appearance, _) {
          if (!appearance.isLiquidGlass) return _materialSurface();
          final program = _ensureProgram();
          return AnimatedBuilder(
            animation: _press,
            builder: (context, _) {
              if (program == null) return _surface(appearance);
              return FutureBuilder<ui.FragmentProgram>(
                future: program,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return _surface(appearance);
                  _shader ??= snapshot.requireData.fragmentShader();
                  return _surface(appearance, shader: _shader);
                },
              );
            },
          );
        },
      );
}
