import 'package:flutter/material.dart';

import '../../data/lookup/movie_dates.dart';
import '../../data/lookup/series_check.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../data/models/release_dates.dart';
import '../../data/models/released.dart';
import '../../data/models/season.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/row_ink_well.dart';
import '../entry/series.dart';
import '../plans/plan_dates.dart';
import '../settings/display_preferences.dart';
import 'library_sort.dart';

/// The three sections of the library home on All (Library › Home), each
/// shown only when it has something, up to [HomeSection.limit] rows each.
enum HomeSectionKind {
  /// Entries the owner wants whose release date is still ahead, nearest
  /// first ([wantsRelease]).
  comingSoon('Coming soon'),

  /// Entries In progress, the most recently changed first.
  inProgress('In progress'),

  /// Entries added in the last [HomeSection.recentDays] days, newest first.
  recentlyAdded('Recently added');

  const HomeSectionKind(this.title);

  final String title;
}

/// One row of a home section: the entry, the detail after its type
/// ("Stephen King", "Season 2", "2024"), and what stands on the right ("Nov
/// 10", "Today"), [emphasized] in the text color rather than the muted one
/// (every date is; only Coming soon's "Date not set" stays muted).
/// Library › Coming soon: everything puts an [action] under it
/// ("Want" in the accent when [actionEmphasized], else "Add" muted), and
/// rows there for a part not in the library have no entry ([HomeRowData.text]).
@immutable
class HomeRowData {
  HomeRowData(
    Entry this.entry, {
    this.detail,
    this.right = '',
    this.emphasized = false,
    this.action,
    this.actionEmphasized = false,
  }) : id = entry.id,
       title = entry.title,
       type = entry.type;

  const HomeRowData.text({
    required this.id,
    required this.title,
    required this.type,
    this.detail,
    this.right = '',
    this.emphasized = false,
    this.action,
    this.actionEmphasized = false,
  }) : entry = null;

  /// The entry the row stands for; null for a part not in the library.
  final Entry? entry;

  /// What tells the row apart in its section.
  final String id;
  final String title;
  final MediaType type;
  final String? detail;
  final String right;
  final bool emphasized;
  final String? action;
  final bool actionEmphasized;

  /// "Book · Stephen King", or just "Book".
  String get subtitle =>
      [type.singular, ?detail].where((s) => s.isNotEmpty).join(' · ');
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
/// from the day it was added. [movieDates] (by lookup id) and
/// [releaseDates] pick the date a movie is listed by (Settings › Movies ›
/// Release dates).
List<HomeSection> homeSections(
  Iterable<Entry> entries, {
  required DateTime today,
  Map<String, DateTime> changes = const {},
  Map<String, MovieDates> movieDates = const {},
  ReleaseDates releaseDates = ReleaseDates.both,
}) {
  final list = entries.toList();
  final sections = [
    _comingSoon(
      list,
      today,
      movieDates: movieDates,
      releaseDates: releaseDates,
    ),
    _inProgress(list, changes),
    _recentlyAdded(list, today),
  ];
  return [
    for (final section in sections)
      if (section.rows.isNotEmpty) section,
  ];
}

/// A release still ahead: an entry's own date, or for a show or an anime
/// series the earliest season not yet out ("Wednesday · Season 3"). For a
/// movie, the date Settings › Movies › Release dates shows ([shownRelease]
/// of its [dates] by kind), so under Digital a movie out in cinemas with
/// its digital date ahead is still coming.
({Released released, Season? season})? upcomingRelease(
  Entry entry,
  DateTime today, {
  MovieDates? dates,
  ReleaseDates releaseDates = ReleaseDates.both,
}) {
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
  final released = shownRelease(entry.released, dates, releaseDates);
  if (released == null || released.isReleasedOn(today)) return null;
  return (released: released, season: null);
}

/// Whether a release still ahead is one the owner asked for, so that the
/// home lists it in Coming soon (owner's decision, 2026-10-29: the home
/// shows only what is set Want): [entry] is Want, or [season], its coming
/// season from [upcomingRelease], was set Want in its season sheet. A show
/// Done or In progress whose announced season is not set stays out.
bool wantsRelease(Entry entry, Season? season) =>
    entry.status == EntryStatus.want || season?.status == EntryStatus.want;

/// The parts the daily series check recorded ([SeriesCheck]) that are worth
/// listing: of a series still followed (a part of it in [library] Done or
/// In progress), not in the library by now (matched to the library's
/// entries as the Series section matches them), not hidden by the owner in
/// Choose what to show ([prefs]), and not an extra of the automatic rules
/// the owner has not shown. The home does not list them (only entries set
/// Want, [wantsRelease]); Library › Coming soon: everything does
/// (`upcomingItems` in `upcoming.dart`).
List<UpcomingPart> upcomingPartsToShow(
  List<UpcomingPart> parts, {
  required Iterable<Entry> library,
  required DisplayPreferences prefs,
}) {
  final entries = library.toList();
  final shown = <UpcomingPart>[];
  final seen = <String>{};
  for (final part in parts) {
    final owned = entriesInSeries(entries, part.type, part.seriesName);
    if (!SeriesCheck.isFollowed(owned)) continue;
    final key = '${part.type.name}/${part.seriesName}/${part.partKey}';
    if (!seen.add(key)) continue;
    final choices = seriesPartChoices(
      prefs,
      seriesKey(part.type, part.seriesName),
    );
    if (choices.hidden.contains(part.partKey) ||
        (part.extra && !choices.shown.contains(part.partKey))) {
      continue;
    }
    final rows = seriesRows(
      current: owned.first,
      library: entries,
      parts: (
        name: part.seriesName,
        parts: [
          (
            number: part.number,
            title: part.title,
            year: part.released.year,
            released: part.released,
            source: part.source,
            creator: null,
            cover: part.cover,
            extra: part.extra,
          ),
        ],
      ),
    );
    final row = rows.where((r) => r.partKey == part.partKey).firstOrNull;
    if (row == null || row.owned) continue;
    shown.add(part);
  }
  return shown;
}

HomeSection _comingSoon(
  List<Entry> entries,
  DateTime today, {
  required Map<String, MovieDates> movieDates,
  required ReleaseDates releaseDates,
}) {
  final rows = <(Released, HomeRowData)>[];
  for (final entry in entries) {
    final upcoming = upcomingRelease(
      entry,
      today,
      dates: movieDates[entry.source],
      releaseDates: releaseDates,
    );
    if (upcoming == null) continue;
    final (:released, :season) = upcoming;
    if (!wantsRelease(entry, season)) continue;
    rows.add((
      released,
      HomeRowData(
        entry,
        detail: season != null ? 'Season ${season.season}' : _creator(entry),
        right: comingSoonLabel(released, today: today),
        emphasized: true,
      ),
    ));
  }
  // The order of Library › Coming soon: in library (`compareUpcoming`), so
  // the home is the first rows of that list: by the first day the release
  // counts as out (within a month the exact dates come before the month
  // alone), then by title.
  rows.sort((a, b) {
    final c = a.$1.availableFrom.compareTo(b.$1.availableFrom);
    return c != 0 ? c : compareTitles(a.$2.title, b.$2.title);
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
        emphasized: true,
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
/// type's color before "Type · detail", and the date or when on the right,
/// with the row's action under it when it has one (Library › Coming soon:
/// everything). No chevron.
class HomeRow extends StatelessWidget {
  const HomeRow(this.row, {super.key, this.onTap, this.minHeight = 56});

  final HomeRowData row;
  final VoidCallback? onTap;

  /// 56 on the home, 60 on the Coming soon screen, as the canvas draws them.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(fontSize: 13.5);
    return RowInkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
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
                    row.title,
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
                          color: colors.forType(row.type),
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
            if (row.right.isNotEmpty || row.action != null) ...[
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (row.right.isNotEmpty)
                    Text(
                      row.right,
                      style: subtitleStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: row.emphasized
                            ? theme.textTheme.bodyMedium!.color
                            : null,
                      ),
                    ),
                  if (row.action case final action?) ...[
                    if (row.right.isNotEmpty) const SizedBox(height: 3),
                    Text(
                      action,
                      style: subtitleStyle.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: row.actionEmphasized
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ],
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
