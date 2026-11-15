import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/demo_states.dart';
import '../../dev/fake_images.dart';
import '../library_providers.dart';
import '../lookup/lookup_providers.dart';
import '../models/entry.dart';
import '../models/library.dart';
import '../operations/operations.dart';
import '../models/entry_kind.dart';
import '../lookup/episode_service.dart';
import '../lookup/series_check.dart';
import '../lookup/series_service.dart';
import '../lookup/track_list_service.dart';
import '../upcoming/creator_lookup.dart';
import '../storage/json_file.dart';
import 'artwork_resolver.dart';
import 'image_cache_store.dart';
import 'image_fetcher.dart';

/// Downloads images. The FIRST_RUN dev switch draws them instead (see
/// `lib/dev/fake_images.dart`); the tests and walks override this too.
final imageFetcherProvider = Provider<ImageFetcher>((ref) {
  if (firstRunDemo) return FakeImageFetcher();
  return HttpImageFetcher(ref.watch(httpClientProvider));
});

/// The image files on the device, under the app cache folder.
final imageCacheProvider = Provider<ImageCacheStore>(
  (ref) => ImageCacheStore(
    Directory(ref.watch(appCacheDirectoryProvider).path),
    fetcher: ref.watch(imageFetcherProvider),
    covers: ref.watch(coverStoreProvider),
  ),
);

/// Covers and artist photos resolved for entries, with the records in
/// `artwork.json` under the app cache folder.
final artworkResolverProvider = Provider<ArtworkResolver>((ref) {
  final cache = ref.watch(appCacheDirectoryProvider);
  final resolver = ArtworkResolver(
    lookups: ref.watch(lookupServiceProvider),
    cache: JsonFile(File('${cache.path}${Platform.pathSeparator}artwork.json')),
  );
  ref.onDispose(resolver.dispose);
  return resolver;
});

/// Once per session, a little after the library first loads: drops the
/// records and image files of entries and artists that are gone. The app
/// shell watches it so it runs. Does nothing unless `main` overrides it
/// with [startArtworkPruner], so no test has a timer it did not ask for.
final artworkPrunerProvider = Provider<void>((ref) {});

/// The real pruner, for the root scope in `main`.
void startArtworkPruner(Ref ref) {
  var done = false;
  Timer? timer;
  ref.listen(libraryProvider, (_, next) {
    final library = next.value;
    if (library == null || done) return;
    done = true;
    timer = Timer(ArtworkPruner.delay, () async {
      final current = ref.read(libraryProvider).value ?? library;
      await ArtworkPruner(
        resolver: ref.read(artworkResolverProvider),
        images: ref.read(imageCacheProvider),
        tracks: ref.read(trackListServiceProvider),
        episodes: ref.read(episodeServiceProvider),
        series: ref.read(seriesServiceProvider),
        upcoming: ref.read(seriesCheckProvider)?.upcoming,
        releases: ref.read(creatorCheckProvider)?.releases,
      ).run(current);
    });
  }, fireImmediately: true);
  ref.onDispose(() => timer?.cancel());
}

/// Keeps the online match of an album in the library: an album without a
/// `source` is matched by title on the device, and the match found is
/// written into its `source` ([SetSource]), so every device reads the same
/// one and a wrong one is corrected once, in Add / edit entry. Every match
/// already on record goes in when the library first loads, each new one as
/// it is found. The app shell watches it so it runs. Does nothing unless
/// `main` overrides it with [startMatchKeeper], so no test writes a match
/// it did not ask for.
final matchKeeperProvider = Provider<void>((ref) {});

/// The real keeper, for the root scope in `main`.
void startMatchKeeper(Ref ref) {
  final keeper = MatchKeeper(
    resolver: ref.read(artworkResolverProvider),
    apply: (operation) => ref.read(libraryRepositoryProvider).apply(operation),
    library: () => ref.read(libraryProvider).value,
  );
  var done = false;
  ref.listen(libraryProvider, (_, next) {
    final library = next.value;
    if (library == null || done) return;
    done = true;
    unawaited(keeper.keepKnown(library));
  }, fireImmediately: true);
  ref.onDispose(keeper.stop);
}

/// The keeper itself, also run by the tests. Albums only: songs and the
/// other types are matched per device.
class MatchKeeper {
  MatchKeeper({
    required this.resolver,
    required this.apply,
    required this.library,
  }) {
    resolver.onMatched = (entry, source) => unawaited(_keep(entry, source));
  }

  final ArtworkResolver resolver;
  final Future<void> Function(LibraryOperation operation) apply;
  final Library? Function() library;

  void stop() => resolver.onMatched = null;

  /// Writes every match on record for an album of [library] with no source.
  Future<void> keepKnown(Library library) async {
    await resolver.load();
    for (final entry in library.entries) {
      final source = entry.source == null ? resolver.cachedSource(entry) : null;
      if (source != null) await _keep(entry, source);
    }
  }

  Future<void> _keep(Entry entry, String source) async {
    if (entry.kind != EntryKind.album || source.startsWith('fake:')) return;
    // The entry as it is now: a match picked meanwhile stays.
    if (library()?.entryById(entry.id)?.source != null) return;
    await apply(SetSource(entry.id, source));
    final after = library()?.entryById(entry.id);
    if (after != null && after.source == source) resolver.matchKept(after);
  }
}

/// The prune itself, also run by the tests. The covers of the upcoming
/// parts and found releases on record ([upcoming], [releases]) are kept
/// too, so a cover the add sheet fetched (Library › Coming soon: add an
/// upcoming entry) stays until the row is gone.
class ArtworkPruner {
  const ArtworkPruner({
    required this.resolver,
    required this.images,
    this.tracks,
    this.episodes,
    this.series,
    this.upcoming,
    this.releases,
  });

  final ArtworkResolver resolver;
  final ImageCacheStore images;
  final TrackListService? tracks;
  final EpisodeService? episodes;
  final SeriesService? series;
  final UpcomingPartsStore? upcoming;
  final FoundReleaseStore? releases;

  static const delay = Duration(seconds: 15);

  Future<void> run(Library library) async {
    final keep = await resolver.prune(entries: library.entries);
    for (final part in await upcoming?.read() ?? const <UpcomingPart>[]) {
      if (part.cover case final cover?) keep.add(cover);
    }
    for (final release in await releases?.read() ?? const <FoundRelease>[]) {
      if (release.match.cacheCoverUrl case final cover?) keep.add(cover);
    }
    await images.prune(keep);
    await tracks?.prune([
      for (final e in library.entries)
        if (e.kind == EntryKind.album) e,
    ]);
    await episodes?.prune([
      for (final e in library.entries)
        if (e.usesSeasons) e,
    ]);
    await series?.prune([
      for (final e in library.entries)
        if (e.series != null) e,
    ]);
  }
}
