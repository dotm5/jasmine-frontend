import 'package:flutter/material.dart';

import '../../basic/entities.dart';
import 'hot_glass.dart';
import 'images.dart';
import 'types.dart';

class ReadingSearchEntry extends StatelessWidget {
  const ReadingSearchEntry({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return HotGlassCluster(
      borderRadius: BorderRadius.circular(24),
      fallbackColor: colors.surfaceContainerHigh,
      morphStrength: 0.72,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: colors.onSurface),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '搜索漫画、作者、标签',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReadingSectionHeading extends StatelessWidget {
  const ReadingSectionHeading(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child:
          MediaQuery.textScalerOf(context).scale(14) > 21
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, if (action != null) action!],
              )
              : Row(
                children: [Expanded(child: label), if (action != null) action!],
              ),
    );
  }
}

class ReadingEmptyState extends StatelessWidget {
  const ReadingEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A real cover, with enough space for two lines of accessible text.
class ReadingCoverTile extends StatelessWidget {
  const ReadingCoverTile({
    super.key,
    required this.comic,
    required this.onTap,
    this.onLongPress,
    this.square = false,
    this.showTitle = true,
    this.titleOverlay = false,
    this.subtitle,
    this.imageMenuItems,
  });

  final ComicBasic comic;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool square;
  final bool showTitle;
  final bool titleOverlay;
  final String? subtitle;
  final List<LongPressMenuItem>? imageMenuItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sealed = comic is ComicSimple && (comic as ComicSimple).sealed;
    final title = Text(
      comic.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: titleOverlay ? Colors.white : theme.colorScheme.onSurface,
      ),
    );
    return Semantics(
      button: !sealed && onTap != null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: sealed ? null : onTap,
          onLongPress: sealed ? null : onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: square ? 1 : 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cover =
                          sealed
                              ? ColoredBox(
                                color: theme.colorScheme.surfaceContainerHigh,
                                child: const Center(
                                  child: Icon(Icons.visibility_off_outlined),
                                ),
                              )
                              : square
                              ? JMSquareCover(
                                key: ValueKey('square:${comic.id}'),
                                comicId: comic.id,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                longPressMenuItems: imageMenuItems,
                              )
                              : JM3x4Cover(
                                key: ValueKey('portrait:${comic.id}'),
                                comicId: comic.id,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                longPressMenuItems: imageMenuItems,
                              );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          cover,
                          if (titleOverlay)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                color: const Color(0xBB000000),
                                padding: const EdgeInsets.all(8),
                                child: title,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (showTitle && !titleOverlay) ...[
                const SizedBox(height: 8),
                title,
                if ((subtitle ?? comic.author).trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle ?? comic.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    super.key,
    required this.comic,
    required this.position,
    required this.onContinue,
    this.busy = false,
  });

  final ComicBasic comic;
  final String position;
  final VoidCallback onContinue;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '继续上次阅读',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          comic.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          position,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onContinue,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: Icon(
            busy ? Icons.hourglass_top_rounded : Icons.auto_stories_rounded,
          ),
          label: Text(busy ? '正在打开…' : '继续阅读'),
        ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 22;
            if (compact) return details;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: JM3x4Cover(
                    key: ValueKey('resume:${comic.id}'),
                    comicId: comic.id,
                    width: 112,
                    height: 150,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The control layer only: page images and reading controllers stay untouched.
class ReaderBottomControls extends StatelessWidget {
  const ReaderBottomControls({
    super.key,
    required this.page,
    required this.total,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onContents,
    required this.onSettings,
    this.onPrevious,
    this.onNext,
  });

  final int page;
  final int total;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;
  final VoidCallback onContents;
  final VoidCallback onSettings;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  static double contentHeight(BuildContext context) =>
      101 + MediaQuery.textScalerOf(context).scale(12) * 1.2;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    );
    final value = total > 0 ? page.clamp(0, total - 1) : 0;
    Widget action(IconData icon, String label, VoidCallback? callback) =>
        Expanded(
          child: TextButton(
            onPressed: callback,
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              disabledForegroundColor: colors.onSurface.withValues(alpha: .35),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 25),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 12, height: 1.2)),
              ],
            ),
          ),
        );
    return HotGlassCluster(
      fallbackColor: const Color(0xF018171C),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      activeTintAlpha: .17,
      activeDarkTintAlpha: .5,
      morphStrength: 0.12,
      refraction: 9,
      dispersion: 1.6,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '${total == 0 ? 0 : value + 1} / $total',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: colors.primary,
                              inactiveTrackColor:
                                  colors.surfaceContainerHighest,
                              thumbColor: colors.primary,
                              overlayColor: colors.primary.withValues(
                                alpha: .12,
                              ),
                              valueIndicatorColor: colors.primary,
                              valueIndicatorTextStyle: TextStyle(
                                color: colors.onPrimary,
                              ),
                              showValueIndicator: ShowValueIndicator.always,
                            ),
                            child: Slider(
                              value: value.toDouble(),
                              min: 0,
                              max: total > 1 ? (total - 1).toDouble() : 1,
                              label: '${value + 1} / $total',
                              semanticFormatterCallback:
                                  (value) =>
                                      '第 ${value.round() + 1} 页，共 $total 页',
                              onChanged:
                                  total > 1
                                      ? (value) => onChanged(value.round())
                                      : null,
                              onChangeEnd:
                                  total > 1
                                      ? (value) => onChangeEnd(value.round())
                                      : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        action(Icons.list_alt_rounded, '目录', onContents),
                        action(Icons.skip_previous_rounded, '上一话', onPrevious),
                        action(Icons.skip_next_rounded, '下一话', onNext),
                        action(Icons.tune_rounded, '设置', onSettings),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
