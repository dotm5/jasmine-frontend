import 'package:flutter/material.dart';
import '../../basic/entities.dart';
import '../../configs/pager_column_number.dart';
import '../../configs/pager_cover_rate.dart';
import '../../configs/pager_view_mode.dart';
import '../comic_info_screen.dart';
import 'comic_info_card.dart';
import 'expressive_page_transitions.dart';
import 'reading_widgets.dart';
import 'types.dart';

class ComicList extends StatefulWidget {
  const ComicList({
    super.key,
    required this.data,
    this.appendList,
    this.controller,
    this.inScroll = false,
    this.onScroll,
    this.longPressMenuItems,
    this.header,
    this.onReturn,
    this.onComicTap,
    this.subtitleBuilder,
  });

  final bool inScroll;
  final List<ComicBasic> data;
  final List<Widget>? appendList;
  final ScrollController? controller;
  final Function? onScroll;
  final List<ComicLongPressMenuItem>? longPressMenuItems;
  final Widget? header;
  final VoidCallback? onReturn;
  final Future<void> Function(ComicBasic)? onComicTap;
  final String? Function(ComicBasic)? subtitleBuilder;

  @override
  State<ComicList> createState() => _ComicListState();
}

class _ComicListState extends State<ComicList> {
  @override
  void initState() {
    super.initState();
    currentPagerViewModeEvent.subscribe(_update);
    pageColumnEvent.subscribe(_update);
    pagerCoverRateEvent.subscribe(_update);
  }

  @override
  void dispose() {
    currentPagerViewModeEvent.unsubscribe(_update);
    pageColumnEvent.unsubscribe(_update);
    pagerCoverRateEvent.unsubscribe(_update);
    super.dispose();
  }

  void _update(_) {
    if (mounted) setState(() {});
  }

  Future<void> _open(ComicBasic comic) async {
    if (widget.onComicTap != null) {
      await widget.onComicTap!(comic);
    } else {
      await Navigator.of(
        context,
      ).push(AppPageRoute(builder: (_) => ComicInfoScreen(comic.id, comic)));
    }
    if (mounted) widget.onReturn?.call();
  }

  VoidCallback? _menu(ComicBasic comic) {
    final items = widget.longPressMenuItems;
    if (items == null || items.isEmpty) return null;
    return () async {
      final selected = await showModalBottomSheet<ComicLongPressMenuItem>(
        context: context,
        showDragHandle: true,
        builder:
            (context) => SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    ListTile(
                      title: Text(item.title),
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
            ),
      );
      if (selected != null && mounted) selected.onChoose(comic);
    };
  }

  Widget _tile(int index) {
    final comic = widget.data[index];
    final sealed = comic is ComicSimple && comic.sealed;
    if (currentPagerViewMode == PagerViewMode.info && !sealed) {
      return InkWell(
        onTap: () => _open(comic),
        onLongPress: _menu(comic),
        child: ComicInfoCard(comic),
      );
    }
    return ReadingCoverTile(
      key: ValueKey('comic:${comic.id}:$index'),
      comic: comic,
      onTap: () => _open(comic),
      onLongPress: _menu(comic),
      square: currentPagerCoverRate == PagerCoverRate.rateSquare,
      showTitle: currentPagerViewMode != PagerViewMode.cover,
      titleOverlay: currentPagerViewMode == PagerViewMode.titleInCover,
      subtitle: widget.subtitleBuilder?.call(comic),
      imageMenuItems:
          widget.longPressMenuItems
              ?.map(
                (item) =>
                    LongPressMenuItem(item.title, () => item.onChoose(comic)),
              )
              .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = readingGridColumns(width, scale, pagerColumnNumber);
        final cardWidth = (width - 32 - 16 * (columns - 1)) / columns;
        final square = currentPagerCoverRate == PagerCoverRate.rateSquare;
        final withCaption = currentPagerViewMode == PagerViewMode.titleAndCover;
        final extent =
            cardWidth * (square ? 1 : 4 / 3) +
            (withCaption ? 16 + 62 * scale : 0);
        final slivers = <Widget>[
          if (widget.header != null) SliverToBoxAdapter(child: widget.header),
          if (currentPagerViewMode == PagerViewMode.info)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (widget.data[index] is ComicSimple &&
                    (widget.data[index] as ComicSimple).sealed) {
                  return ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: Text(
                      widget.data[index].name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                return _tile(index);
              }, childCount: widget.data.length),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: extent,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _tile(index),
                  childCount: widget.data.length,
                ),
              ),
            ),
          if (widget.appendList != null)
            SliverList(delegate: SliverChildListDelegate(widget.appendList!)),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ];
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) widget.onScroll?.call();
            return false;
          },
          child: CustomScrollView(
            controller: widget.controller,
            shrinkWrap: widget.inScroll,
            primary: false,
            physics:
                widget.inScroll
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
            slivers: slivers,
          ),
        );
      },
    );
  }
}

int readingGridColumns(double width, double textScale, int preferred) {
  final automatic = ((width - 16) / (160 * textScale.clamp(1, 2) + 16))
      .floor()
      .clamp(1, 6);
  return preferred <= 0 ? automatic : preferred.clamp(1, automatic);
}
