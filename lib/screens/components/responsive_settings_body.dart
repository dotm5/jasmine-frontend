import 'package:flutter/material.dart';

class ResponsiveSettingsBody extends StatelessWidget {
  final List<Widget> children;
  const ResponsiveSettingsBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 840 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24
              ? 2
              : 1;
      return SingleChildScrollView(
        padding: EdgeInsets.all(columns == 2 ? 24 : 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      key: ValueKey('settings-column-$column'),
                      children: [
                        for (var i = column; i < children.length; i += columns)
                          children[i],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
