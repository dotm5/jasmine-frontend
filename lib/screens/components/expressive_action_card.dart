import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Expressive emphasis for primary destinations; motion is local, not an
/// emulation of a newer Flutter/Compose component or an official token set.
class ExpressiveActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool secondary;

  const ExpressiveActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.secondary = false,
  });

  @override
  State<ExpressiveActionCard> createState() => _ExpressiveActionCardState();
}

class _ExpressiveActionCardState extends State<ExpressiveActionCard>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);
  double _target = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && _press.isAnimating) {
      _press.stop();
      _press.value = _target;
    }
  }

  void _animate(bool pressed) {
    final target = pressed ? 1.0 : 0.0;
    _target = target;
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.stop();
      _press.value = target;
      return;
    }
    _press.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 500, damping: 32),
        _press.value,
        target,
        _press.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        widget.secondary ? scheme.tertiaryContainer : scheme.secondaryContainer;
    final foreground =
        widget.secondary
            ? scheme.onTertiaryContainer
            : scheme.onSecondaryContainer;
    return AnimatedBuilder(
      animation: _press,
      builder: (context, _) {
        final progress = _press.value.clamp(0.0, 1.0);
        final shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28 - 12 * progress),
        );
        return Transform.scale(
          scale: 1 - .025 * progress,
          child: Semantics(
            button: true,
            child: Material(
              color: background,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: shape,
                onTap: widget.onTap,
                onTapDown: (_) => _animate(true),
                onTapUp: (_) => _animate(false),
                onTapCancel: () => _animate(false),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 104),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: foreground, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: foreground),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_outward_rounded,
                          color: foreground,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
