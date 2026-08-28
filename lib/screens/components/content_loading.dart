import 'package:flutter/material.dart';
import 'content_state.dart';

class ContentLoading extends StatelessWidget {
  final String label;
  const ContentLoading({super.key, this.label = '正在加载…'});

  @override
  Widget build(BuildContext context) => ContentStateLayout(
    child: Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    ),
  );
}
