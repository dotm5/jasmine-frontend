import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Feedback stays readable in a full page, a small pane, or a scrolling list.
class ContentStateLayout extends StatelessWidget {
  final Widget child;
  const ContentStateLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder:
        (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  constraints.hasBoundedHeight
                      ? math.max(0, constraints.maxHeight - 48)
                      : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: child,
              ),
            ),
          ),
        ),
  );
}
