import 'package:flutter/foundation.dart';

import '../../data/lookup/series_check.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/entry.dart';
import '../../data/models/follow_kind.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../data/models/released.dart';
import '../../data/models/season.dart';
import '../../data/upcoming/creator_lookup.dart';
import '../../widgets/labels.dart';
import '../entry/series.dart';
import '../settings/display_preferences.dart';
import 'home_sections.dart';
import 'library_sort.dart';

/// Where an upcoming row comes from.
enum UpcomingKind {
  /// An entry of the library with a release date still ahead, or one set
  /// Want with no date at all ("Date not set").
  entry,

  /// The coming season of a show or anime series in the library.
  season,

  /// A part of a followed series that is not in the library, as the daily
  /// series check recorded it.
  part,

  /// A new release of a followed creator that is not in the library, as the
  /// creator check recorded it (Settings › Upcoming releases).
  release,
}

/// One row of Library › Coming soon: your wants and Coming soon: everything
/// upcoming. [wanted] rows are what the owner asked for ([wantsRelease]);
/// the rest are listed in Everything upcoming with "Add", and [reason] says
/// why they are there (Coming soon: add an upcoming entry).
@immutable
class UpcomingItem {
  const UpcomingItem._({
    required this.kind,
    required this.id,
    required this.type,
    required this.title,
    required this.wanted,
    required this.reason,
    this.released,
    this.detail,
    this.creator,
    this.description = '',
    this.entry,
    this.season,
    this.part,
    this.release,
  });

  /// An entry with a release ahead, or set Want with no date.
  factory UpcomingItem.entry(Entry entry) => UpcomingItem._(
    kind: UpcomingKind.entry,
    id: entry.id,
    type: entry.type,
    title: entry.title,
    released: entry.released,
    detail: _creator(entry),
    creator: _creator(entry),
    description: entry.description,
    wanted: entry.status == EntryStatus.want,
    reason: '${entry.title} is in your library (${entry.status.label}).',
    entry: entry,
  );

  /// The coming [season] of [show] (a show or an anime series).
  factory UpcomingItem.season(Entry show, Season season, {DateTime? today}) =>
      UpcomingItem._(
        kind: UpcomingKind.season,
        id: seasonKey(show.id, season.season),
        type: show.type,
        title: show.title,
        released: season.released,
        detail: 'Season ${season.season}',
        creator: _creator(show),
        description: show.description,
        wanted: wantsRelease(show, season),
        reason: seasonReason(show, today: today),
        entry: show,
        season: season,
      );

  /// A part of a followed series not in the library; [owned] are the
  /// library's entries of that series.
  factory UpcomingItem.part(UpcomingPart part, {required List<Entry> owned}) =>
      UpcomingItem._(
        kind: UpcomingKind.part,
        id: 'part:${part.type.name}/${part.seriesName}/${part.partKey}',
        type: part.type,
        title: seriesPartTitle(part.title, part.seriesName),
        released: part.released,
        detail: seriesDisplayName(part.seriesName),
        wanted: false,
        reason: partReason(part, owned: owned),
        part: part,
      );

  /// A release of a followed creator not in the library.
  factory UpcomingItem.release(FoundRelease release) => UpcomingItem._(
    kind: UpcomingKind.release,
    id: release.key,
    type: release.match.type,
    title: release.match.title,
    released: release.match.released,
    detail: release.match.creator ?? release.creatorName,
    creator: release.match.creator ?? release.creatorName,
    description: release.match.description,
    wanted: false,
    reason: releaseReason(release),
    release: release,
  );

  final UpcomingKind kind;

  /// Tells the row apart, and is the key Not interested hides an entry, a
  /// season or a found release by (`AppSettings.notInterested`); a part is
  /// hidden through its series' Choose what to show instead.
  final String id;

  final MediaType type;
  final String title;

  /// Null for a Want entry without a date ("Date not set").
  final Released? released;

  /// After the type: the creator, "Season 3", or the series name.
  final String? detail;
  final String? creator;
  final String description;
  final bool wanted;

  /// "Why it's here", for a row that is not wanted.
  final String reason;

  final Entry? entry;
  final Season? season;
  final UpcomingPart? part;
  final FoundRelease? release;

  /// The lookup id Add to library starts the entry form from, for a part
  /// or a found release; null when the source gave none.
  String? get source => release?.match.source ?? part?.source;

  /// "Nov 10", "Jan 2027", "2027", or "Date not set".
  String rightLabel(DateTime today) => switch (released) {
    final released? => comingSoonLabel(released, today: today),
    null => 'Date not set',
  };

  /// An exact date stands in the text color on the row.
  bool get emphasized => released?.day != null;

  /// What the add sheet calls it: "Stranger Things, Season 5" for a
  /// season, a part's full title as the lookup lists it, else the title.
  String get sheetTitle => switch ((season, part)) {
    (final season?, _) => '$title, Season ${season.season}',
    (_, final part?) => part.title,
    _ => title,
  };

  /// The key a season is hidden by.
  static String seasonKey(String entryId, int season) => '$entryId#$season';
}

/// A month, a year or "Date not set" of the list, with its rows.
@immutable
class UpcomingGroup {
  const UpcomingGroup(this.name, this.items);

  final String name;
  final List<UpcomingItem> items;
}

/// Everything coming for [entries] (seasonal-only ones already left out),
/// nearest first: every entry with a release ahead, the coming season of
/// every show and anime series, every Want entry without a date, the parts
/// of followed series the series check recorded ([parts], sifted by
/// [upcomingPartsToShow]), and the [releases] of followed creators the
/// creator check recorded that are not in the library. Rows the owner
/// marked Not interested are left out ([AppSettings.notInterested]; a part
/// through its series in [prefs]). Your wants is [wantedUpcoming] of this.
List<UpcomingItem> upcomingItems(
  Iterable<Entry> entries, {
  required List<UpcomingPart> parts,
  List<FoundRelease> releases = const [],
  required DisplayPreferences prefs,
  AppSettings settings = AppSettings.defaults,
  required DateTime today,
}) {
  final list = entries.toList();
  final items = <UpcomingItem>[];
  for (final entry in list) {
    final upcoming = upcomingRelease(entry, today);
    if (upcoming != null) {
      items.add(switch (upcoming.season) {
        final season? => UpcomingItem.season(entry, season, today: today),
        null => UpcomingItem.entry(entry),
      });
    } else if (!entry.usesSeasons &&
        entry.released == null &&
        entry.status == EntryStatus.want) {
      items.add(UpcomingItem.entry(entry));
    }
  }
  for (final part in upcomingPartsToShow(parts, library: list, prefs: prefs)) {
    items.add(
      UpcomingItem.part(
        part,
        owned: entriesInSeries(list, part.type, part.seriesName),
      ),
    );
  }
  final owned = {for (final e in list) ?e.source};
  final seen = <String>{};
  for (final release in releases) {
    if (owned.contains(release.key) || !seen.add(release.key)) continue;
    if (!isRecentOrAhead(release.match.released, today)) continue;
    items.add(UpcomingItem.release(release));
  }
  items.removeWhere((item) => settings.notInterested.contains(item.id));
  items.sort(compareUpcoming);
  return items;
}

/// "A new album by Alice in Chains, whom you follow (2 albums in your
/// library)."
String releaseReason(FoundRelease release) {
  final what = switch (release.match.type) {
    MediaType.movies => 'movie',
    MediaType.shows => 'show',
    MediaType.books => 'book',
    MediaType.games => 'game',
    MediaType.music => 'album',
    MediaType.anime => 'anime',
  };
  final by = switch (release.kind) {
    FollowKind.actors => 'with',
    FollowKind.studios => 'from',
    _ => 'by',
  };
  return 'A new $what $by ${release.creatorName}, whom you follow.';
}

/// The rows of Your wants: those the owner asked for.
List<UpcomingItem> wantedUpcoming(List<UpcomingItem> items) => [
  for (final item in items)
    if (item.wanted) item,
];

/// By the first day the release counts as out (so within a month the exact
/// dates come before the month alone), undated rows last, then by title.
int compareUpcoming(UpcomingItem a, UpcomingItem b) {
  final ra = a.released, rb = b.released;
  if (ra == null || rb == null) {
    if (ra != null) return -1;
    if (rb != null) return 1;
  } else {
    final c = ra.availableFrom.compareTo(rb.availableFrom);
    if (c != 0) return c;
  }
  return compareTitles(a.title, b.title);
}

/// [items] (already sorted) under their month ("November", "January 2027"
/// when not this year), their year alone for year-only dates ("2027", after
/// that year's months), and "Date not set" last.
List<UpcomingGroup> upcomingGroups(
  List<UpcomingItem> items, {
  required DateTime today,
}) {
  final groups = <UpcomingGroup>[];
  for (final item in items) {
    final name = upcomingGroupName(item.released, today: today);
    if (groups.isNotEmpty && groups.last.name == name) {
      groups.last.items.add(item);
    } else {
      groups.add(UpcomingGroup(name, [item]));
    }
  }
  return groups;
}

String upcomingGroupName(Released? released, {required DateTime today}) {
  if (released == null) return 'Date not set';
  final month = released.month;
  if (month == null) return '${released.year}';
  final name = monthNames[month - 1];
  return released.year == today.year ? name : '$name ${released.year}';
}

/// "Stranger Things is in your library; seasons 1–4 are Done.": the
/// seasons that give the show its status. A show whose seasons have no
/// status yet just is in the library.
String seasonReason(Entry show, {DateTime? today}) {
  final seasons = show.seasons ?? const <Season>[];
  final status = Season.showStatus(seasons, today ?? seasonClock());
  final numbers = [
    for (final s in seasons)
      if (s.status == status) s.season,
  ];
  if (numbers.isEmpty) return '${show.title} is in your library.';
  final verb = numbers.length == 1 ? 'is' : 'are';
  return '${show.title} is in your library; '
      '${numberedPhrase('season', numbers)} $verb ${status.label}.';
}

/// "Part 3 of Dune; parts 1 and 2 are in your library." when the numbers
/// are known, else "Berserk is in your library (15 volumes)."
String partReason(UpcomingPart part, {required List<Entry> owned}) {
  final series = seriesDisplayName(part.seriesName);
  final numbers = [for (final e in owned) ?e.series?.number];
  if (part.number case final number? when numbers.length == owned.length) {
    final verb = numbers.length == 1 ? 'is' : 'are';
    return 'Part $number of $series; '
        '${numberedPhrase('part', numbers)} $verb in your library.';
  }
  final (one, many) = seriesNouns(part.type);
  final noun = owned.length == 1 ? one : many;
  return '$series is in your library (${owned.length} $noun).';
}

/// "part 3", "parts 1 and 2", "parts 1–3", "parts 1, 2 and 4".
String numberedPhrase(String noun, List<int> numbers) {
  if (numbers.length == 1) return '$noun ${numbers.single}';
  final sorted = [...numbers]..sort();
  final consecutive = sorted.last - sorted.first == sorted.length - 1;
  if (consecutive && sorted.length > 2) {
    return '${noun}s ${sorted.first}–${sorted.last}';
  }
  final head = sorted.sublist(0, sorted.length - 1).join(', ');
  return '${noun}s $head and ${sorted.last}';
}

String? _creator(Entry entry) {
  final creator = entry.creator;
  return creator == null || creator.isEmpty ? null : creator;
}
