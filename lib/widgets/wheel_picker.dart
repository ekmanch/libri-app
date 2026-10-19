import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One column of a wheel picker (Add / edit entry › Released: wheel picker): a
/// caption, then a flat, snapping list of [items] with the chosen one in the
/// middle. Rows are [itemExtent] tall and [visibleRows] of them show; the rows
/// above and below the middle fade out. Tapping another row scrolls to it;
/// tapping the chosen row calls [onTapSelected], which the Released sheet uses
/// to switch the year to typing.
class WheelColumn extends StatefulWidget {
  const WheelColumn({
    super.key,
    required this.caption,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.onTapSelected,
  });

  final String caption;
  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;
  final VoidCallback? onTapSelected;

  static const itemExtent = 44.0;
  static const visibleRows = 5;
  static const height = itemExtent * visibleRows;

  /// The caption's height, so a band drawn behind the middle row can line
  /// up with it.
  static const captionHeight = 20.0;

  @override
  State<WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<WheelColumn> {
  late final FixedExtentScrollController _controller;

  /// True while the wheel is moved from outside, so that move is not
  /// reported back as a change.
  bool _following = false;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: widget.selected);
  }

  @override
  void didUpdateWidget(WheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent moved the selection (a day clamped to a shorter month):
    // follow it without a scroll event of our own.
    if (widget.selected != oldWidget.selected &&
        _controller.hasClients &&
        _controller.selectedItem != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        _following = true;
        _controller.jumpToItem(widget.selected);
        _following = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tap(int index) {
    if (index == widget.selected) {
      widget.onTapSelected?.call();
      return;
    }
    _controller.animateToItem(
      index,
      duration: AppMotion.slide,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: WheelColumn.captionHeight,
          child: Text(
            widget.caption,
            style: theme.textTheme.labelMedium!.copyWith(
              fontSize: 12,
              color: colors.muted,
            ),
          ),
        ),
        SizedBox(
          height: WheelColumn.height,
          child: Semantics(
            label: widget.caption,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, 0.3, 0.7, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: WheelColumn.itemExtent,
                physics: const FixedExtentScrollPhysics(),
                // A flat list, not a drum: no perspective to speak of.
                diameterRatio: 100,
                perspective: 0.00001,
                onSelectedItemChanged: (index) {
                  if (!_following) widget.onChanged(index);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: widget.items.length,
                  builder: (context, index) {
                    final on = index == widget.selected;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _tap(index),
                      child: Center(
                        child: Text(
                          widget.items[index],
                          maxLines: 1,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            fontSize: on ? 20 : 17,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            color: on
                                ? theme.colorScheme.onSurface
                                : colors.placeholder,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
