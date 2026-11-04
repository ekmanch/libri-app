import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'entry_status.dart';
import 'released.dart';
import 'season.dart';
import 'season_span.dart';

part 'season_split.freezed.dart';
part 'season_split.g.dart';

/// One way the sources split a show or anime series into seasons (Add /
/// edit entry › Split into: pick a split): the split's ids, whether it is
/// one season per story arc, which streaming service it follows, whether
/// it is one long run, and its seasons with their episode counts, names
/// and dates. Kept on the phone (`season_splits.json`); only the
/// chosen split's first id goes to `library.json`, as `seasons_from`.
@freezed
abstract class SeasonSplit with _$SeasonSplit {
  const SeasonSplit._();

  const factory SeasonSplit({
    /// Where the split comes from, the first being the id written as
    /// `seasons_from`: "anilist" (AniList's sequel chain, parts folded),
    /// "anilist:parts" (the chain's entries one by one), "tmdb:seasons"
    /// (the TMDB show's season list), `tmdb:group:<id>` (one of its
    /// episode groups). Several when sources split alike ([distinct]).
    required List<String> ids,

    /// One season per story arc (a TMDB story-arc group): the seasons are
    /// named after the arcs, and this is the split Libri picks for a long
    /// run ([automatic]).
    @Default(false) bool arcs,

    /// The streaming service whose seasons a TMDB group follows
    /// ("Netflix", "Crunchyroll"), named in the sheet beside the season
    /// count (owner's decision, 2026-11-04); null for any other split.
    @JsonKey(includeIfNull: false) String? service,

    /// A regular list that is one long run: one season of more than 100
    /// episodes, or airing with no count for years (Hunter x Hunter, One
    /// Piece). Its automatic split is the arcs ([automatic]).
    @Default(false) bool long,

    /// In season number order.
    required List<SeasonSpan> seasons,
  }) = _SeasonSplit;

  factory SeasonSplit.fromJson(Map<String, Object?> json) =>
      _$SeasonSplitFromJson(json);

  /// AniList's chain, and a TMDB show's own season list: the regular
  /// lists, as against the user-made episode groups.
  static const anilistId = 'anilist';
  static const anilistPartsId = 'anilist:parts';
  static const tmdbSeasonsId = 'tmdb:seasons';
  static const tmdbGroupPrefix = 'tmdb:group:';

  /// How many splits the sheet lists at most ([shortlist]).
  static const maxListed = 6;

  static bool isRegular(String id) => id == anilistId || id == tmdbSeasonsId;

  String get id => ids.first;

  bool has(String from) => ids.contains(from);

  int get count => seasons.length;

  /// The episode counts of the seasons whose count is known, in order:
  /// what tells one split from another. A season announced with no count
  /// yet is left out, so AniList's chain with a sequel coming and a TMDB
  /// group without it are the same split.
  List<int> get shape => [
    for (final s in seasons)
      if (s.episodes case final n? when n > 0) n,
  ];

  /// The episodes known so far.
  int get episodes => shape.fold(0, (sum, n) => sum + n);

  /// Whether [other] splits the show as this does.
  bool sameAs(SeasonSplit other) =>
      listEquals(shape, other.shape) &&
      (shape.isNotEmpty || count == other.count);

  /// Every season dated, each in a later year than the one before: the
  /// seasons follow the broadcast years.
  bool get byYear {
    if (count < 2) return false;
    int? last;
    for (final s in seasons) {
      final year = s.released?.year;
      if (year == null || (last != null && year <= last)) return false;
      last = year;
    }
    return true;
  }

  /// "One season", "3 seasons", "6 seasons, one per arc", "19 seasons ·
  /// Crunchyroll": the count always, so a service's can be checked
  /// against its app.
  String get label {
    final seasons = count == 1
        ? 'One season'
        : '$count seasons${arcs ? ', one per arc' : ''}';
    return service == null ? seasons : '$seasons · $service';
  }

  /// Whether the seasons have names worth showing: an arcs split's, or a
  /// service's when it names them ("East Blue", not "Season 3").
  bool get named => arcs || seasons.any((s) => s.name != null);

  /// What the seasons are: the arc names ("Hunter Exam, Heavens Arena, …")
  /// or a service's season names, "148 episodes", "By year: 62, 74 and 12
  /// episodes", "28 and 10 episodes, one more coming". Never a source's
  /// name.
  String get detail {
    if (named) {
      return [for (final s in seasons) s.name ?? 'Season ${s.season}']
          .join(', ');
    }
    final counts = shape;
    final coming = count - counts.length;
    if (counts.isEmpty) {
      return coming == 1
          ? 'Episode count not known yet'
          : 'Episode counts not known yet';
    }
    var text = '${_list([for (final n in counts) '$n'])} episodes';
    if (coming == 1) text += ', one more coming';
    if (coming > 1) text += ', $coming more coming';
    return byYear ? 'By year: $text' : text;
  }

  /// "62", "62 and 74", "62, 74 and 12".
  static String _list(List<String> items) => switch (items.length) {
    0 => '',
    1 => items.single,
    _ => '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
  };

  /// The seasons as an entry gets them: numbered and dated, no status.
  List<Season> toSeasons() => [
    for (final s in seasons) Season(season: s.season, released: s.released),
  ];

  /// The seasons' names by number, for an arcs split or a service's named
  /// seasons; empty otherwise, so the rows read "Season 3".
  Map<int, String> get names => {
    if (named)
      for (final s in seasons) s.season: ?s.name,
  };

  /// [splits], those that split alike folded into one (Add / edit entry ›
  /// Split into: pick a split lists each distinct split once), in the
  /// order given: the first of them stands and takes the others' ids, the
  /// arc names of an arcs split among them, a service among them, and the
  /// long mark.
  static List<SeasonSplit> distinct(Iterable<SeasonSplit> splits) {
    final out = <SeasonSplit>[];
    for (final split in splits) {
      final i = out.indexWhere((o) => o.sameAs(split));
      if (i < 0) {
        out.add(split);
        continue;
      }
      final kept = out[i];
      out[i] = kept.copyWith(
        ids: [...kept.ids, ...split.ids.where((id) => !kept.ids.contains(id))],
        arcs: kept.arcs || split.arcs,
        service: kept.service ?? split.service,
        long: kept.long || split.long,
        seasons: kept.named || !split.named
            ? kept.seasons
            : [
                for (final (j, s) in kept.seasons.indexed)
                  s.copyWith(
                    name: split.seasons.elementAtOrNull(j)?.name ?? s.name,
                  ),
              ],
      );
    }
    return out;
  }

  /// The split Libri picks on its own (the one marked Automatic; owner's
  /// decision, 2026-11-04): the regular list, AniList's chain with its
  /// parts folded for an anime, else the TMDB show's own seasons, which
  /// is how streaming services show seasonal anime and shows; except for
  /// a long run ([long]: Hunter x Hunter, One Piece), which streaming
  /// services show by story arc, so it takes one season per arc when the
  /// sources have one, the coarsest of several (the Story Arcs group of
  /// six for Hunter x Hunter, not the Japanese one of nine). The first of
  /// [splits] when there is no regular list.
  static SeasonSplit? automatic(List<SeasonSplit> splits) {
    final regular = regularOf(splits);
    if (regular?.long ?? false) {
      SeasonSplit? arcs;
      for (final s in splits) {
        if (s.arcs && (arcs == null || s.count < arcs.count)) arcs = s;
      }
      if (arcs != null) return arcs;
    }
    return regular ?? splits.firstOrNull;
  }

  /// The regular list among [splits]: AniList's chain, else the TMDB
  /// show's own seasons; null without either.
  static SeasonSplit? regularOf(List<SeasonSplit> splits) {
    for (final id in const [anilistId, tmdbSeasonsId]) {
      for (final s in splits) {
        if (s.has(id)) return s;
      }
    }
    return null;
  }

  /// The splits the sheet lists: the automatic one and the first others
  /// in the sources' order, [maxListed] at most (TMDB's users make many
  /// groups for a long show: One Piece has twenty).
  static List<SeasonSplit> shortlist(List<SeasonSplit> splits) {
    if (splits.length <= maxListed) return splits;
    final auto = automatic(splits);
    final listed = [?auto];
    for (final s in splits) {
      if (listed.length >= maxListed) break;
      if (s != auto) listed.add(s);
    }
    return listed;
  }

  /// Whether an entry's [seasons] can be this split's: every season out
  /// that is not set by hand is numbered in it and dated as it dates it,
  /// as far as both dates go (a season dated "1990" by a migration agrees
  /// with "1990-04-08"). A season not out yet is not held against it: the
  /// source may have dropped or redated it, which the check handles. A
  /// season of the split beyond them is one the source added since.
  bool fits(List<Season> seasons, DateTime today) {
    final byNumber = {for (final s in this.seasons) s.season: s};
    for (final s in seasons) {
      if (s.isManual || !s.isReleasedOn(today)) continue;
      final span = byNumber[s.season];
      if (span == null) return false;
      if (!_agree(s.released, span.released)) return false;
    }
    return true;
  }

  /// Whether two dates agree as far as both go; an unknown date agrees
  /// with any.
  static bool _agree(Released? a, Released? b) {
    if (a == null || b == null) return true;
    if (a.year != b.year) return false;
    if (a.month != null && b.month != null && a.month != b.month) return false;
    return a.day == null || b.day == null || a.day == b.day;
  }

  /// Whether this split, kept on the phone, is stale for an entry in it
  /// whose [seasons] these are: it lists a season beyond their highest
  /// that is already out on [today]. The daily check adds a season the
  /// day it is out, so one out and not added means the stored split and
  /// the entry disagree (a list stored by a build that did not fold
  /// Bleach's parts; owner's report, 2026-11-04), and the splits are read
  /// again. An announced season beyond them is not held against it.
  bool staleFor(List<Season> seasons, DateTime today) {
    final highest = seasons.isEmpty ? 0 : seasons.last.season;
    return this.seasons.any(
      (s) => s.season > highest && (s.released?.isReleasedOn(today) ?? false),
    );
  }

  /// How many seasons this split has beyond [seasons]' highest.
  int beyond(List<Season> seasons) {
    final highest = seasons.isEmpty ? 0 : seasons.last.season;
    return this.seasons.where((s) => s.season > highest).length;
  }

  /// Of [splits], the one an entry's [seasons] are in, told by their shape
  /// (an entry from before `seasons_from`): the one that [fits] with the
  /// fewest seasons beyond them, the first of equals; null when none fits.
  static SeasonSplit? fitting(
    List<SeasonSplit> splits,
    List<Season> seasons,
    DateTime today,
  ) {
    SeasonSplit? best;
    for (final s in splits) {
      if (!s.fits(seasons, today)) continue;
      if (best == null || s.beyond(seasons) < best.beyond(seasons)) best = s;
    }
    return best;
  }

  /// An entry's [seasons] moved into this split, nothing marked lost: each
  /// season takes the status of the seasons of [current] (the split they
  /// are in now) its episodes overlap, counted from episode 1 over the
  /// whole show (one status as it is; several as [Season.showStatus]
  /// combines them), and keeps a "new" mark one of them had; with no
  /// [current] to count by, the status of the season with its number. A
  /// season of this split with nothing to take has no status and is marked
  /// new only with [markNew] (the daily check's re-split; a split picked in
  /// the form is the owner's doing). Manual marks are dropped: the seasons
  /// are the split's now.
  List<Season> seasonsFrom(
    List<Season> seasons, {
    SeasonSplit? current,
    required DateTime today,
    bool markNew = false,
  }) {
    final byNumber = {for (final s in seasons) s.season: s};
    final oldRanges = current == null
        ? null
        : SeasonSpan.ranges(current.seasons);
    final newRanges = SeasonSpan.ranges(this.seasons);
    return [
      for (final span in this.seasons)
        _moved(
          span,
          oldRanges == null
              ? [?byNumber[span.season]]
              : [
                  if (newRanges[span.season] case final range?)
                    for (final MapEntry(:key, :value) in oldRanges.entries)
                      if (byNumber[key] case final s?
                          when SeasonSpan.overlaps(range, value))
                        s,
                ],
          today,
          markNew,
        ),
    ];
  }

  static Season _moved(
    SeasonSpan span,
    List<Season> overlapped,
    DateTime today,
    bool markNew,
  ) {
    final withStatus = [
      for (final s in overlapped)
        if (s.status != null) Season(season: s.season, status: s.status),
    ];
    final EntryStatus? status = withStatus.isEmpty
        ? null
        : Season.showStatus(withStatus, today);
    final fresh =
        (overlapped.isEmpty && markNew) ||
        overlapped.any((s) => s.fresh == true);
    return Season(
      season: span.season,
      released: span.released,
      status: status,
      fresh: fresh && status == null ? true : null,
    );
  }
}
