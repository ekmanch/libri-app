import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/demo_states.dart';
import '../../dev/fake_images.dart';
import '../../features/music/artist_index.dart';
import '../library_providers.dart';
import '../lookup/lookup_providers.dart';
import '../models/library.dart';
import '../models/entry_kind.dart';
import '../lookup/episode_service.dart';
import '../lookup/series_service.dart';
import '../lookup/track_list_service.dart';
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
      ).run(current);
    });
  }, fireImmediately: true);
  ref.onDispose(() => timer?.cancel());
}

/// The prune itself, also run by the tests.
class ArtworkPruner {
  const ArtworkPruner({
    required this.resolver,
    required this.images,
    this.tracks,
    this.episodes,
    this.series,
  });

  final ArtworkResolver resolver;
  final ImageCacheStore images;
  final TrackListService? tracks;
  final EpisodeService? episodes;
  final SeriesService? series;

  static const delay = Duration(seconds: 15);

  Future<void> run(Library library) async {
    final keep = await resolver.prune(
      entries: library.entries,
      artists: [for (final artist in artistIndex(library.entries)) artist.name],
    );
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
