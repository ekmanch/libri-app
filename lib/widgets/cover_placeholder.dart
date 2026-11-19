import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/models/entry.dart';
import '../data/models/media_type.dart';
import '../theme/app_theme.dart';

/// What a [CoverPlaceholder] writes on itself.
enum CoverPlaceholderText {
  /// Nothing: a small cover in a list or on Home, where the title is right
  /// beside it.
  none,

  /// The title: a cover in a grid.
  title,

  /// The title and the creator under it: the large cover on details.
  titleAndCreator,
}

/// Stands in for a cover, shown until the image is on the device (or when
/// there is none): the Library "Placeholder covers" note, the same recipe
/// as the desktop app. A base color picked from the entry's id, a soft
/// highlight from the top-left corner and a fade to dark at the bottom;
/// the title, where there is one, in white bold at the bottom-left.
/// Albums and songs are square, everything else is a 2:3 poster; a game's
/// 3:4 art is cropped to fit it.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.id,
    required this.type,
    required this.width,
    this.title = '',
    this.creator,
    this.text = CoverPlaceholderText.none,
    this.badgeBelow = false,
  });

  /// [entry]'s placeholder; [title] replaces the entry's own.
  CoverPlaceholder.of(
    Entry entry, {
    super.key,
    required this.width,
    String? title,
    this.text = CoverPlaceholderText.none,
    this.badgeBelow = false,
  }) : id = entry.id,
       type = entry.type,
       title = title ?? entry.title,
       creator = entry.creator;

  /// Picks the base color, so a title has the same one here and on the
  /// desktop.
  final String id;
  final MediaType type;
  final double width;
  final String title;
  final String? creator;
  final CoverPlaceholderText text;

  /// Whether a series badge sits in the bottom-left corner; the title then
  /// stands above it.
  final bool badgeBelow;

  static double aspectRatio(MediaType type) =>
      type == MediaType.music ? 1 : 2 / 3;

  /// Same id, same color, on every run and platform, and the desktop
  /// app's pick: each UTF-16 code unit of [id] times its index plus 3,
  /// summed, modulo the palette's length.
  static int paletteIndex(String id, int paletteLength) {
    final units = id.codeUnits;
    var sum = 0;
    for (var i = 0; i < units.length; i++) {
      sum += units[i] * (i + 3);
    }
    return sum % paletteLength;
  }

  /// The base color of [id]'s placeholder, out of [colors]' cover palette.
  static Color baseColor(LibraryColors colors, String id) {
    final palette = colors.coverPlaceholders;
    return palette[paletteIndex(id, palette.length)];
  }

  /// Text sizes larger than this would not fit a cover.
  static const _maxTextScale = 1.3;

  /// The series badge (22 tall, 6 from the edge) and the gap above it,
  /// less the padding already under the title.
  static const _badgeRoom = 6.0 + 22 + 5 - 8;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final height = width / aspectRatio(type);
    final creator = this.creator;
    final large = text == CoverPlaceholderText.titleAndCreator;
    final withCreator = large && creator != null && creator.isNotEmpty;
    final scaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: _maxTextScale);
    final padding = large ? 7.0 : 8.0;
    final titleSize = large ? 11.0 : 12.0;
    const creatorSize = 9.5;
    const lineHeight = 1.2;
    // As many lines of the title as the cover has room for, three at most.
    final room =
        height -
        2 * padding -
        (badgeBelow ? _badgeRoom : 0) -
        (withCreator ? 2 + scaler.scale(creatorSize) * lineHeight : 0);
    final lines = (room / (scaler.scale(titleSize) * lineHeight)).floor().clamp(
      0,
      3,
    );
    final lettered =
        text != CoverPlaceholderText.none && title.isNotEmpty && lines > 0;
    return Semantics(
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _CoverPlaceholderPainter(
            base: baseColor(colors, id),
            highlight: colors.coverHighlight,
            shade: colors.coverShade,
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: !lettered
                ? null
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      padding,
                      padding,
                      padding + (badgeBelow ? _badgeRoom : 0),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: lines,
                          overflow: TextOverflow.ellipsis,
                          textScaler: scaler,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            height: lineHeight,
                            color: colors.onCover,
                          ),
                        ),
                        if (withCreator) ...[
                          const SizedBox(height: 2),
                          Text(
                            creator,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: scaler,
                            style: TextStyle(
                              fontSize: creatorSize,
                              fontWeight: FontWeight.w500,
                              height: lineHeight,
                              color: colors.onCoverMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The three layers of the mockup's CSS, bottom to top: the base color;
/// `linear-gradient(180deg, rgba(0,0,0,0) 45%, rgba(0,0,0,0.42) 100%)`;
/// `radial-gradient(130% 70% at 20% 0%, rgba(255,255,255,0.16),
/// rgba(255,255,255,0) 60%)`.
class _CoverPlaceholderPainter extends CustomPainter {
  const _CoverPlaceholderPainter({
    required this.base,
    required this.highlight,
    required this.shade,
  });

  final Color base;
  final Color highlight;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [shade.withValues(alpha: 0), shade],
          const [0.45, 1],
        ),
    );
    // The highlight is an ellipse, 130% of the width by 70% of the height
    // around a point 20% along the top edge: a circle of radius 1 drawn
    // with the canvas stretched by those radii.
    final centerX = size.width * 0.2;
    final radiusX = size.width * 1.3;
    final radiusY = size.height * 0.7;
    canvas.save();
    canvas.translate(centerX, 0);
    canvas.scale(radiusX, radiusY);
    canvas.drawRect(
      Rect.fromLTRB(
        -centerX / radiusX,
        0,
        (size.width - centerX) / radiusX,
        size.height / radiusY,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          [highlight, highlight.withValues(alpha: 0)],
          const [0, 0.6],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPlaceholderPainter old) =>
      old.base != base || old.highlight != highlight || old.shade != shade;
}
