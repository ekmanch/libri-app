import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../covers/artist_photo_providers.dart';
import '../library_providers.dart';
import '../lookup/lookup_providers.dart';
import 'artwork_providers.dart';
import 'image_cache_store.dart';
import 'large_cover_pass.dart';

/// The larger versions of the covers on the device, in `images_large`
/// under the app cache folder, apart from the images the lists show.
final largeImageCacheProvider = Provider<ImageCacheStore>(
  (ref) => ImageCacheStore(
    Directory(ref.watch(appCacheDirectoryProvider).path),
    fetcher: ref.watch(imageFetcherProvider),
    folder: 'images_large',
  ),
);

/// The pass that fetches them in the background.
final largeCoverPassProvider = Provider<LargeCoverPass>(
  (ref) => LargeCoverPass(
    resolver: ref.watch(artworkResolverProvider),
    small: ref.watch(imageCacheProvider),
    large: ref.watch(largeImageCacheProvider),
    network: ref.watch(networkKindProvider),
  ),
);

/// What Settings › About says about the larger covers: how many files
/// there are, their total size, and what the last run found.
typedef LargeCoverStatus = ({int files, int bytes, LargeCoverProgress? last});

/// Runs the pass while the app is open: a little after the library loads
/// and again after every change to it, so a new entry, a changed cover and
/// a deleted entry are followed. The app shell watches it so it runs. Does
/// nothing unless `main` overrides it with [startLargeCoverFetch], so no
/// test fetches what it did not ask for.
final largeCoverFetchProvider = Provider<void>((ref) {});

/// How long after a change the pass looks again.
const largeCoverFetchDelay = Duration(seconds: 5);

/// How long after a run that being offline or on mobile data ended.
const largeCoverRetryDelay = Duration(minutes: 5);

/// The real fetch, for the root scope in `main`. It follows Only on Wi-Fi
/// as the artist photos do ([artistPhotosWifiOnlyProvider]).
void startLargeCoverFetch(Ref ref) {
  Timer? timer;
  var disposed = false;
  var again = false;
  final pass = ref.read(largeCoverPassProvider);

  void schedule([Duration delay = largeCoverFetchDelay]) {
    if (disposed) return;
    timer?.cancel();
    timer = Timer(delay, () async {
      final library = ref.read(libraryProvider).value;
      if (library == null || disposed) return;
      if (pass.isRunning) {
        again = true;
        return;
      }
      again = false;
      final end = await pass.run(
        library,
        wifiOnly: () => ref.read(artistPhotosWifiOnlyProvider),
      );
      if (disposed) return;
      if (again) {
        schedule();
      } else if (end == LargeCoverRunEnd.interrupted) {
        schedule(largeCoverRetryDelay);
      }
    });
  }

  ref.listen(libraryProvider, (_, next) {
    if (next.value != null) schedule();
  }, fireImmediately: true);
  // Only while the app is open.
  final lifecycle = AppLifecycleListener(
    onPause: () {
      timer?.cancel();
      pass.halt();
    },
    onResume: schedule,
  );
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    pass.halt();
    lifecycle.dispose();
  });
}
