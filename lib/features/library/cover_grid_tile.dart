import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/cover_mark.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/entry_row.dart';
import 'cover_grid.dart';

/// One cell of the grid with covers (Library › Movies, grid with covers; Long
/// grid: fast-scroll thumb): the cover, a title of up to two lines and the
/// year right under it, however many lines the title takes (the Library
/// "Grid cells" note). A check badge on the cover means Done; the caption
/// never shows a status. A series grouped as one tile shows one part's cover with a stack
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

  /// The second line: the year, a show's years, or "Not released yet"
  /// ([gridYears]). Never the status.
  static String yearCaption(Entry entry, {DateTime? today}) =>
      gridYears(entry, today: today);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = GridTileText.of(context);
    final done = this.done ?? entry.status == EntryStatus.done;
    final badgeInk = CoverMark.inkOf(
      context,
      otherwise: theme.colorScheme.onSurface,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                CoverImage(
                  entry: entry,
                  width: constraints.maxWidth,
                  text: CoverPlaceholderText.title,
                  placeholderTitle: title,
                  badgeBelow: seriesCount != null,
                ),
                if (done)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: CoverMark(
                      width: 26,
                      height: 26,
                      child: Center(
                        child: StrokeIcon(
                          AppIcons.check,
                          size: 14,
                          color: CoverMark.inkOf(
                            context,
                            otherwise: AccentColors.of(context).link,
                          ),
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
                      child: CoverMark(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StrokeIcon(
                              AppIcons.stack,
                              size: 13,
                              color: badgeInk,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$count',
                              textScaler: TextScaler.noScaling,
                              style: theme.textTheme.labelSmall!.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: badgeInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: GridTileText.coverGap),
            // No room is kept for a second title line: the second line
            // sits right under the title, and the grid measured the row
            // with this same style and width (CoverGridSpec).
            Text(
              title ?? entry.title,
              maxLines: text.titleLines,
              overflow: TextOverflow.ellipsis,
              textScaler: text.scaler,
              style: text.title,
            ),
            const SizedBox(height: GridTileText.captionGap),
            Text(
              caption ?? yearCaption(entry, today: today),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: text.scaler,
              style: text.caption,
            ),
          ],
        ),
      ),
    );
  }
}
