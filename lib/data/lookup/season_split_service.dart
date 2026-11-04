import '../images/artwork_resolver.dart';
import '../models/entry.dart';
import '../models/season.dart';
import '../models/season_split.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'season_split_store.dart';

/// The ways a show's or anime series' seasons can be split (Add / edit
/// entry › Split into: pick a split; section 10c), read from the lookup
/// when the form or the details open and kept on the phone, so the field
/// and the season names show at once the next time. Which split an entry
/// is in is told by its `seasons_from`, or by its seasons' shape for an
/// entry from before splits ([current]).
class SeasonSplitService {
  SeasonSplitService({
    required this.lookups,
    required this.store,
    required this.resolver,
  });

  final LookupService lookups;
  final SeasonSplitStore store;

  /// Matches an entry without a lookup id (one from before lookups) to the
  /// provider's show on the device, as for its cover and episodes.
  final ArtworkResolver resolver;

  /// How long stored splits serve before the lookup is asked again: a new
  /// episode group or a new season shows up within a week.
  static const keep = Duration(days: 7);

  /// The id [entry]'s show is known by: its `source`, else the match made
  /// on the device; null when there is none, or none can be made now.
  Future<String?> sourceOf(Entry entry) async {
    if (entry.source case final source?) return source;
    try {
      return await resolver.matchedSource(entry);
    } on LookupException {
      return null;
    }
  }

  /// The store's key: the show's id and its TMDB show, since the TMDB
  /// show's groups are among the splits.
  static String keyFor(String source, String? tmdb) => '$source|${tmdb ?? ''}';

  /// [keyFor] with [entry]'s id ([sourceOf]); null when it has none.
  Future<String?> keyOf(Entry entry) async {
    final source = await sourceOf(entry);
    return source == null ? null : keyFor(source, entry.tmdb);
  }

  /// The splits for [entry], distinct ([SeasonSplit.distinct]), at most
  /// [SeasonSplit.maxListed] ([SeasonSplit.shortlist]) and in the
  /// sources' order: the stored ones while they are younger than [keep]
  /// and not stale for the entry ([SeasonSplit.staleFor]: the split its
  /// `seasons_from` names lists a season out that the entry lacks), else
  /// fetched and stored, as with [refresh] (a new entry's form, whose
  /// pick just walked the chain); the stored ones, however old, when the
  /// lookup cannot answer. Null for an entry with no lookup id, or nothing
  /// stored and no answer. Ahead of the daily checks' requests, since a
  /// screen waits for it.
  Future<List<SeasonSplit>?> load(Entry entry, {bool refresh = false}) async {
    final source = await sourceOf(entry);
    if (source == null) return null;
    final key = keyFor(source, entry.tmdb);
    final now = DateTime.now();
    final stored = await store.read(key);
    if (stored != null &&
        !refresh &&
        now.difference(stored.fetched) < keep &&
        !isStale(entry, stored.splits, now)) {
      return stored.splits;
    }
    final lookup = lookups.sourceOf(source);
    if (lookup == null || !lookup.isConfigured) return stored?.splits;
    final List<SeasonSplit>? found;
    try {
      found = await urgentLookups(
        () => lookup.seasonSplits(source, tmdb: entry.tmdb),
      );
    } on LookupException {
      return stored?.splits;
    }
    if (found == null) return stored?.splits;
    final splits = SeasonSplit.shortlist(SeasonSplit.distinct(found));
    await store.write(key, splits, now);
    return splits;
  }

  /// The stored splits for [entry], however old, without asking the
  /// lookup; null when none are stored.
  Future<List<SeasonSplit>?> stored(Entry entry) async {
    final source = entry.source ?? resolver.cachedSource(entry);
    if (source == null) return null;
    return (await store.read(keyFor(source, entry.tmdb)))?.splits;
  }

  /// Whether the stored [splits] are stale for [entry]: the split its
  /// `seasons_from` names lists a season out on [today] beyond the
  /// entry's seasons ([SeasonSplit.staleFor]). Seasons set by hand, or an
  /// entry without a split, are never stale.
  static bool isStale(Entry entry, List<SeasonSplit> splits, DateTime today) {
    if (entry.seasonsByHand) return false;
    final from = entry.seasonsFrom;
    if (from == null) return false;
    for (final split in splits) {
      if (split.has(from)) {
        return split.staleFor(entry.seasons ?? const [], today);
      }
    }
    return false;
  }

  /// The split [entry]'s seasons are in: the one its `seasons_from` names,
  /// else, for an entry from before splits or whose split is gone, the one
  /// its seasons' shape fits ([SeasonSplit.fitting]); null for seasons set
  /// by hand, or when none fits.
  static SeasonSplit? current(
    Entry entry,
    List<SeasonSplit> splits,
    DateTime today,
  ) {
    if (entry.seasonsByHand) return null;
    if (entry.seasonsFrom case final from?) {
      for (final split in splits) {
        if (split.has(from)) return split;
      }
    }
    return SeasonSplit.fitting(splits, entry.seasons ?? const [], today);
  }

  /// The seasons' names for [entry]'s rows, by number: the arc names of
  /// the arcs split it is in; empty when it is in another, so the rows
  /// read "Season 3".
  static Map<int, String> names(
    Entry entry,
    List<SeasonSplit>? splits,
    DateTime today,
  ) => splits == null
      ? const {}
      : current(entry, splits, today)?.names ?? const {};

  /// "Hunter Exam" for a season in an arcs split, else "Season 3".
  static String seasonName(Map<int, String> names, int season) =>
      names[season] ?? 'Season $season';

  /// The split [entry]'s seasons are in, by `seasons_from` or by the
  /// stored splits' shapes, for reading the episodes (the id the lookup
  /// takes as `from`); null when nothing says.
  Future<String?> currentId(Entry entry) async {
    if (entry.seasonsFrom case final from?) return from;
    if (entry.seasonsByHand) return null;
    final splits = await stored(entry);
    if (splits == null) return null;
    return current(entry, splits, seasonClock())?.id;
  }
}
