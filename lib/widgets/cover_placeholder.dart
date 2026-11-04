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

  @override
  Widget build(BuildContext context) {
    final palette = LibraryColors.of(context).coverPlaceholders;
    final color = palette[paletteIndex(entry.title, palette.length)];
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

/// Stands in for a cover that is not on the device: a plain tile tinted in
/// the type's color, with no letters (Library › Coming soon: list with
/// covers, where the title sits right next to it and an upcoming title often
/// has no art yet). Never an empty box.
class CoverTint extends StatelessWidget {
  const CoverTint({super.key, required this.type, required this.width});

  final MediaType type;
  final double width;

  /// How much of the type's color the tile shows (the canvas draws it at
  /// a quarter).
  static const alpha = 0.25;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: width,
        height: width / CoverPlaceholder.aspectRatio(type),
        decoration: BoxDecoration(
          color: LibraryColors.of(context)
              .forType(type)
              .withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
