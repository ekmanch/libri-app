import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A mark on a cover: the Done disc at the top right and the series badge
/// at the bottom left of a grid tile. Both are built the same way (the
/// Library "Light theme, the rule" note): on light a solid white shape with
/// a hairline ring and a small shadow, so it reads on a white cover too; on
/// dark the translucent dark shape. [height] tall and fully rounded; a
/// [width] makes it a disc, without one it is as wide as its [child] and
/// [padding].
class CoverMark extends StatelessWidget {
  const CoverMark({
    super.key,
    required this.height,
    this.width,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  final double height;
  final double? width;
  final EdgeInsetsGeometry padding;
  final Widget child;

  /// The color of what a mark holds: the theme's on light, [otherwise] in
  /// the themes that have no color of their own for it.
  static Color inkOf(BuildContext context, {required Color otherwise}) =>
      LibraryColors.of(context).coverMarkInk ?? otherwise;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.coverMark,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: colors.coverMarkShadow,
      ),
      child: child,
    );
  }
}
