import 'package:flutter/foundation.dart';

import '../../data/lookup/movie_dates.dart';
import '../../data/lookup/book_match.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/series_check.dart';
import '../../data/lookup/text_clean.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/release_dates.dart';
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

/// One row of Library › Coming soon: in library and Coming soon: everything.
/// [wanted] rows are what the owner asked for ([wantsRelease]);
/// the rest are listed in Everything with "Add", and [reason] says
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
    this.dates,
  });

  /// An entry with a release ahead, or set Want with no date; a movie
  /// listed by the date Settings › Movies › Release dates picks from its
  /// [dates] by kind ([shownRelease]).
  factory UpcomingItem.entry(
    Entry entry, {
    MovieDates? dates,
    ReleaseDates releaseDates = ReleaseDates.both,
  }) => UpcomingItem._(
    kind: UpcomingKind.entry,
    id: entry.id,
    type: entry.type,
    title: entry.title,
    released: shownRelease(entry.released, dates, releaseDates),
    dates: dates,
    detail: _creator(entry),
    creator: _creator(entry),
    description: entry.description,
    wanted: entry.status == EntryStatus.want,
    reason:
        '${entry.title} is in your library (${entry.status.labelFor(entry.type)}).',
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
  /// library's entries of that series. A [release] of a followed creator
  /// that is the same title ([sameUpcoming]) is folded in: one row, the
  /// series as its detail, with the release's creator, description, cover
  /// and movie [dates], and both reasons.
  factory UpcomingItem.part(
    UpcomingPart part, {
    required List<Entry> owned,
    FoundRelease? release,
    MovieDates? dates,
    ReleaseDates releaseDates = ReleaseDates.both,
  }) {
    final match = release?.match;
    return UpcomingItem._(
      kind: UpcomingKind.part,
      id: 'part:${part.type.name}/${part.seriesName}/${part.partKey}',
      type: part.type,
      title: seriesPartTitle(part.title, part.seriesName),
      released: shownRelease(part.released, dates, releaseDates),
      dates: dates,
      detail: seriesDisplayName(part.seriesName),
      creator: release == null ? null : match!.creator ?? release.creatorName,
      description: match?.description ?? '',
      wanted: false,
      reason: [
        partReason(part, owned: owned),
        if (release != null) releaseReason(release),
      ].join(' '),
      part: part,
      release: release,
    );
  }

  /// A release of a followed creator not in the library; a movie listed by
  /// the date Settings › Movies › Release dates picks from its [dates].
  factory UpcomingItem.release(
    FoundRelease release, {
    MovieDates? dates,
    ReleaseDates releaseDates = ReleaseDates.both,
  }) => UpcomingItem._(
    kind: UpcomingKind.release,
    id: release.key,
    type: release.match.type,
    title: release.match.title,
    released: shownRelease(release.match.released, dates, releaseDates),
    dates: dates,
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

  /// A movie's dates by kind as the checks recorded them, for the add
  /// sheet's "In cinemas Dec 18 · Digital Feb 2027" line under Both.
  final MovieDates? dates;

  /// The lookup id Add to library starts the entry form from, for a part
  /// or a found release; null when the source gave none.
  String? get source => release?.match.source ?? part?.source;

  /// The cover of a part or a found release not in the library, as the
  /// daily check recorded it from the lookup's list, at the size the cache
  /// keeps; null while the title has no art yet (the add sheet then shows
  /// the placeholder). An entry or a season has the entry's own cover.
  String? get coverUrl => release?.match.cacheCoverUrl ?? part?.cover;

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
/// creator check recorded that are not in the library, each only while its
/// date is still ahead, as for an entry. Rows the owner
/// marked Not interested are left out ([AppSettings.notInterested]; a part
/// through its series in [prefs]). Movies are listed by the date
/// [settings]' Release dates picks from their [movieDates] (by lookup id).
/// In library is [wantedUpcoming] of this.
List<UpcomingItem> upcomingItems(
  Iterable<Entry> entries, {
  required List<UpcomingPart> parts,
  List<FoundRelease> releases = const [],
  required DisplayPreferences prefs,
  AppSettings settings = AppSettings.defaults,
  Map<String, MovieDates> movieDates = const {},
  required DateTime today,
}) {
  final list = entries.toList();
  final items = <UpcomingItem>[];
  final releaseDates = settings.releaseDates;
  for (final entry in list) {
    final dates = movieDates[entry.source];
    final upcoming = upcomingRelease(
      entry,
      today,
      dates: dates,
      releaseDates: releaseDates,
    );
    if (upcoming != null) {
      items.add(switch (upcoming.season) {
        final season? => UpcomingItem.season(entry, season, today: today),
        null => UpcomingItem.entry(
          entry,
          dates: dates,
          releaseDates: releaseDates,
        ),
      });
    } else if (!entry.usesSeasons &&
        entry.released == null &&
        entry.status == EntryStatus.want) {
      items.add(UpcomingItem.entry(entry));
    }
  }
  // A release that is a recorded part of a followed series is that part's
  // row (or nothing, when the owner hid the part); one that is an entry of
  // the library, or another release already listed, is left out.
  final shown = upcomingPartsToShow(parts, library: list, prefs: prefs);
  final followed = [
    for (final part in parts)
      if (SeriesCheck.isFollowed(
        entriesInSeries(list, part.type, part.seriesName),
      ))
        part,
  ];
  final folded = <UpcomingPart, FoundRelease>{};
  final owned = {for (final e in list) ?e.source};
  final seen = <String>{};
  final listed = <FoundRelease>[];
  for (final release in releases) {
    if (owned.contains(release.key) || !seen.add(release.key)) continue;
    final match = release.match;
    if (list.any((e) => sameUpcoming(match, entryUpcoming(e)))) continue;
    final part = followed
        .where(
          (p) =>
              p.source == release.key || sameUpcoming(match, partUpcoming(p)),
        )
        .firstOrNull;
    if (part != null) {
      final row = shown.where((p) => _samePart(p, part)).firstOrNull;
      if (row != null) folded.putIfAbsent(row, () => release);
      continue;
    }
    if (listed.any((r) => sameUpcoming(match, releaseUpcoming(r)))) continue;
    listed.add(release);
  }
  for (final part in shown) {
    final release = folded[part];
    final item = UpcomingItem.part(
      part,
      owned: entriesInSeries(list, part.type, part.seriesName),
      release: release,
      dates: movieDates[release?.key ?? part.source],
      releaseDates: releaseDates,
    );
    if (_isAhead(item.released, today)) items.add(item);
  }
  for (final release in listed) {
    final item = UpcomingItem.release(
      release,
      dates: movieDates[release.key],
      releaseDates: releaseDates,
    );
    if (_isAhead(item.released, today)) items.add(item);
  }
  items.removeWhere((item) => settings.notInterested.contains(item.id));
  items.sort(compareUpcoming);
  return items;
}

/// Whether a part or a found release is still ahead on [today] by the
/// release rule, as an entry must be ([upcomingRelease]). The checks keep
/// what came out in the last thirty days ([isRecentOrAhead]), so that it is
/// still matched to the library and to other paths, but Coming soon lists
/// only what is still to come (owner's decision, 2026-10-31).
bool _isAhead(Released? released, DateTime today) =>
    released != null && !released.isReleasedOn(today);

bool _samePart(UpcomingPart a, UpcomingPart b) =>
    a.type == b.type && a.seriesName == b.seriesName && a.partKey == b.partKey;

/// What [sameUpcoming] compares of a title found by a check.
typedef UpcomingTitle = ({
  MediaType type,
  String title,
  Released? released,
  String? creator,
});

UpcomingTitle entryUpcoming(Entry e) =>
    (type: e.type, title: e.title, released: e.released, creator: e.creator);

UpcomingTitle releaseUpcoming(FoundRelease r) => (
  type: r.match.type,
  title: r.match.title,
  released: r.match.released,
  creator: r.match.creator,
);

UpcomingTitle partUpcoming(UpcomingPart p) =>
    (type: p.type, title: p.title, released: p.released, creator: null);

/// Whether [match], found for a followed creator, is the same title as
/// [other], an entry, a recorded part or another release that came by
/// another path (Incredibles 3 as part 3 of the series and as Pixar's new
/// movie; Berserk volume 43 in the library and as Kentaro Miura's new
/// book): the same type and title, "Vol." aside ([volumeTitleKey]), dated
/// within a year of each other when both are dated, and for a book an
/// author in common when both name one.
bool sameUpcoming(LookupMatch match, UpcomingTitle other) {
  if (match.type != other.type) return false;
  if (volumeTitleKey(match.title) != volumeTitleKey(other.title)) {
    return false;
  }
  final a = match.released, b = other.released;
  if (a != null && b != null && (a.year - b.year).abs() > 1) return false;
  final x = match.creator, y = other.creator;
  if (match.type == MediaType.books &&
      x != null &&
      x.isNotEmpty &&
      y != null &&
      y.isNotEmpty &&
      !shareAuthor(x, y)) {
    return false;
  }
  return true;
}

/// [titleKey] without the word "Vol." or "Volume": "Berserk Vol. 43",
/// "Berserk, Volume 43" and "Berserk 43" are one key.
String volumeTitleKey(String title) => titleKey(
  title.replaceAll(RegExp(r'\b(vol(ume)?|v)\b\.?', caseSensitive: false), ' '),
);

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

/// The rows of In library: those the owner asked for.
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

/// "Stranger Things is in your library; seasons 1–4 are Done.", "Frieren
/// is in your library; you're watching season 2.": the seasons that give
/// the show its status. A show whose seasons have no
/// status yet just is in the library.
String seasonReason(Entry show, {DateTime? today}) {
  final seasons = show.seasons ?? const <Season>[];
  final status = Season.showStatus(seasons, today ?? seasonClock());
  final numbers = [
    for (final s in seasons)
      if (s.status == status) s.season,
  ];
  if (numbers.isEmpty) return '${show.title} is in your library.';
  final seasonsWord = numberedPhrase('season', numbers);
  if (status == EntryStatus.inProgress) {
    return "${show.title} is in your library; you're watching $seasonsWord.";
  }
  final verb = numbers.length == 1 ? 'is' : 'are';
  return '${show.title} is in your library; $seasonsWord $verb ${status.label}.';
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
