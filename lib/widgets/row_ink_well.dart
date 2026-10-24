import 'package:flutter/material.dart';

/// The press highlight of a list row: a rounded rectangle that reaches
/// [bleed] past the row's left and right ends, into the page margin, so the
/// fill does not stop sharp at the first and last letter. The row keeps its
/// own size and touch area; only the ink is wider.
///
/// Use it for rows whose content sits flush with the page margin (tag,
/// setting and entry rows). Cards and chips that have a shape of their own
/// keep [InkWell] with that shape.
class RowInkWell extends InkResponse {
  const RowInkWell({
    super.key,
    super.child,
    super.onTap,
    super.onLongPress,
    this.bleed = defaultBleed,
  }) : super(
         containedInkWell: true,
         highlightShape: BoxShape.rectangle,
         borderRadius: const BorderRadius.all(Radius.circular(cornerRadius)),
       );

  /// How far the ink reaches past each end of the row.
  final double bleed;

  /// Less than the 20 dp page margin, so the ink never meets the screen edge
  /// or a jump rail beside the list.
  static const defaultBleed = 8.0;

  static const cornerRadius = 12.0;

  @override
  RectCallback getRectCallback(RenderBox referenceBox) =>
      () => Rect.fromLTRB(
        -bleed,
        0,
        referenceBox.size.width + bleed,
        referenceBox.size.height,
      );
}
