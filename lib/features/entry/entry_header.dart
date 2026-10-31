import 'package:flutter/material.dart';

import '../../data/lookup/movie_dates.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../data/models/release_dates.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/labels.dart';

/// The top of a details sheet (Library › Entry details; Music › Album with
/// track ratings; Plans › Entry details (timeline on)): the cover spot when a
/// photo view is chosen, the kind and year in the type color, the title, the
/// creator, a book's page count, and for a movie whose dates by kind are
/// known, with Settings › Movies › Release dates set to Both, "In cinemas
/// Dec 18 · Digital Feb 2027" ([movieDates], [releaseDates]).
class EntryHeader extends StatelessWidget {
  const EntryHeader({
    super.key,
    required this.entry,
    required this.showCover,
    this.movieDates,
    this.releaseDates = ReleaseDates.both,
  });

  final Entry entry;
  final bool showCover;
  final MovieDates? movieDates;
  final ReleaseDates releaseDates;

  /// "MOVIE · 1999", "SONG · 1981", "SHOW · 2025–2026" for a show with
  /// seasons, or just the kind without a date.
  static String kindLine(Entry entry) {
    final years = showYears(entry) ?? entry.year?.toString();
    return [entryKindLabel(entry), ?years].join(' · ').toUpperCase();
  }

  /// "160 pages" for a book with a page count (Library › Book details (page
  /// count)), else null.
  static String? pagesLine(Entry entry) => switch (entry.pages) {
    final pages? when entry.type == MediaType.books && pages > 0 =>
      pages == 1 ? '1 page' : '$pages pages',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14.5,
      height: 1.2,
      color: colors.muted,
    );
    final pages = pagesLine(entry);
    final both = releaseDates == ReleaseDates.both
        ? bothDatesLabel(movieDates, today: DateTime.now())
        : null;
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
                    style: muted,
                  ),
                ],
                if (pages != null) ...[
                  const SizedBox(height: 6),
                  Text(pages, style: muted),
                ],
                if (both != null) ...[
                  const SizedBox(height: 6),
                  Text(both, style: muted),
                ],
                if (entry.hasNewSeasonOn(DateTime.now())) ...[
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
