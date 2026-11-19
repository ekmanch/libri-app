import 'package:flutter/material.dart';

import '../data/models/media_type.dart';
import '../theme/app_theme.dart';

/// A type's color dot. With [ringed] it gets the theme's hairline ring, for
/// a dot that stands alone with no label (the index rail in results with
/// several types), so the light theme's yellow does not vanish on white.
class TypeDot extends StatelessWidget {
  const TypeDot(this.color, {super.key, this.size = 8, this.ringed = false});

  final Color color;
  final double size;
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final ring = LibraryColors.of(context).dotRing;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: ringed && ring.a > 0
            ? [BoxShadow(color: ring, spreadRadius: 1)]
            : null,
      ),
    );
  }
}

/// A line that names a type: the kicker over a title ("MOVIE · 2024" in
/// Library › Entry details), the kind over a match. On dark it is written
/// in the type's color. On light a type color is only ever a fill
/// ([LibraryColors.typeColorsAreFills]), so the line is a dot in that color
/// and the words in the neutral label color.
class TypeKicker extends StatelessWidget {
  const TypeKicker(
    this.text, {
    super.key,
    required this.type,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final MediaType type;

  /// The text style; its color is replaced.
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final color = colors.forType(type);
    if (!colors.typeColorsAreFills) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: color),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TypeDot(color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: colors.muted),
          ),
        ),
      ],
    );
  }
}

/// [label] as a span whose leading "#" is in the theme's tag-hash color
/// (mid gray on light, the text's own color on dark). A label without one
/// comes back whole.
TextSpan tagLabelSpan(BuildContext context, String label) {
  final hash = LibraryColors.of(context).tagHash;
  if (hash == null || !label.startsWith('#')) return TextSpan(text: label);
  return TextSpan(
    children: [
      TextSpan(
        text: '#',
        style: TextStyle(color: hash),
      ),
      TextSpan(text: label.substring(1)),
    ],
  );
}
