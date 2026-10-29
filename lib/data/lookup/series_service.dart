import '../images/artwork_resolver.dart';
import '../models/entry.dart';
import '../models/released.dart';
import '../models/season.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'lookup_source.dart';
import 'series_store.dart';

/// A series' parts, whether they came from the phone, and whether asking
/// the lookup for a newer list failed, so the stored one is all there is.
class SeriesList {
  const SeriesList(
    this.series, {
    required this.fromCache,
    this.updateFailed = false,
  });

  final SeriesParts series;
  final bool fromCache;
  final bool updateFailed;
}

/// The parts of the series an entry belongs to (Library › Movie in a series;
/// Book in a long series; All volumes in a series), fetched when its details
/// open and kept on the phone. A stored list shows at once and is fetched
/// again behind it once it is [refreshAfter] old, since a series grows, or
/// at once when the entry's series name is not the one it was asked for (a
/// renamed series can be another of the game's collections). The
/// entry is known to the lookup by its `source`, or by the id the artwork
/// resolver matched it to. Only the entry's series name and number live in
/// `library.json`.
class SeriesService {
  SeriesService({
    required this.lookups,
    required this.resolver,
    required this.store,
  });

  final LookupService lookups;
  final ArtworkResolver resolver;
  final SeriesStore store;

  /// How long a stored list is trusted before the lookup is asked again.
  static const refreshAfter = Duration(days: 7);

  /// How long a stored list with a part still to come is trusted by the
  /// daily check ([refresh]): once a day, since its dates move.
  static const refreshUpcomingAfter = Duration(days: 1);

  /// The stored parts first, when there are any, then the fetched ones when
  /// they were fetched. Ends with null when no lookup id could be found or
  /// the lookup knows no series for the entry. Fails with [LookupException]
  /// only when nothing is stored; with a stored list it ends with that list
  /// again, marked [SeriesList.updateFailed].
  Stream<SeriesList?> load(Entry entry) async* {
    final now = seasonClock();
    final source = entry.source ?? await resolver.matchedSource(entry);
    if (source == null) {
      yield null;
      return;
    }
    final name = entry.series?.name;
    final stored = await store.read(source);
    if (stored != null) {
      yield SeriesList(stored.series, fromCache: true);
      if (now.difference(stored.fetched) < refreshAfter &&
          stored.asked == name) {
        return;
      }
    }
    final lookup = lookups.sourceOf(source);
    if (lookup == null) {
      if (stored == null) yield null;
      return;
    }
    final SeriesParts? parts;
    try {
      if (!lookup.isConfigured) {
        throw const LookupException(LookupFailure.notConfigured);
      }
      parts = await lookup.seriesParts(source, name: name);
    } on LookupException {
      // The stored list stays on screen, saying it could not be updated.
      if (stored == null) rethrow;
      yield SeriesList(stored.series, fromCache: true, updateFailed: true);
      return;
    }
    if (parts == null || parts.parts.isEmpty) {
      if (stored == null) yield null;
      return;
    }
    await store.write(source, parts, fetched: now, asked: name);
    yield SeriesList(parts, fromCache: false);
  }

  /// The lookup id the series of [entry] is read by: its `source`, or the
  /// id its cover was matched to (looked up when needed). Throws
  /// [LookupException] when that lookup gave no answer.
  Future<String?> sourceOf(Entry entry) async =>
      entry.source ?? await resolver.matchedSource(entry);

  /// Whether [parts] has a part whose release is still ahead of [today].
  static bool hasUpcoming(SeriesParts parts, DateTime today) => parts.parts.any(
    (p) => switch (seriesPartRelease(p)) {
      final Released r => !r.isReleasedOn(today),
      null => false,
    },
  );

  /// The daily check's refresh (`SeriesCheck`): the parts of the series
  /// [entry] is in, fetched again when the stored list is [refreshAfter]
  /// old, was asked for another name, or has a part still to come and is
  /// [refreshUpcomingAfter] old; else the stored list. [parts] is null when
  /// nothing is known; [failure] says why a fetch that was due did not
  /// work, the stored list standing in meanwhile. With [askLookup] off
  /// (the check has already found the lookup offline) only the stored list
  /// is read.
  Future<({SeriesParts? parts, LookupException? failure})> refresh(
    Entry entry, {
    required DateTime now,
    bool askLookup = true,
  }) async {
    const nothing = (parts: null, failure: null);
    final String? source;
    try {
      source = askLookup
          ? await sourceOf(entry)
          : entry.source ?? resolver.cachedSource(entry);
    } on LookupException catch (e) {
      return (parts: null, failure: e);
    }
    if (source == null) return nothing;
    final name = entry.series?.name;
    final stored = await store.read(source);
    if (stored != null && stored.asked == name) {
      final age = now.difference(stored.fetched);
      final due =
          age >= refreshAfter ||
          (age >= refreshUpcomingAfter &&
              hasUpcoming(
                stored.series,
                DateTime(now.year, now.month, now.day),
              ));
      if (!due) return (parts: stored.series, failure: null);
    }
    final lookup = lookups.sourceOf(source);
    if (!askLookup || lookup == null || !lookup.isConfigured) {
      return (parts: stored?.series, failure: null);
    }
    final SeriesParts? parts;
    try {
      parts = await lookup.seriesParts(source, name: name);
    } on LookupException catch (e) {
      return (parts: stored?.series, failure: e);
    }
    if (parts == null || parts.parts.isEmpty) {
      return (parts: stored?.series, failure: null);
    }
    await store.write(source, parts, fetched: now, asked: name);
    return (parts: parts, failure: null);
  }

  /// Drops the series of entries that are gone.
  Future<void> prune(Iterable<Entry> entries) => store.prune({
    for (final entry in entries)
      ?(entry.source ?? resolver.cachedSource(entry)),
  });
}
