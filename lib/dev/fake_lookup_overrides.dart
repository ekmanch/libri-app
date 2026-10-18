import 'dart:io';

import 'package:flutter_riverpod/misc.dart';

import '../data/images/artwork_providers.dart';
import '../data/images/artwork_resolver.dart';
import '../data/library_providers.dart';
import '../data/lookup/lookup_failure.dart';
import '../data/lookup/lookup_providers.dart';
import '../data/lookup/season_check.dart';
import '../data/lookup/track_list_service.dart';
import '../data/lookup/track_list_store.dart';
import 'fake_images.dart';
import 'fake_lookup.dart';

/// Provider overrides that keep every lookup and image off the network,
/// for the widget tests, the screenshot walks and the accessibility
/// audit: the fake catalog answers, covers are drawn, and the cache lives
/// in [cacheDirectory] (a fresh temporary folder when not given).
/// [latency] shows the loading states, [failure] an error state, and
/// `configured: false` the "not set up" state; [source] replaces the fake
/// those three would build.
List<Override> fakeLookupOverrides({
  Duration latency = Duration.zero,
  LookupFailure? failure,
  bool configured = true,
  Directory? cacheDirectory,
  Set<String>? failingImages,
  FakeLookupSource? source,
}) => [
  lookupSourcesProvider.overrideWithValue([
    source ??
        FakeLookupSource(
          latency: latency,
          failure: failure,
          configured: configured,
        ),
  ]),
  imageFetcherProvider.overrideWithValue(
    FakeImageFetcher(latency: latency, failing: failingImages),
  ),
  appCacheDirectoryProvider.overrideWithValue(
    cacheDirectory ?? Directory.systemTemp.createTempSync('libri-cache-'),
  ),
  // The resolver's records and the track lists stay in memory: no file
  // the widget tests would have to wait for, no write timer pending.
  artworkResolverProvider.overrideWith(
    (ref) => ArtworkResolver(lookups: ref.watch(lookupServiceProvider)),
  ),
  seasonCheckProvider.overrideWith(
    (ref) => SeasonCheck(
      lookups: ref.watch(lookupServiceProvider),
      store: MemorySeasonCheckStore(),
    ),
  ),
  trackListServiceProvider.overrideWith(
    (ref) => TrackListService(
      lookups: ref.watch(lookupServiceProvider),
      resolver: ref.watch(artworkResolverProvider),
      store: MemoryTrackListStore(),
    ),
  ),
];
