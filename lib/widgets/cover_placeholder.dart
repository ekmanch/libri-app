import 'package:flutter/material.dart';

import '../data/models/entry.dart';
import '../data/models/media_type.dart';
import '../theme/app_theme.dart';

/// Stands in for a cover: a colored box
/// with the title in it, shown until the image is on the device (or when
/// there is none). Albums and songs are square, everything else is a
/// 2:3 poster; a game's 3:4 art is cropped to fit it.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.entry,
    required this.width,
    this.fontSize = 7,
  });

  final Entry entry;
  final double width;
  final double fontSize;

  static double aspectRatio(MediaType type) =>
      type == MediaType.music ? 1 : 2 / 3;

  /// Same title, same color, on every run and platform.
  static int paletteIndex(String title, int paletteLength) =>
      title.codeUnits.fold(0, (sum, c) => sum + c) % paletteLength;

  /// The fill for [title]'s placeholder, out of the shared cover palette.
  static Color colorFor(BuildContext context, String title) {
    final palette = LibraryColors.of(context).coverPlaceholders;
    return palette[paletteIndex(title, palette.length)];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context, entry.title);
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: width,
        height: width / aspectRatio(entry.type),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: Text(
          entry.title,
          textAlign: TextAlign.center,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: const Color(0xCCFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// Stands in for a cover that is not on the device where the title sits
/// right next to it (Library › Home; Library › Coming soon: list with
/// covers, where an upcoming title often has no art yet): the
/// [CoverPlaceholder] without its letters, a plain tile in the color picked
/// from [title], so neighbors differ. Never the type's color, never an empty
/// box.
class CoverTile extends StatelessWidget {
  const CoverTile({
    super.key,
    required this.title,
    required this.type,
    required this.width,
  });

  final String title;
  final MediaType type;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: width,
        height: width / CoverPlaceholder.aspectRatio(type),
        decoration: BoxDecoration(
          color: CoverPlaceholder.colorFor(context, title),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
