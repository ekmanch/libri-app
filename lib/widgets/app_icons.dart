import 'package:flutter/material.dart';

/// A stroked line icon drawn on a 24 by 24 grid, matching the icons in the
/// design canvas (round caps and joins, no fill).
@immutable
class StrokeIconData {
  const StrokeIconData({
    this.polylines = const [],
    this.circles = const [],
    this.rects = const [],
    this.strokeWidth = 2,
  });

  final List<List<Offset>> polylines;
  final List<StrokeCircle> circles;
  final List<Rect> rects;

  /// In grid units; scaled with the icon.
  final double strokeWidth;
}

@immutable
class StrokeCircle {
  const StrokeCircle(this.center, this.radius);
  final Offset center;
  final double radius;
}

class AppIcons {
  AppIcons._();

  /// Three book spines.
  static const library = StrokeIconData(
    polylines: [
      [Offset(5, 4), Offset(5, 20)],
      [Offset(10, 4), Offset(10, 20)],
      [Offset(15, 5), Offset(19, 20)],
    ],
  );

  /// A checklist.
  static const plans = StrokeIconData(
    polylines: [
      [Offset(9, 6), Offset(20, 6)],
      [Offset(9, 12), Offset(20, 12)],
      [Offset(9, 18), Offset(20, 18)],
      [Offset(4, 6), Offset(5, 7), Offset(7, 5)],
      [Offset(4, 12), Offset(5, 13), Offset(7, 11)],
      [Offset(4, 18), Offset(5, 19), Offset(7, 17)],
    ],
  );

  static const plus = StrokeIconData(
    strokeWidth: 2.5,
    polylines: [
      [Offset(12, 5), Offset(12, 19)],
      [Offset(5, 12), Offset(19, 12)],
    ],
  );

  static const check = StrokeIconData(
    strokeWidth: 2.5,
    polylines: [
      [Offset(5, 12.5), Offset(9.5, 17), Offset(19, 7.5)],
    ],
  );

  /// A triangle with an exclamation mark (D16).
  static const warning = StrokeIconData(
    polylines: [
      [Offset(12, 3), Offset(21.5, 20), Offset(2.5, 20), Offset(12, 3)],
      [Offset(12, 10), Offset(12, 14)],
      [Offset(12, 17.5), Offset(12, 18)],
    ],
  );

  static const back = StrokeIconData(
    polylines: [
      [Offset(15, 5), Offset(8, 12), Offset(15, 19)],
    ],
  );

  static const chevronRight = StrokeIconData(
    polylines: [
      [Offset(9, 5), Offset(16, 12), Offset(9, 19)],
    ],
  );

  /// An arrow out of a box: the row opens a website (D19).
  static const externalLink = StrokeIconData(
    polylines: [
      [Offset(14, 4), Offset(20, 4), Offset(20, 10)],
      [Offset(20, 4), Offset(11, 13)],
      [
        Offset(18, 14),
        Offset(18, 20),
        Offset(4, 20),
        Offset(4, 6),
        Offset(10, 6),
      ],
    ],
  );

  /// The heavier chevron after a tappable section heading (A1).
  static const chevronRightBold = StrokeIconData(
    strokeWidth: 2.5,
    polylines: [
      [Offset(9, 6), Offset(15, 12), Offset(9, 18)],
    ],
  );

  static const close = StrokeIconData(
    polylines: [
      [Offset(6, 6), Offset(18, 18)],
      [Offset(18, 6), Offset(6, 18)],
    ],
  );

  /// Heavier cross for the small remove button on a chip.
  static const closeBold = StrokeIconData(
    strokeWidth: 2.5,
    polylines: [
      [Offset(6, 6), Offset(18, 18)],
      [Offset(18, 6), Offset(6, 18)],
    ],
  );

  /// Three lines: the text view.
  static const textView = StrokeIconData(
    polylines: [
      [Offset(4, 6), Offset(20, 6)],
      [Offset(4, 12), Offset(20, 12)],
      [Offset(4, 18), Offset(20, 18)],
    ],
  );

  /// Small squares with lines: the list with photos.
  static const listView = StrokeIconData(
    rects: [
      Rect.fromLTWH(4, 4, 4, 4),
      Rect.fromLTWH(4, 10, 4, 4),
      Rect.fromLTWH(4, 16, 4, 4),
    ],
    polylines: [
      [Offset(12, 6), Offset(20, 6)],
      [Offset(12, 12), Offset(20, 12)],
      [Offset(12, 18), Offset(20, 18)],
    ],
  );

  /// Four squares: the grid.
  static const gridView = StrokeIconData(
    rects: [
      Rect.fromLTWH(4, 4, 6, 6),
      Rect.fromLTWH(14, 4, 6, 6),
      Rect.fromLTWH(4, 14, 6, 6),
      Rect.fromLTWH(14, 14, 6, 6),
    ],
  );

  static const chevronDown = StrokeIconData(
    polylines: [
      [Offset(6, 9), Offset(12, 15), Offset(18, 9)],
    ],
  );

  static const search = StrokeIconData(
    circles: [StrokeCircle(Offset(11, 11), 7)],
    polylines: [
      [Offset(16.5, 16.5), Offset(21, 21)],
    ],
  );

  /// Eight short rays: "details fetched online".
  static const sparkle = StrokeIconData(
    polylines: [
      [Offset(12, 3), Offset(12, 6)],
      [Offset(12, 18), Offset(12, 21)],
      [Offset(3, 12), Offset(6, 12)],
      [Offset(18, 12), Offset(21, 12)],
      [Offset(5.6, 5.6), Offset(7.7, 7.7)],
      [Offset(16.3, 16.3), Offset(18.4, 18.4)],
      [Offset(5.6, 18.4), Offset(7.7, 16.3)],
      [Offset(16.3, 7.7), Offset(18.4, 5.6)],
    ],
  );

  /// Three dots: a menu for the thing on this screen (D3).
  static const more = StrokeIconData(
    strokeWidth: 3,
    polylines: [
      [Offset(12, 5), Offset(12, 5.01)],
      [Offset(12, 12), Offset(12, 12.01)],
      [Offset(12, 19), Offset(12, 19.01)],
    ],
  );

  /// A bin, for Delete.
  static const trash = StrokeIconData(
    polylines: [
      [Offset(5, 7), Offset(19, 7)],
      [Offset(10, 7), Offset(10, 5), Offset(14, 5), Offset(14, 7)],
      [Offset(7, 7), Offset(8, 19), Offset(16, 19), Offset(17, 7)],
      [Offset(10, 11), Offset(10, 16)],
      [Offset(14, 11), Offset(14, 16)],
    ],
  );

  /// A heavier check, for the big "all set" disc (F8).
  static const checkBold = StrokeIconData(
    strokeWidth: 2.6,
    polylines: [
      [Offset(5, 12.5), Offset(9.5, 17), Offset(19, 7.5)],
    ],
  );

  /// A git branch: two commits on a line and one branching off (F4).
  static const branch = StrokeIconData(
    circles: [
      StrokeCircle(Offset(6, 5), 2.2),
      StrokeCircle(Offset(6, 19), 2.2),
      StrokeCircle(Offset(18, 7), 2.2),
    ],
    polylines: [
      [Offset(6, 7.2), Offset(6, 16.8)],
      // The curve from the branch's commit down to the main line.
      [
        Offset(18, 9.2),
        Offset(17.9, 11.3),
        Offset(17.1, 12.9),
        Offset(15.6, 14.1),
        Offset(13.6, 15.0),
        Offset(11.3, 15.8),
        Offset(9.1, 16.6),
        Offset(6.8, 17.4),
      ],
    ],
  );

  /// A page with a folded corner and a plus: a new library file (F5).
  static const filePlus = StrokeIconData(
    polylines: [
      [
        Offset(14, 3),
        Offset(5, 3),
        Offset(5, 21),
        Offset(19, 21),
        Offset(19, 8),
        Offset(14, 3),
      ],
      [Offset(14, 3), Offset(14, 8), Offset(19, 8)],
      [Offset(12, 11), Offset(12, 17)],
      [Offset(9, 14), Offset(15, 14)],
    ],
  );

  /// A folder: an existing file (F5).
  static const folder = StrokeIconData(
    polylines: [
      [
        Offset(3, 19),
        Offset(3, 5),
        Offset(9, 5),
        Offset(11, 7),
        Offset(21, 7),
        Offset(21, 19),
        Offset(3, 19),
      ],
    ],
  );

  static const filters = StrokeIconData(
    polylines: [
      [Offset(4, 7), Offset(14, 7)],
      [Offset(18, 7), Offset(20, 7)],
      [Offset(4, 17), Offset(6, 17)],
      [Offset(10, 17), Offset(20, 17)],
      [Offset(16, 5), Offset(16, 9)],
      [Offset(8, 15), Offset(8, 19)],
    ],
  );
}

class StrokeIcon extends StatelessWidget {
  const StrokeIcon(
    this.data, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  final StrokeIconData data;
  final double size;

  /// Defaults to the surrounding icon color.
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _StrokeIconPainter(data, resolved)),
      ),
    );
  }
}

class _StrokeIconPainter extends CustomPainter {
  const _StrokeIconPainter(this.data, this.color);

  final StrokeIconData data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = data.strokeWidth * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final line in data.polylines) {
      final path = Path()..moveTo(line.first.dx * scale, line.first.dy * scale);
      for (final point in line.skip(1)) {
        path.lineTo(point.dx * scale, point.dy * scale);
      }
      canvas.drawPath(path, paint);
    }
    for (final circle in data.circles) {
      canvas.drawCircle(circle.center * scale, circle.radius * scale, paint);
    }
    for (final rect in data.rects) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left * scale,
          rect.top * scale,
          rect.width * scale,
          rect.height * scale,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StrokeIconPainter old) =>
      old.data != data || old.color != color;
}
