import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    with SingleTickerProviderStateMixin {
  final _node = FocusNode();
  final _textEditingController = TextEditingController();
  late final AnimationController _animationController;
  late final CurvedAnimation _animation;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addStatusListener(_onAnimationStatus);
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubicEmphasized,
    );
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

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && _visible) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
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
                SafeArea(
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
                                            icon: const Icon(Icons.arrow_back),
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
                                                hintText: widget.hint ?? '搜索漫画',
                                                filled: false,
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
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
                                        borderRadius: BorderRadius.circular(28),
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _displayFloatingSearchBar({String? modifyInput}) {
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
    if (!_visible) return;
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
