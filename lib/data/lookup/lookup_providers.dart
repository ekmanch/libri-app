import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/demo_states.dart';
import '../../dev/fake_lookup.dart';
import '../library_providers.dart';
import '../storage/json_file.dart';
import 'anilist_source.dart';
import 'anime_link_store.dart';
import 'check_day_store.dart';
import 'deezer_source.dart';
import 'episode_service.dart';
import 'episode_store.dart';
import 'google_books.dart';
import 'igdb_source.dart';
import 'igdb_token_store.dart';
import 'itunes_books.dart';
import 'lookup_keys.dart';
import 'lookup_service.dart';
import 'lookup_source.dart';
import 'open_library_source.dart';
import 'release_check.dart';
import 'season_check.dart';
import 'series_check.dart';
import 'series_service.dart';
import 'series_store.dart';
import 'tmdb_source.dart';
import 'track_list_service.dart';
import 'track_list_store.dart';
import 'wikidata_series.dart';
import '../images/artwork_providers.dart';
import '../models/entry.dart';
import '../models/entry_status.dart';

/// The sources this build looks titles up in. The FIRST_RUN dev switch,
/// the widget tests and the screenshot walks get the fake instead (see
/// `lib/dev/fake_lookup_overrides.dart`). The real sources are added here
/// as they are built.
final lookupSourcesProvider = Provider<List<LookupSource>>((ref) {
  if (firstRunDemo) {
    return [FakeLookupSource(latency: FakeLookupSource.demoLatency)];
  }
  final client = ref.watch(httpClientProvider);
  final cache = ref.watch(appCacheDirectoryProvider);
  // An anime series' seasons and episodes come from TMDB when it has a
  // match there (Show & seasons › Anime with seasons (Frieren)).
  final tmdb = TmdbSource(client, token: LookupKeys.tmdbReadToken);
  return [
    IgdbSource(
      client,
      clientId: LookupKeys.igdbClientId,
      clientSecret: LookupKeys.igdbClientSecret,
      tokens: IgdbTokenStore(
        JsonFile(File('${cache.path}${Platform.pathSeparator}igdb_token.json')),
      ),
      platformsFile: JsonFile(
        File('${cache.path}${Platform.pathSeparator}igdb_platforms.json'),
      ),
    ),
    tmdb,
    AniListSource(client, tmdb: tmdb, links: FileAnimeLinkStore(cache)),
    OpenLibrarySource(
      client,
      apple: ITunesBooks(client),
      google: GoogleBooks(client, key: LookupKeys.googleBooksKey),
      wikidata: WikidataSeries(client),
    ),
    DeezerSource(client),
  ];
});

final lookupServiceProvider = Provider<LookupService>(
  (ref) => LookupService(ref.watch(lookupSourcesProvider)),
);

/// The platforms a game search can be narrowed to (Add / edit entry ›
/// Platform picker), asked once a session; a failure is not kept, so the
/// next open asks again.
final gamePlatformsProvider = FutureProvider<List<GamePlatform>>(
  (ref) => ref.watch(lookupServiceProvider).platforms(),
  retry: (_, _) => null,
);

/// The daily check for new seasons, or null for none. Off by default, so a
/// scope without a cache folder never runs it; `main` turns on
/// [fileSeasonCheck], and the fake overrides one that keeps its day in
/// memory.
final seasonCheckProvider = Provider<SeasonCheck?>((ref) => null);

SeasonCheck fileSeasonCheck(Ref ref) => SeasonCheck(
  lookups: ref.watch(lookupServiceProvider),
  store: FileSeasonCheckStore(ref.watch(appCacheDirectoryProvider)),
);

JsonFile _cacheFile(Ref ref, String name) => JsonFile(
  File(
    '${ref.watch(appCacheDirectoryProvider).path}${Platform.pathSeparator}$name',
  ),
);

/// The daily check of the release dates of entries not out yet (Library ›
/// Home: Coming soon), or null for none; off by default like
/// [seasonCheckProvider]. `main` turns on [fileReleaseCheck].
final releaseCheckProvider = Provider<ReleaseCheck?>((ref) => null);

ReleaseCheck fileReleaseCheck(Ref ref) => ReleaseCheck(
  lookups: ref.watch(lookupServiceProvider),
  store: FileCheckDayStore(_cacheFile(ref, 'release_check.json')),
);

/// The daily check of the series the owner follows, for the parts still to
/// come (for the place that will list everything coming; the home lists
/// only entries set Want), or null for none; off by default
/// like [seasonCheckProvider]. `main` turns on [fileSeriesCheck].
final seriesCheckProvider = Provider<SeriesCheck?>((ref) => null);

SeriesCheck fileSeriesCheck(Ref ref) => SeriesCheck(
  series: ref.watch(seriesServiceProvider),
  store: FileCheckDayStore(_cacheFile(ref, 'series_check.json')),
  upcoming: FileUpcomingPartsStore(_cacheFile(ref, 'upcoming_parts.json')),
);

/// The parts of followed series still to come, as the last series check
/// recorded them; empty without a check. The shell invalidates it after
/// each run. Nothing reads it yet: the home lists only entries set Want,
/// and the place that lists everything coming is still to be built.
final upcomingPartsProvider = FutureProvider<List<UpcomingPart>>(
  (ref) => ref.watch(seriesCheckProvider)?.upcoming.read() ?? Future.value([]),
);

/// Album track lists (Music › Album with track ratings), stored under the app
/// cache folder. The fake overrides keep them in memory.
final trackListServiceProvider = Provider<TrackListService>(
  (ref) => TrackListService(
    lookups: ref.watch(lookupServiceProvider),
    resolver: ref.watch(artworkResolverProvider),
    store: FileTrackListStore(ref.watch(appCacheDirectoryProvider)),
  ),
);

/// The track list of the album entry [entryId]: null when none could be
/// found, an error when the fetch failed (offline, or the source did not
/// answer). Fetched again when the entry's source, title or artist change,
/// not when a track is rated.
final trackListProvider = FutureProvider.autoDispose.family<TrackList?, String>(
  (ref, entryId) async {
    final album = ref.watch(
      libraryProvider.select((l) => _albumKey(l.value?.entryById(entryId))),
    );
    if (album == null) return null;
    return ref.watch(trackListServiceProvider).load(album);
  },
  // No automatic retry: offline is said as such, and opening the album
  // again asks again.
  retry: (_, _) => null,
);

/// Season episodes (Show & seasons › Season episodes (all out) and Season
/// episodes (airing weekly)), stored under the app cache folder. The fake
/// overrides keep them in memory.
final episodeServiceProvider = Provider<EpisodeService>(
  (ref) => EpisodeService(
    lookups: ref.watch(lookupServiceProvider),
    resolver: ref.watch(artworkResolverProvider),
    store: FileEpisodeStore(ref.watch(appCacheDirectoryProvider)),
  ),
);

/// The episodes of season `season` of the show `showId`: the stored ones,
/// then the fetched ones; null when none could be found, an error when the
/// fetch failed with nothing stored. Fetched again when the show's source
/// or title change, not when a season's status does.
final seasonEpisodesProvider = StreamProvider.autoDispose
    .family<SeasonEpisodes?, ({String showId, int season})>(
      (ref, key) {
        final show = ref.watch(
          libraryProvider.select(
            (l) => _showKey(l.value?.entryById(key.showId)),
          ),
        );
        if (show == null) return Stream.value(null);
        return ref.watch(episodeServiceProvider).load(show, key.season);
      },
      // No automatic retry: offline is said as such, and opening the
      // season again asks again.
      retry: (_, _) => null,
    );

/// The parts of the series an entry belongs to (Library › Movie in a series;
/// Book in a long series), stored under the app cache folder. The fake
/// overrides keep them in memory.
final seriesServiceProvider = Provider<SeriesService>(
  (ref) => SeriesService(
    lookups: ref.watch(lookupServiceProvider),
    resolver: ref.watch(artworkResolverProvider),
    store: FileSeriesStore(ref.watch(appCacheDirectoryProvider)),
  ),
);

/// The series of the entry `entryId`: the stored parts, then the fetched
/// ones; null when none could be found, an error when the fetch failed with
/// nothing stored. Fetched again when the entry's source, title, creator or
/// series change, not when its status does.
final seriesPartsProvider = StreamProvider.autoDispose
    .family<SeriesList?, String>(
      (ref, entryId) {
        final entry = ref.watch(
          libraryProvider.select(
            (l) => _seriesKey(l.value?.entryById(entryId)),
          ),
        );
        if (entry == null || entry.series == null) return Stream.value(null);
        return ref.watch(seriesServiceProvider).load(entry);
      },
      // No automatic retry: opening the details again asks again.
      retry: (_, _) => null,
    );

/// The fields the series depend on, so a status pick does not refetch.
Entry? _seriesKey(Entry? entry) => entry == null
    ? null
    : Entry(
        id: entry.id,
        type: entry.type,
        title: entry.title,
        released: entry.released,
        creator: entry.creator,
        status: EntryStatus.want,
        added: entry.added,
        source: entry.source,
        kind: entry.kind,
        series: entry.series,
      );

/// The fields the episodes depend on, so a status pick does not refetch.
Entry? _showKey(Entry? entry) => entry == null
    ? null
    : Entry(
        id: entry.id,
        type: entry.type,
        title: entry.title,
        released: entry.released,
        creator: entry.creator,
        status: EntryStatus.want,
        added: entry.added,
        source: entry.source,
      );

/// The fields the track list depends on, so a rating does not refetch.
Entry? _albumKey(Entry? entry) => entry == null
    ? null
    : Entry(
        id: entry.id,
        type: entry.type,
        title: entry.title,
        released: entry.released,
        creator: entry.creator,
        status: entry.status,
        added: entry.added,
        source: entry.source,
        kind: entry.kind,
        album: entry.album,
      );
