import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/released.dart';
import '../../data/models/season.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/row_ink_well.dart';
import '../plans/plan_dates.dart';
import 'library_sort.dart';

/// The three sections of the library home on All (Library › Home), each
/// shown only when it has something, up to [HomeSection.limit] rows each.
enum HomeSectionKind {
  /// Entries whose release date is still ahead, nearest first.
  comingSoon('Coming soon'),

  /// Entries In progress, the most recently changed first.
  inProgress('In progress'),

  /// Entries added in the last [HomeSection.recentDays] days, newest first.
  recentlyAdded('Recently added');

  const HomeSectionKind(this.title);

  final String title;
}

/// One row of a home section: the entry, the detail after its type ("Stephen
/// King", "Season 2", "2024"), and what stands on the right ("Nov 10",
/// "Today"), [emphasized] in the text color rather than the muted one.
@immutable
class HomeRowData {
  const HomeRowData(
    this.entry, {
    this.detail,
    this.right = '',
    this.emphasized = false,
  });

  final Entry entry;
  final String? detail;
  final String right;
  final bool emphasized;

  /// "Book · Stephen King", or just "Book".
  String get subtitle =>
      [entry.type.singular, ?detail].where((s) => s.isNotEmpty).join(' · ');
}

/// A home section with its rows, at most [limit] of [total].
@immutable
class HomeSection {
  const HomeSection(this.kind, this.rows, {required this.total});

  final HomeSectionKind kind;
  final List<HomeRowData> rows;

  /// How many entries belong to the section before the cap, for "See all 7".
  final int total;

  /// Rows per section on the home.
  static const limit = 10;

  /// How far back Recently added looks.
  static const recentDays = 30;
}

/// The home's sections for [entries] (seasonal-only ones already left out by
/// the filter), skipping the empty ones. [changes] says when an entry last
/// changed on this phone ([RecentChanges]); an entry without a record counts
/// from the day it was added.
List<HomeSection> homeSections(
  Iterable<Entry> entries, {
  required DateTime today,
  Map<String, DateTime> changes = const {},
}) {
  final list = entries.toList();
  final sections = [
    _comingSoon(list, today),
    _inProgress(list, changes),
    _recentlyAdded(list, today),
  ];
  return [
    for (final section in sections)
      if (section.rows.isNotEmpty) section,
  ];
}

/// A release still ahead: an entry's own date, or for a show or an anime
/// series the earliest season not yet out ("Wednesday · Season 3").
({Released released, Season? season})? upcomingRelease(
  Entry entry,
  DateTime today,
) {
  if (entry.usesSeasons) {
    Season? next;
    for (final season in entry.seasons ?? const <Season>[]) {
      final released = season.released;
      if (released == null || released.isReleasedOn(today)) continue;
      if (next == null ||
          released.availableFrom.isBefore(next.released!.availableFrom)) {
        next = season;
      }
    }
    return next == null ? null : (released: next.released!, season: next);
  }
  final released = entry.released;
  if (released == null || released.isReleasedOn(today)) return null;
  return (released: released, season: null);
}

/// Exact dates sort first, then month-only, then year-only dates; the
/// nearest first within each.
int _precision(Released r) => r.day != null ? 0 : (r.month != null ? 1 : 2);

HomeSection _comingSoon(List<Entry> entries, DateTime today) {
  final rows = <(Released, HomeRowData)>[];
  for (final entry in entries) {
    final upcoming = upcomingRelease(entry, today);
    if (upcoming == null) continue;
    final (:released, :season) = upcoming;
    rows.add((
      released,
      HomeRowData(
        entry,
        detail: season != null ? 'Season ${season.season}' : _creator(entry),
        right: comingSoonLabel(released, today: today),
        emphasized: released.day != null,
      ),
    ));
  }
  rows.sort((a, b) {
    final c = _precision(a.$1).compareTo(_precision(b.$1));
    if (c != 0) return c;
    final d = a.$1.availableFrom.compareTo(b.$1.availableFrom);
    return d != 0 ? d : compareTitles(a.$2.entry.title, b.$2.entry.title);
  });
  return HomeSection(HomeSectionKind.comingSoon, [
    for (final (_, row) in rows.take(HomeSection.limit)) row,
  ], total: rows.length);
}

HomeSection _inProgress(List<Entry> entries, Map<String, DateTime> changes) {
  final going = [
    for (final entry in entries)
      if (entry.status == EntryStatus.inProgress) entry,
  ];
  // Newest added first breaks ties and orders entries never changed here;
  // same-day pairs keep the later in the library first, as that sort does.
  final byAdded = sortEntries(going, LibrarySort.newestAdded);
  final position = {for (final (i, entry) in byAdded.indexed) entry.id: i};
  DateTime changed(Entry e) => changes[e.id] ?? dateOnly(e.added);
  byAdded.sort((a, b) {
    final c = changed(b).compareTo(changed(a));
    return c != 0 ? c : position[a.id]!.compareTo(position[b.id]!);
  });
  return HomeSection(HomeSectionKind.inProgress, [
    for (final entry in byAdded.take(HomeSection.limit))
      HomeRowData(entry, detail: inProgressDetail(entry)),
  ], total: byAdded.length);
}

HomeSection _recentlyAdded(List<Entry> entries, DateTime today) {
  final recent = sortEntries(
    entries.where((e) => daysBetween(e.added, today) <= HomeSection.recentDays),
    LibrarySort.newestAdded,
  );
  return HomeSection(HomeSectionKind.recentlyAdded, [
    for (final entry in recent.take(HomeSection.limit))
      HomeRowData(
        entry,
        detail: recentlyAddedDetail(entry, today: today),
        right: addedLabel(entry.added, today: today),
        emphasized: daysBetween(entry.added, today) <= 1,
      ),
  ], total: recent.length);
}

/// Calendar days from [from] to [to], counted in UTC so a daylight saving
/// change in between does not lose a day.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String? _creator(Entry entry) {
  final creator = entry.creator;
  return creator == null || creator.isEmpty ? null : creator;
}

/// The In progress detail: the season being watched ("Season 2"), else the
/// creator, else the year.
String? inProgressDetail(Entry entry) {
  if (entry.usesSeasons) {
    final seasons = entry.seasons ?? const <Season>[];
    final today = seasonClock();
    Season? current;
    for (final season in seasons) {
      if (season.status == EntryStatus.inProgress) {
        current = season;
        break;
      }
    }
    // Done and Want together read as In progress: the next one to watch.
    current ??= seasons
        .where((s) => s.isReleasedOn(today) && s.status != EntryStatus.done)
        .firstOrNull;
    if (current != null) return 'Season ${current.season}';
  }
  return _creator(entry) ?? entry.year?.toString();
}

/// The Recently added detail: the creator and the year ("Frank Herbert ·
/// 1969"), a show's years ("2025–2026"), or the year alone.
String? recentlyAddedDetail(Entry entry, {DateTime? today}) {
  final years = entry.usesSeasons
      ? showYears(entry, today: today)
      : entry.year?.toString();
  final detail = [?_creator(entry), ?years].join(' · ');
  return detail.isEmpty ? null : detail;
}

/// "Nov 10" (with the year when it is not this year: "Nov 10, 2027"), "Jan
/// 2027" for a month, "2027" for a year.
String comingSoonLabel(Released released, {required DateTime today}) {
  final month = released.month, day = released.day;
  if (month == null) return '${released.year}';
  final name = monthAbbreviations[month - 1];
  if (day == null) return '$name ${released.year}';
  final date = '$name $day';
  return released.year == today.year ? date : '$date, ${released.year}';
}

/// "Today", "Yesterday", "3 days ago" up to six days, then the date ("Oct
/// 20", with the year when it is not this year).
String addedLabel(DateTime added, {required DateTime today}) {
  final days = daysBetween(added, today);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  final date = formatMonthDay(added);
  return added.year == today.year ? date : '$date, ${added.year}';
}

/// One row of a home section (Library › Home): the title, a dot in the
/// type's color before "Type · detail", and the date or when on the right.
class HomeRow extends StatelessWidget {
  const HomeRow(this.row, {super.key, this.onTap});

  final HomeRowData row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(fontSize: 13.5);
    return RowInkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.entry.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.forType(row.entry.type),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          row.subtitle,
                          style: subtitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (row.right.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                row.right,
                style: subtitleStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: row.emphasized
                      ? theme.textTheme.bodyMedium!.color
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the home says when none of its sections has anything (Library ›
/// Home: nothing to show).
class HomeNothingToShow extends StatelessWidget {
  const HomeNothingToShow({super.key});

  static const text =
      'Nothing coming up, in progress or new.\nPick a type above to browse.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall!.copyWith(fontSize: 15, height: 1.45),
      ),
    );
  }
}
