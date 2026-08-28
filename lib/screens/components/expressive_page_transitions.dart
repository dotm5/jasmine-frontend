import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

const readerRouteSettings = RouteSettings(name: '/reader');

/// Allows restoring a canceled preview even if an incoming route covers it.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
    super.barrierDismissible,
  });

  void restoreBackPreview() {
    controller?.value = 1;
  }
}

/// App-owned transitions on the pinned Flutter SDK. The system still decides
/// whether a gesture commits; root back-to-home is deliberately not intercepted.
class ExpressivePageTransitionsBuilder extends PageTransitionsBuilder {
  const ExpressivePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _BackTransition(route: route, animation: animation, child: child);
  }
}

class _BackTransition extends StatefulWidget {
  const _BackTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_BackTransition> createState() => _BackTransitionState();
}

class _BackTransitionState extends State<_BackTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _settle;
  bool _active = false;
  bool _committing = false;
  double _progress = 0;
  double _from = 0;
  double _base = 0;
  int _generation = 0;
  Offset _origin = Offset.zero;
  double _dy = 0;
  SwipeEdge _edge = SwipeEdge.left;
  NavigatorState? _navigator;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this)..addListener(_tick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to coverage changes, including a dialog pushed mid-gesture.
    ModalRoute.of(context);
    if (_active && !widget.route.isCurrent) {
      _generation++;
      _settle.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active && !widget.route.isCurrent) _complete();
      });
    }
    if (_active && _settle.isAnimating && _reduceMotion) _settle.stop();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (!mounted ||
        event.isButtonEvent ||
        !widget.route.isCurrent ||
        (_active
            ? _committing ||
                !_settle.isAnimating ||
                widget.route.popDisposition != RoutePopDisposition.pop
            : !widget.route.popGestureEnabled)) {
      return false;
    }
    final restarting = _active;
    _generation++;
    _settle.stop();
    _base = restarting ? _progress : 0;
    _active = true;
    _committing = false;
    _origin = event.touchOffset!;
    _edge = event.swipeEdge;
    _dy = 0;
    _progress = _base + (1 - _base) * event.progress;
    _navigator = widget.route.navigator;
    // A non-completed route exposes the previous route's retained subtree.
    if (restarting) {
      widget.route.handleUpdateBackGestureProgress(progress: _routeProgress);
    } else {
      widget.route.handleStartBackGesture(progress: _routeProgress);
    }
    setState(() {});
    return true;
  }

  double get _routeProgress => 1 - _progress.clamp(.000001, .999999);

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    if (!mounted || !_active || _settle.isAnimating) return;
    _progress = _base + (1 - _base) * event.progress;
    _dy = (event.touchOffset?.dy ?? _origin.dy) - _origin.dy;
    widget.route.handleUpdateBackGestureProgress(progress: _routeProgress);
    setState(() {});
  }

  @override
  void handleCancelBackGesture() => _finishGesture(false);

  @override
  void handleCommitBackGesture() => _finishGesture(true);

  void _finishGesture(bool commit) {
    if (!mounted || !_active || _settle.isAnimating) return;
    // Recheck a blocker which may have appeared after the gesture started.
    _committing =
        commit &&
        widget.route.isCurrent &&
        widget.route.popDisposition == RoutePopDisposition.pop;
    _from = _progress;
    final generation = _generation;
    if (_reduceMotion || !widget.route.isCurrent) {
      _complete();
      return;
    }
    _settle.value = 0;
    // Critically damped: continuous recovery without bouncing the comic canvas.
    _settle
        .animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 900, damping: 60),
            0,
            1,
            0,
            tolerance: const Tolerance(distance: .001, velocity: .01),
          ),
        )
        .whenCompleteOrCancel(() {
          if (mounted && _active && generation == _generation) _complete();
        });
  }

  void _tick() {
    if (!_active) return;
    _progress = _from + ((_committing ? 1 : 0) - _from) * _settle.value;
    widget.route.handleUpdateBackGestureProgress(progress: _routeProgress);
    setState(() {});
  }

  void _complete() {
    final commit =
        _committing &&
        widget.route.isCurrent &&
        widget.route.popDisposition == RoutePopDisposition.pop;
    // Finish at the endpoint before invoking the SDK. This avoids its old
    // progress-dependent (up to 800ms) second animation after release.
    if (!commit && widget.route is AppPageRoute) {
      (widget.route as AppPageRoute).restoreBackPreview();
    } else {
      widget.route.handleUpdateBackGestureProgress(progress: commit ? 0 : 1);
    }
    _active = false;
    _committing = false;
    _progress = 0;
    _navigator = null;
    if (commit) {
      widget.route.handleCommitBackGesture();
    } else {
      widget.route.handleCancelBackGesture();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    _settle.dispose();
    // A route removed during a gesture must not leave the navigator locked.
    final navigator = _navigator;
    if (navigator != null &&
        navigator.mounted &&
        navigator.userGestureInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && navigator.userGestureInProgress) {
          navigator.didStopUserGesture();
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = widget.route.settings.name == readerRouteSettings.name;
    return AnimatedBuilder(
      animation: widget.animation,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final reduce = _reduceMotion;
        final progress = _active && !reduce ? _progress : 0.0;
        final normal =
            reduce || _active
                ? 1.0
                : Curves.easeOutCubic.transform(widget.animation.value);
        return BackGestureSurface(
          progress: progress,
          edge: _edge,
          verticalDrag: _dy,
          restrained: reader,
          opacity:
              _active
                  ? (reduce || !_committing ? 1 : 1 - _settle.value)
                  : normal,
          entryOffset: (reader ? 8 : 24) * (1 - normal),
          ignorePointer: _active,
          child: child!,
        );
      },
    );
  }
}

/// Stable wrapper shared by route and search previews. It never reconstructs
/// the content, so canceling preserves focus, scroll position and image state.
class BackGestureSurface extends StatelessWidget {
  const BackGestureSurface({
    required this.progress,
    required this.child,
    this.edge = SwipeEdge.left,
    this.verticalDrag = 0,
    this.restrained = false,
    this.opacity = 1,
    this.entryOffset = 0,
    this.ignorePointer = false,
    super.key,
  });

  final double progress;
  final SwipeEdge edge;
  final double verticalDrag;
  final bool restrained;
  final double opacity;
  final double entryOffset;
  final bool ignorePointer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final p = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final shrink = restrained ? .04 : .1;
    final xLimit = math.max(0.0, size.width * shrink / 2 - 8);
    final yLimit = math.max(0.0, size.height * shrink / 2 - 8);
    final y =
        yLimit == 0
            ? 0.0
            : yLimit * (verticalDrag / (verticalDrag.abs() + 160)) * p;
    return Transform.translate(
      offset: Offset(
        (edge == SwipeEdge.left ? 1 : -1) * xLimit * p + entryOffset,
        y,
      ),
      child: Transform.scale(
        scale: 1 - shrink * p,
        child: ClipRRect(
          borderRadius: BorderRadius.circular((restrained ? 16 : 28) * p),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: IgnorePointer(ignoring: ignorePointer, child: child),
          ),
        ),
      ),
    );
  }
}
