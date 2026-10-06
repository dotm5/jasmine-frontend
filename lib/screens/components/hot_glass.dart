import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../configs/surface_appearance.dart';

/// Resolves a shared, screen-space key light into the direction seen by one
/// glass surface. Keeping the light anchored to the window prevents every
/// control from rendering the same centre-symmetric reflection.
@visibleForTesting
Offset glassLightDirectionForRect(Rect globalBounds, Size screenSize) {
  const fallback = Offset(-0.78, -0.62);
  if (globalBounds.isEmpty || screenSize.isEmpty) return fallback;

  final lightAnchor = Offset(screenSize.width * 0.16, screenSize.height * 0.10);
  final delta = lightAnchor - globalBounds.center;
  if (!delta.dx.isFinite || !delta.dy.isFinite || delta.distance < 1) {
    return fallback;
  }
  return delta / delta.distance;
}

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
    with TickerProviderStateMixin {
  static Future<List<ui.FragmentProgram>>? _cachedProgram;

  final _surfaceKey = GlobalKey();
  late final AnimationController _press;
  Future<List<ui.FragmentProgram>>? _program;
  ui.FragmentShader? _shader;
  ui.FragmentShader? _backdropShader;
  late final AnimationController _motion;
  Offset _pointer = const Offset(0.5, 0.5);
  double get _velocity => _motion.value;

  bool get _shaderFilterSupported => ui.ImageFilter.isShaderFilterSupported;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 340),
    );
  }

  Future<List<ui.FragmentProgram>>? _ensureProgram() {
    if (!_shaderFilterSupported) return null;
    return _program ??=
        _cachedProgram ??= Future.wait([
          ui.FragmentProgram.fromAsset('shaders/hot_glass.frag'),
          ui.FragmentProgram.fromAsset('shaders/hot_glass_backdrop.frag'),
        ]);
  }

  @override
  void dispose() {
    _shader?.dispose();
    _backdropShader?.dispose();
    _motion.dispose();
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
        _setMotion(nextVelocity);
      });
    }
  }

  void _trackSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !widget.interactive) return;
    _trackPointer(event, includeVelocity: false);
    final speed = (event.scrollDelta.distance / 72).clamp(0.0, 1.0);
    if (mounted) _setMotion(speed);
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

  void _setMotion(double velocity) {
    _motion.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 0;
      return;
    }
    _motion.value = velocity;
    _motion.animateTo(0, curve: Curves.easeOutCubic);
  }

  void _configureShader(ui.FragmentShader shader, Size size) {
    var light = const Offset(-0.78, -0.62);
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final screen = MediaQuery.sizeOf(context);
      final delta =
          box.globalToLocal(Offset(screen.width * .16, screen.height * .10)) -
          box.size.center(Offset.zero);
      if (delta.distance > 1 && delta.dx.isFinite && delta.dy.isFinite) {
        light = delta / delta.distance;
      }
    }
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, _press.value)
      ..setFloat(3, _pointer.dx)
      ..setFloat(4, _pointer.dy)
      ..setFloat(5, (_press.value * widget.morphStrength).clamp(0.0, 1.0))
      ..setFloat(6, _baseRadius)
      ..setFloat(7, widget.fresnel)
      ..setFloat(8, Theme.of(context).brightness == Brightness.dark ? 1 : 0)
      ..setFloat(9, _velocity)
      ..setFloat(10, light.dx)
      ..setFloat(11, light.dy);
  }

  void _configureBackdrop(ui.FragmentShader shader) {
    shader
      ..setFloat(2, widget.refraction)
      ..setFloat(3, widget.dispersion)
      ..setFloat(4, _press.value)
      ..setFloat(5, _pointer.dx)
      ..setFloat(6, _pointer.dy)
      ..setFloat(7, View.of(context).devicePixelRatio)
      ..setFloat(8, _velocity);
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
              // The shader owns the directional rim. A strong uniform border
              // makes the surface read as a symmetric acrylic capsule.
              alpha: theme.brightness == Brightness.dark ? 0.14 : 0.18,
            )
            : scheme.outlineVariant.withValues(alpha: 0.72);

    ui.ImageFilter filter;
    if (active) {
      _configureBackdrop(_backdropShader!);
      filter = ui.ImageFilter.shader(_backdropShader!);
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
              child:
                  active
                      ? CustomPaint(
                      painter: _GlassOpticsPainter(shader, _configureShader),
                        child: widget.child,
                      )
                      : widget.child,
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
            animation: Listenable.merge([_press, _motion]),
            builder: (context, _) {
              if (program == null) return _surface(appearance);
              return FutureBuilder<List<ui.FragmentProgram>>(
                future: program,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return _surface(appearance);
                  _shader ??= snapshot.requireData[0].fragmentShader();
                  _backdropShader ??= snapshot.requireData[1].fragmentShader();
                  return _surface(appearance, shader: _shader);
                },
              );
            },
          );
        },
      );
}

// Geometry is evaluated in the local paint coordinate system, independently of
// the backdrop texture's size, pixel density or parent render-pass origin.
class _GlassOpticsPainter extends CustomPainter {
  _GlassOpticsPainter(this.shader, this.configure);
  final ui.FragmentShader shader;
  final void Function(ui.FragmentShader, Size) configure;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    configure(shader, size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _GlassOpticsPainter oldDelegate) => true;
}
