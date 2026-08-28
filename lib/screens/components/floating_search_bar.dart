import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';

import 'expressive_page_transitions.dart';

class FloatingSearchBarScreen extends StatefulWidget {
  final FloatingSearchBarController controller;
  final Widget child;
  final ValueChanged<String>? onSubmitted;
  final String? hint;
  final bool showCursor;
  final bool autocorrect;
  final Widget? panel;

  const FloatingSearchBarScreen({
    required this.controller,
    required this.child,
    this.hint,
    this.showCursor = true,
    this.autocorrect = true,
    this.onSubmitted,
    this.panel,
    super.key,
  });

  @override
  State<FloatingSearchBarScreen> createState() =>
      _FloatingSearchBarScreenState();
}

class _FloatingSearchBarScreenState extends State<FloatingSearchBarScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _node = FocusNode();
  final _textEditingController = TextEditingController();
  late final AnimationController _animationController;
  late final CurvedAnimation _animation;
  bool _visible = false;
  bool _closing = false;
  bool _backActive = false;
  late final AnimationController _back;
  SwipeEdge _backEdge = SwipeEdge.left;
  Offset _backOrigin = Offset.zero;
  double _backDy = 0;
  double _backBase = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    )..addStatusListener(_onAnimationStatus);
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubicEmphasized,
      reverseCurve: Curves.easeOutCubic,
    );
    _back = AnimationController(vsync: this);
    WidgetsBinding.instance.addObserver(this);
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(covariant FloatingSearchBarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent == true;
    // An incoming dialog or route takes ownership without dismissing search.
    if (_backActive && !_closing && !current) {
      _backActive = false;
      _back.stop();
      _back.value = 0;
    }
    if (MediaQuery.disableAnimationsOf(context) && _back.isAnimating) {
      _back.stop();
      _back.value = 0;
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && _visible) {
      setState(() {
        _visible = false;
        _closing = false;
        _backActive = false;
      });
      _back.value = 0;
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (!mounted ||
        !_visible ||
        _closing ||
        event.isButtonEvent ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    _backBase = _back.isAnimating ? _back.value : 0;
    _back.stop();
    _backActive = true;
    _backOrigin = event.touchOffset!;
    _backEdge = event.swipeEdge;
    _backDy = 0;
    _back.value = _backBase + (1 - _backBase) * event.progress;
    setState(() {});
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    if (!mounted || !_backActive || _closing) return;
    _backDy = (event.touchOffset?.dy ?? _backOrigin.dy) - _backOrigin.dy;
    _back.value = _backBase + (1 - _backBase) * event.progress;
    setState(() {});
  }

  @override
  void handleCancelBackGesture() {
    if (!mounted || !_backActive || _closing) return;
    _backActive = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _back.value = 0;
    } else {
      _back
          .animateWith(
            SpringSimulation(
              const SpringDescription(mass: 1, stiffness: 900, damping: 60),
              _back.value,
              0,
              0,
              tolerance: const Tolerance(distance: .001, velocity: .01),
            ),
          )
          .whenCompleteOrCancel(() {
            if (mounted && !_backActive && !_closing) _back.value = 0;
          });
    }
  }

  @override
  void handleCommitBackGesture() {
    if (!mounted || !_backActive || _closing) return;
    _hideSearchBar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _back.dispose();
    widget.controller._state = null;
    _node.dispose();
    _textEditingController.dispose();
    _animation.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: !_visible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _visible) _hideSearchBar();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _hideSearchBar,
        },
        child: Scaffold(
          body: Stack(
            children: [
              widget.child,
              if (_visible) ...[
                FadeTransition(
                  opacity: _animation,
                  child: ModalBarrier(
                    color: scheme.scrim.withValues(alpha: .32),
                    onDismiss: _hideSearchBar,
                    semanticsLabel: '关闭搜索',
                  ),
                ),
                AnimatedBuilder(
                  animation: _back,
                  builder:
                      (context, child) => BackGestureSurface(
                        progress:
                            MediaQuery.disableAnimationsOf(context)
                                ? 0
                                : _back.value,
                        edge: _backEdge,
                        verticalDrag: _backDy,
                        ignorePointer: _backActive || _closing,
                        child: child!,
                      ),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: FadeTransition(
                            opacity: _animation,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, -.04),
                                end: Offset.zero,
                              ).animate(_animation),
                              child: FocusScope(
                                autofocus: true,
                                child: Column(
                                  children: [
                                    Material(
                                      color: scheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(28),
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Row(
                                          children: [
                                            IconButton(
                                              tooltip: '关闭搜索',
                                              onPressed: _hideSearchBar,
                                              icon: const Icon(
                                                Icons.arrow_back,
                                              ),
                                            ),
                                            Expanded(
                                              child: TextField(
                                                controller:
                                                    _textEditingController,
                                                focusNode: _node,
                                                showCursor: widget.showCursor,
                                                autocorrect: widget.autocorrect,
                                                textInputAction:
                                                    TextInputAction.search,
                                                onSubmitted: widget.onSubmitted,
                                                decoration: InputDecoration(
                                                  hintText:
                                                      widget.hint ?? '搜索漫画',
                                                  filled: false,
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 12,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (widget.panel != null) ...[
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: Material(
                                          color: scheme.surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: widget.panel,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _displayFloatingSearchBar({String? modifyInput}) {
    _backActive = false;
    _closing = false;
    _back.value = 0;
    if (modifyInput != null) _textEditingController.text = modifyInput;
    setState(() => _visible = true);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animationController.value = 1;
    } else {
      _animationController.forward();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _visible) _node.requestFocus();
    });
  }

  void _hideSearchBar() {
    if (!_visible || _closing) return;
    setState(() => _closing = true);
    _back.stop();
    _node.unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animationController.value = 0;
      if (_visible) setState(() => _visible = false);
    } else {
      _animationController.reverse();
    }
  }
}

class FloatingSearchBarController {
  _FloatingSearchBarScreenState? _state;
  void hide() => _state?._hideSearchBar();
  void display({String? modifyInput}) =>
      _state?._displayFloatingSearchBar(modifyInput: modifyInput);
}
