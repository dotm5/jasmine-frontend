import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Uses the available window, not the device model or its orientation.
/// The content remains in the same element slot while navigation changes.
class AdaptiveAppScaffold extends StatelessWidget {
  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  const AdaptiveAppScaffold({
    super.key,
    required this.body,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final useRail = constraints.maxWidth >= 600;
      final extended =
          constraints.maxWidth >= 1200 &&
          MediaQuery.textScalerOf(context).scale(14) < 21;
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surfaceContainer,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              SizedBox(
                width: useRail ? (extended ? 240 : 96) : 0,
                child:
                    useRail
                        ? SafeArea(
                          child: LayoutBuilder(
                            builder: (context, railConstraints) {
                              return SingleChildScrollView(
                                child: SizedBox(
                                  height: math.max(
                                    400,
                                    railConstraints.maxHeight,
                                  ),
                                  child: NavigationRail(
                                    key: const ValueKey(
                                      'adaptive-navigation-rail',
                                    ),
                                    extended: extended,
                                    minWidth: 96,
                                    minExtendedWidth: 240,
                                    backgroundColor: scheme.surfaceContainer,
                                    useIndicator: true,
                                    labelType:
                                        extended
                                            ? NavigationRailLabelType.none
                                            : NavigationRailLabelType.all,
                                    leading: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Icon(
                                        Icons.auto_stories_rounded,
                                        color: scheme.primary,
                                        size: 32,
                                      ),
                                    ),
                                    selectedIndex: selectedIndex,
                                    onDestinationSelected:
                                        onDestinationSelected,
                                    destinations:
                                        destinations
                                            .map(
                                              (entry) =>
                                                  NavigationRailDestination(
                                                    icon: entry.icon,
                                                    selectedIcon:
                                                        entry.selectedIcon,
                                                    label: Text(entry.label),
                                                  ),
                                            )
                                            .toList(),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                        : null,
              ),
              Expanded(child: body),
            ],
          ),
        ),
        bottomNavigationBar:
            useRail
                ? null
                : NavigationBar(
                  key: const ValueKey('adaptive-navigation-bar'),
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: destinations,
                ),
      );
    },
  );
}
