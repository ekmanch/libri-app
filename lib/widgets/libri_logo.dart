import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'svg_path.dart';

/// The Libri mark from the canvas (First run › Splash; Welcome): a rounded 7:5
/// tile, peach on the left with a play triangle, paper on the right with three
/// lines.
class LibriLogo extends StatelessWidget {
  const LibriLogo({super.key, this.width = 168});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Libri',
      child: CustomPaint(
        size: Size(width, width * 1000 / 1400),
        painter: const _LogoPainter(),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  // The mark is drawn on a 1400 by 1000 grid, like the SVG on the canvas.
  static final _triangle = parseSvgPath(
    'M200 350a37 37 0 0 1 57-32l238 150a37 37 0 0 1 0 64L257 682'
    'a37 37 0 0 1-57-32z',
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 1400;
    canvas.save();
    canvas.scale(scale);
    const tile = Rect.fromLTWH(0, 0, 1400, 1000);
    canvas.clipRRect(RRect.fromRectAndRadius(tile, const Radius.circular(150)));
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 700, 1000),
      Paint()..color = BrandColors.peach,
    );
    canvas.drawRect(
      const Rect.fromLTWH(700, 0, 700, 1000),
      Paint()..color = BrandColors.paper,
    );
    final ink = Paint()..color = BrandColors.ink;
    canvas.drawPath(_triangle, ink);
    for (final (top, width) in const [(262, 376), (462, 376), (662, 276)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(862, top.toDouble(), width.toDouble(), 76),
          const Radius.circular(38),
        ),
        ink,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
