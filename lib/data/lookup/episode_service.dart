import '../images/artwork_resolver.dart';
import '../models/entry.dart';
import '../models/season.dart';
import 'episode_info.dart';
import 'episode_store.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';

/// A season's episodes, and whether they came from the phone.
class SeasonEpisodes {
  const SeasonEpisodes(this.episodes, {required this.fromCache});

  final List<EpisodeInfo> episodes;
  final bool fromCache;
}

/// The episodes of a show's season (A39, A40), fetched when the season
/// screen opens and kept on the phone. Stored episodes show at once; they
/// are fetched again behind them unless [isSettled]. The show is known by
/// its `source`, or by the id the artwork resolver matched it to on the
/// phone. Opening a season writes nothing to the library, and the daily
/// season check never comes here.
class EpisodeService {
  EpisodeService({
    required this.lookups,
    required this.resolver,
    required this.store,
  });

  final LookupService lookups;
  final ArtworkResolver resolver;
  final EpisodeStore store;

  /// How long after a season's last episode its stored list is trusted
  /// for good: late title and runtime fixes on TMDB land by then.
  static const settleAfter = Duration(days: 30);

  /// Whether a list fetched at [fetched] is kept without asking again: it
  /// was fetched today, or every episode has a title and an air date and
  /// it was fetched [settleAfter] past the last one. An airing season is
  /// fetched again on the first open of each day.
  static bool isSettled(
    DateTime fetched,
    List<EpisodeInfo> episodes,
    DateTime now,
  ) {
    final local = fetched.toLocal();
    final day = DateTime(now.year, now.month, now.day);
    if (!local.isBefore(day)) return true;
    if (episodes.isEmpty) return false;
    DateTime? last;
    for (final e in episodes) {
      final aired = e.aired;
      if (e.title == null || aired == null) return false;
      final from = aired.availableFrom;
      if (last == null || from.isAfter(last)) last = from;
    }
    return !local.isBefore(last!.add(settleAfter));
  }

  /// The stored episodes first, when there are any, then the fetched ones
  /// when they were fetched. Ends with null when no show id could be found
  /// or the lookup has no episodes for the season. Fails with
  /// [LookupException] only when nothing is stored, so the screen can tell
  /// being offline from a season the lookup does not know.
  Stream<SeasonEpisodes?> load(Entry show, int season) async* {
    final now = seasonClock();
    final source = show.source ?? await resolver.matchedSource(show);
    if (source == null) {
      yield null;
      return;
    }
    final stored = await store.read(source, season);
    if (stored != null) {
      yield SeasonEpisodes(stored.episodes, fromCache: true);
      if (isSettled(stored.fetched, stored.episodes, now)) return;
    }
    final lookup = lookups.sourceOf(source);
    if (lookup == null) {
      if (stored == null) yield null;
      return;
    }
    final List<EpisodeInfo>? episodes;
    try {
      if (!lookup.isConfigured) {
        throw const LookupException(LookupFailure.notConfigured);
      }
      episodes = await lookup.seasonEpisodes(source, season);
    } on LookupException {
      // The stored list stays on screen.
      if (stored == null) rethrow;
      return;
    }
    if (episodes == null || episodes.isEmpty) {
      if (stored == null) yield null;
      return;
    }
    await store.write(source, season, episodes, fetched: now);
    yield SeasonEpisodes(episodes, fromCache: false);
  }

  /// Drops the episodes of shows that are gone.
  Future<void> prune(Iterable<Entry> shows) => store.prune({
    for (final show in shows) ?(show.source ?? resolver.cachedSource(show)),
  });
}
