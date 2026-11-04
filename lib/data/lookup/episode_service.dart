import '../images/artwork_resolver.dart';
import '../models/entry.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import 'episode_info.dart';
import 'episode_store.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'lookup_source.dart';
import 'season_split_service.dart';

/// A season's episodes, whether they came from the phone, and the name of
/// the providers they came from, for the credit under them ("TMDB", or
/// "TMDB and AniList" for an anime series).
class SeasonEpisodes {
  const SeasonEpisodes(
    this.episodes, {
    required this.fromCache,
    this.provider = 'TMDB',
  });

  final List<EpisodeInfo> episodes;
  final bool fromCache;
  final String provider;
}

/// The episodes of a show's season (Show & seasons › Season episodes (all out)
/// and Season episodes (airing weekly)), fetched when the season screen opens
/// and kept on the phone. Stored episodes show at once; they are fetched again
/// behind them unless [isSettled]. The show is known by its `source`, or by the
/// id the artwork resolver matched it to on the phone, under the id the
/// provider keeps them by ([LookupSource.seasonSource]). Opening a season writes nothing to the
/// library, and the daily season check never comes here.
class EpisodeService {
  EpisodeService({
    required this.lookups,
    required this.resolver,
    required this.store,
    this.splits,
  });

  final LookupService lookups;
  final ArtworkResolver resolver;
  final EpisodeStore store;

  /// Says which split an entry's seasons are in, so the episodes read are
  /// that split's (section 10c); without it the provider's own.
  final SeasonSplitService? splits;

  /// The seasons being preloaded, so one is not fetched twice at once.
  final _preloading = <(String, int)>{};

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
    final own = show.source ?? await resolver.matchedSource(show);
    if (own == null) {
      yield null;
      return;
    }
    final source = await _seasonSource(own);
    final lookup = lookups.sourceOf(source);
    final from = await _splitOf(show, lookup);
    final key = EpisodeStore.keyFor(source, from);
    final stored = await store.read(key, season);
    if (stored != null) {
      yield SeasonEpisodes(
        stored.episodes,
        fromCache: true,
        provider: stored.provider,
      );
      if (isSettled(stored.fetched, stored.episodes, now)) return;
    }
    if (lookup == null) {
      if (stored == null) yield null;
      return;
    }
    final List<EpisodeInfo>? episodes;
    try {
      if (!lookup.isConfigured) {
        throw const LookupException(LookupFailure.notConfigured);
      }
      episodes = await urgentLookups(
        () => lookup.seasonEpisodes(
          source,
          season,
          anime: show.type == MediaType.anime,
          tmdb: show.tmdb,
          from: from,
        ),
      );
    } on LookupException {
      // The stored list stays on screen.
      if (stored == null) rethrow;
      return;
    }
    if (episodes == null || episodes.isEmpty) {
      if (stored == null) yield null;
      return;
    }
    final provider = lookup.episodesProvider(source);
    await store.write(key, season, episodes, fetched: now, provider: provider);
    yield SeasonEpisodes(episodes, fromCache: false, provider: provider);
  }

  /// The split [show]'s seasons are in, as the lookup takes it: null for
  /// the provider's own (the episodes then stay under the show's id alone,
  /// as before splits).
  Future<String?> _splitOf(Entry show, LookupSource? lookup) async {
    final from = await splits?.currentId(show);
    if (from == null || (lookup?.isOwnSplit(from) ?? false)) return null;
    return from;
  }

  /// Fetches and stores the episodes of [seasons] of [show] that are not
  /// stored yet (the first load is the slow one), in the background and
  /// ahead of the daily checks like a season screen's own fetch, so a
  /// season opened from the details, the all-seasons list or the season
  /// before it shows its names at once (owner's request, 2026-11-03).
  /// Stored seasons are skipped, however old; a failure is dropped
  /// quietly, and opening the season asks again.
  Future<void> preload(Entry show, Iterable<int> seasons) async {
    final String? own;
    try {
      own = show.source ?? await resolver.matchedSource(show);
    } on LookupException {
      // No match while offline: opening the season says so.
      return;
    }
    if (own == null) return;
    final source = await _seasonSource(own);
    final lookup = lookups.sourceOf(source);
    if (lookup == null || !lookup.isConfigured) return;
    final from = await _splitOf(show, lookup);
    final key = EpisodeStore.keyFor(source, from);
    for (final season in seasons) {
      if (!_preloading.add((key, season))) continue;
      try {
        if (await store.read(key, season) != null) continue;
        final episodes = await urgentLookups(
          () => lookup.seasonEpisodes(
            source,
            season,
            anime: show.type == MediaType.anime,
            tmdb: show.tmdb,
            from: from,
          ),
        );
        if (episodes == null || episodes.isEmpty) continue;
        await store.write(
          key,
          season,
          episodes,
          fetched: seasonClock(),
          provider: lookup.episodesProvider(source),
        );
      } on LookupException {
        // Opening the season asks again.
      } finally {
        _preloading.remove((key, season));
      }
    }
  }

  /// The id the episodes of [source] are read under. A lookup that cannot
  /// say right now (offline) leaves it as it is.
  Future<String> _seasonSource(String source) async {
    final lookup = lookups.sourceOf(source);
    if (lookup == null || !lookup.isConfigured) return source;
    try {
      return await lookup.seasonSource(source);
    } on LookupException {
      return source;
    }
  }

  /// Drops the episodes of shows that are gone, and those stored under an
  /// id the show no longer reads them by (an anime's old TMDB match).
  Future<void> prune(Iterable<Entry> shows) async {
    final keep = <String>{};
    for (final show in shows) {
      final own = show.source ?? resolver.cachedSource(show);
      if (own == null) continue;
      keep.add(own);
      keep.add(await _seasonSource(own));
    }
    await store.prune(keep);
  }
}
