import '../images/artwork_resolver.dart';
import '../models/entry.dart';
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

  /// Drops the series of entries that are gone.
  Future<void> prune(Iterable<Entry> entries) => store.prune({
    for (final entry in entries)
      ?(entry.source ?? resolver.cachedSource(entry)),
  });
}
