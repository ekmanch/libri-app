import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/demo_states.dart';
import '../../dev/fake_artists.dart';
import '../library_providers.dart';
import '../lookup/apple_artists.dart';
import '../lookup/lookup_providers.dart';
import '../storage/json_file.dart';
import 'artist_photo_fetcher.dart';

/// Apple's artists and their photos (DESIGN.md section 10e), with what was
/// asked kept in `apple_artists.json` under the cache folder. The
/// FIRST_RUN dev switch, the widget tests and the walks get the fake, which
/// asks nobody.
final appleArtistsProvider = Provider<AppleArtists>((ref) {
  if (firstRunDemo) return FakeAppleArtists();
  final cache = ref.watch(appCacheDirectoryProvider).path;
  return AppleArtists(
    ref.watch(appleApiProvider),
    file: JsonFile(File('$cache${Platform.pathSeparator}apple_artists.json')),
  );
});

/// The fetcher of new artists' photos.
final artistPhotoFetcherProvider = Provider<ArtistPhotoFetcher>(
  (ref) => ArtistPhotoFetcher(
    covers: ref.watch(coverStoreProvider),
    apple: ref.watch(appleArtistsProvider),
    network: ref.watch(networkKindProvider),
  ),
);

/// Whether new artists' photos are fetched only on Wi-Fi: the Only on
/// Wi-Fi switch of Settings › Upcoming releases. Read where the
/// preferences live, so this layer does not know them.
final artistPhotosWifiOnlyProvider = Provider<bool>((ref) => true);

/// Looks for the photos of new artists while the app is open: a little
/// after the library loads, and again whenever the library or the cover
/// list changes. The app shell watches it so it runs. Does nothing unless
/// `main` overrides it with [startArtistPhotoFetch], so no test asks
/// anyone.
final artistPhotoFetchProvider = Provider<void>((ref) {});

/// How long after a change the fetcher looks again.
const artistPhotoFetchDelay = Duration(seconds: 5);

/// The real fetch, for the root scope in `main`.
void startArtistPhotoFetch(Ref ref) {
  Timer? timer;
  var disposed = false;
  Future<void> run() async {
    final library = ref.read(libraryProvider).value;
    if (library == null || disposed) return;
    final fetcher = ref.read(artistPhotoFetcherProvider);
    if (fetcher.isRunning) return;
    await fetcher.run(
      library,
      wifiOnly: ref.read(artistPhotosWifiOnlyProvider),
    );
  }

  void schedule() {
    timer?.cancel();
    timer = Timer(artistPhotoFetchDelay, () => unawaited(run()));
  }

  ref.listen(libraryProvider, (_, next) {
    if (next.value != null) schedule();
  }, fireImmediately: true);
  // The list coming, or the record's day arriving, may make artists due.
  ref.listen(artistPhotoFilesProvider, (_, _) => schedule());
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
}
