import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cover_image.dart';

/// One cell of the grid with covers (Library › Movies, grid with covers; Long
/// grid: fast-scroll thumb): the cover, a title of up to two lines and the
/// year. A check badge on the cover means Done; the caption never shows a
/// status. A series grouped as one tile shows one part's cover with a stack
/// badge and the count ([seriesCount]), and the check when every part is
/// done ([done]).
class CoverGridTile extends StatelessWidget {
  const CoverGridTile({
    super.key,
    required this.entry,
    this.onTap,
    this.today,
    this.title,
    this.caption,
    this.seriesCount,
    this.done,
  });

  /// The entry, or the part whose cover stands for a series.
  final Entry entry;
  final VoidCallback? onTap;
  final DateTime? today;

  /// Shown instead of the entry's title, e.g. a rated track on its album.
  final String? title;

  /// Shown instead of the year, e.g. the artist for an album.
  final String? caption;

  /// The parts in a series tile's stack badge; null for a plain entry.
  final int? seriesCount;

  /// Whether to draw the check; the entry's status decides when null.
  final bool? done;

  /// Fixed line boxes, so the grid can size its rows exactly whatever the
  /// platform's font metrics or text scale.
  static const titleFontSize = 13.5;
  static const titleLineHeight = 17.0;
  static const titleLines = 2;
  static const captionFontSize = 12.0;
  static const captionLineHeight = 16.0;

  /// The year, or "Not released yet" (the Library › Movies, grid with covers
  /// note). Never the status.
  static String yearCaption(Entry entry, {DateTime? today}) {
    final released = entry.released;
    if (released != null && !released.isReleasedOn(today ?? DateTime.now())) {
      return 'Not released yet';
    }
    return released?.year.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final done = this.done ?? entry.status == EntryStatus.done;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CoverImage(
                  entry: entry,
                  width: constraints.maxWidth,
                  fontSize: 13,
                ),
                if (done)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: colors.coverBadge,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: StrokeIcon(
                          AppIcons.check,
                          size: 14,
                          color: theme.colorScheme.primary,
                          semanticLabel: 'Done',
                        ),
                      ),
                    ),
                  ),
                if (seriesCount case final count?)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Semantics(
                      label: 'Series, $count',
                      excludeSemantics: true,
                      child: Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        decoration: BoxDecoration(
                          color: colors.coverBadge,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StrokeIcon(
                              AppIcons.stack,
                              size: 13,
                              color: theme.colorScheme.onSurface,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$count',
                              textScaler: TextScaler.noScaling,
                              style: theme.textTheme.labelSmall!.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: titleLineHeight * titleLines,
              child: Text(
                title ?? entry.title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: theme.textTheme.labelMedium!.copyWith(
                  fontSize: titleFontSize,
                  height: titleLineHeight / titleFontSize,
                ),
              ),
            ),
            const SizedBox(height: 1),
            SizedBox(
              height: captionLineHeight,
              child: Text(
                caption ?? yearCaption(entry, today: today),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: theme.textTheme.bodySmall!.copyWith(
                  fontSize: captionFontSize,
                  fontStyle: FontStyle.normal,
                  height: captionLineHeight / captionFontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
