import 'package:flutter/material.dart';

/// A one-line title that steps down through [sizes] until the text fits, and
/// cuts off with an ellipsis at the smallest size (Plans › Halloween touches to
/// Christmas, long plan name).
class FittedTitle extends StatelessWidget {
  const FittedTitle(
    this.text, {
    super.key,
    required this.style,
    required this.sizes,
  });

  final String text;
  final TextStyle style;

  /// Font sizes to try, largest first.
  final List<double> sizes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        TextStyle styled(double size) =>
            style.copyWith(fontSize: size, letterSpacing: -0.02 * size);
        var chosen = sizes.last;
        for (final size in sizes) {
          // Measure exactly what will be drawn, with a pixel to spare, so
          // a borderline fit cannot come out as an ellipsis.
          final painter = TextPainter(
            text: TextSpan(text: text, style: styled(size)),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final fits = painter.width + 1 <= constraints.maxWidth;
          painter.dispose();
          if (fits) {
            chosen = size;
            break;
          }
        }
        return Text(
          text,
          style: styled(chosen),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
