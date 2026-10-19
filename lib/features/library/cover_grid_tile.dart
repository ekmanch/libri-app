import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cover_image.dart';

/// One cell of the grid with covers (Library › Movies, grid with covers; Long
/// grid: fast-scroll thumb): the cover, a title of up to two lines and the
/// year. A check badge on the cover means Done; the caption never shows a
/// status.
class CoverGridTile extends StatelessWidget {
  const CoverGridTile({
    super.key,
    required this.entry,
    this.onTap,
    this.today,
    this.title,
    this.caption,
  });

  final Entry entry;
  final VoidCallback? onTap;
  final DateTime? today;

  /// Shown instead of the entry's title, e.g. a rated track on its album.
  final String? title;

  /// Shown instead of the year, e.g. the artist for an album.
  final String? caption;

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
    final done = entry.status == EntryStatus.done;
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
