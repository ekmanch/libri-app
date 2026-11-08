import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A press highlight that hugs a control's content instead of filling its
/// whole touch area: a stadium, like the pills, [padding] past the
/// [InkBounds] inside [child]. The touch area stays the full size of [child], so a
/// tab or a text button keeps a generous target while the feedback sits on
/// what the finger meant to press.
///
/// Without an [InkBounds] below it, the ink fills the whole control.
class ContentInkWell extends InkResponse {
  const ContentInkWell({
    super.key,
    required super.child,
    super.onTap,
    this.padding = defaultPadding,
  }) : super(
         containedInkWell: true,
         highlightShape: BoxShape.rectangle,
         customBorder: const StadiumBorder(),
       );

  /// How far the ink reaches past the [InkBounds] on each side.
  final EdgeInsets padding;

  static const defaultPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );

  @override
  RectCallback getRectCallback(RenderBox referenceBox) => () {
    final bounds = _findBounds(referenceBox);
    if (bounds == null || !bounds.hasSize) {
      return Offset.zero & referenceBox.size;
    }
    final rect = MatrixUtils.transformRect(
      bounds.getTransformTo(referenceBox),
      Offset.zero & bounds.size,
    );
    return padding.inflateRect(rect);
  };

  static _RenderInkBounds? _findBounds(RenderObject node) {
    _RenderInkBounds? found;
    node.visitChildren((child) {
      found ??= child is _RenderInkBounds ? child : _findBounds(child);
    });
    return found;
  }
}

/// Marks the content that a [ContentInkWell] above it draws its ink
/// around. Changes nothing about layout or painting.
class InkBounds extends SingleChildRenderObjectWidget {
  const InkBounds({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderInkBounds();
}

class _RenderInkBounds extends RenderProxyBox {}
