import 'package:flutter/material.dart';

/// A row that scrolls with the list until it reaches the top, then stays there
/// while the rest scrolls under it (the type chips and the count row of the
/// library home, Library › Home). Pinned rows stack: a second one pins under
/// the first. The row is opaque, on the screen background, so rows passing
/// underneath never show through. [height] is fixed, since a pinned sliver
/// cannot measure its child.
class PinnedSliver extends StatelessWidget {
  const PinnedSliver({super.key, required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedDelegate(
        height: height,
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
  }
}

class _PinnedDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedDelegate({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  // The child fills the fixed extent, whatever its own height: a sliver
  // whose child is shorter than its extent is invalid.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox.expand(
        child: ColoredBox(color: color, child: child),
      );

  @override
  bool shouldRebuild(_PinnedDelegate old) =>
      old.height != height || old.color != color || old.child != child;
}
