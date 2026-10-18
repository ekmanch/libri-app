import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/cover_image.dart';

/// The top of a details sheet (A6, A22, S7): the cover spot when a photo
/// view is chosen, the kind and year in the type color, the title and the
/// creator.
class EntryHeader extends StatelessWidget {
  const EntryHeader({super.key, required this.entry, required this.showCover});

  final Entry entry;
  final bool showCover;

  /// "MOVIE · 1999", "SONG · 1981", "SHOW · 2025–2026" for a show with
  /// seasons, or just the kind without a date.
  static String kindLine(Entry entry) {
    final years = showYears(entry) ?? entry.year?.toString();
    return [entryKindLabel(entry), ?years].join(' · ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCover) ...[
          CoverImage(entry: entry, width: 84, fontSize: 10, labeled: true),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kindLine(entry),
                  style: theme.textTheme.labelSmall!.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.forType(entry.type),
                  ),
                ),
                const SizedBox(height: 6),
                Text(entry.title, style: theme.textTheme.headlineSmall),
                if (entry.creator case final creator?
                    when creator.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    entry.kind != null && entry.album != null
                        ? '$creator · ${entry.album}'
                        : creator,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontSize: 14.5,
                      height: 1.2,
                      color: colors.muted,
                    ),
                  ),
                ],
                if (entry.hasNewSeason) ...[
                  const SizedBox(height: 8),
                  const OutlineBadge(EntryRow.newSeasonLabel, large: true),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
