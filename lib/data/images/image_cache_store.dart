import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../covers/cover_files.dart';
import '../covers/cover_store.dart';
import '../net/http_transport.dart';
import '../storage/atomic_file.dart';
import 'image_fetcher.dart';

/// A cached image: its file, and whether this call downloaded it (then a
/// stale decode of the same path must be evicted before it is shown).
class CachedImage {
  const CachedImage(this.file, {required this.downloadedNow});

  final File file;
  final bool downloadedNow;
}

/// Cover images and artist photos on the device, one file per URL under
/// `<cache>/<folder>/<sha1 of the url>.img`: `images` for the covers the
/// lists show, `images_large` for their larger versions (see
/// `large_cover.dart`), each a store of its own. A URL asked for twice at once is
/// fetched once; a URL that failed is not asked again until [retryAfter]
/// (sooner when the failure was being offline). [prune] drops every file
/// whose URL is no longer wanted.
class ImageCacheStore {
  ImageCacheStore(
    this.directory, {
    required this.fetcher,
    this.covers,
    this.folder = 'images',
    DateTime Function()? now,
    this.retryAfter = const Duration(hours: 6),
    this.offlineRetryAfter = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final Directory directory;
  final ImageFetcher fetcher;

  /// The owner's own covers: a "repo:" key (a `cover_from` naming a file
  /// in the library repo) is one of its files, kept in its own folder and
  /// never in this cache, so every view draws it like a URL.
  final CoverStore? covers;

  /// The folder under [directory] the files are in.
  final String folder;
  final Duration retryAfter;
  final Duration offlineRetryAfter;
  final DateTime Function() _now;

  final _present = <String>{};
  final _inFlight = <String, Future<CachedImage?>>{};
  final _failedUntil = <String, DateTime>{};

  static const _suffix = '.img';

  Directory get imagesDirectory =>
      Directory('${directory.path}${Platform.pathSeparator}$folder');

  static String keyFor(String url) => sha1.convert(utf8.encode(url)).toString();

  File fileFor(String url) => File(
    '${imagesDirectory.path}${Platform.pathSeparator}${keyFor(url)}$_suffix',
  );

  /// The file when it is already on the device, else null, without
  /// waiting: for the first frame of a row that scrolls into view.
  File? cachedFile(String url) {
    if (repoCoverPath(url) case final path?) return covers?.readyFile(path);
    final key = keyFor(url);
    final file = fileFor(url);
    if (_present.contains(key)) return file;
    if (file.existsSync()) {
      _present.add(key);
      return file;
    }
    return null;
  }

  /// Whether a download is under way: the pass that fetches the larger
  /// covers waits while a list is waiting for one of these.
  bool get isBusy => _inFlight.isNotEmpty;

  /// The file, downloading it first when needed. Null when the download
  /// failed; the failure is remembered for a while, and a URL that failed
  /// is not asked again until then unless [retry] says so (a cover opened
  /// large asks every time). [onError] is told why a download failed.
  Future<CachedImage?> get(
    String url, {
    bool retry = false,
    void Function(Object error)? onError,
  }) {
    if (repoCoverPath(url) case final path?) {
      return (covers?.fetch(path) ?? Future.value(null)).then(
        (found) => found == null
            ? null
            : CachedImage(found.$1, downloadedNow: found.$2),
      );
    }
    final cached = cachedFile(url);
    if (cached != null) {
      return Future.value(CachedImage(cached, downloadedNow: false));
    }
    final until = _failedUntil[url];
    if (!retry && until != null && _now().isBefore(until)) {
      return Future.value(null);
    }
    // A block body: returning the removed future would make whenComplete
    // wait for it, that is, for itself.
    return _inFlight[url] ??= _download(url, onError).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<CachedImage?> _download(
    String url,
    void Function(Object error)? onError,
  ) async {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException {
      _failedUntil[url] = _now().add(retryAfter);
      return null;
    }
    try {
      final bytes = await fetcher.fetch(uri);
      final file = fileFor(url);
      await writeBytesAtomically(file, bytes);
      _present.add(keyFor(url));
      _failedUntil.remove(url);
      return CachedImage(file, downloadedNow: true);
    } on NetworkUnreachable catch (e) {
      _failedUntil[url] = _now().add(offlineRetryAfter);
      onError?.call(e);
      return null;
    } on ImageFetchException catch (e) {
      _failedUntil[url] = _now().add(retryAfter);
      onError?.call(e);
      return null;
    } on FileSystemException catch (e) {
      _failedUntil[url] = _now().add(offlineRetryAfter);
      onError?.call(e);
      return null;
    }
  }

  /// How many image files the folder holds and their total size.
  Future<({int files, int bytes})> size() async {
    if (!await imagesDirectory.exists()) return (files: 0, bytes: 0);
    var files = 0;
    var bytes = 0;
    await for (final entity in imagesDirectory.list()) {
      if (entity is! File || !entity.path.endsWith(_suffix)) continue;
      try {
        bytes += await entity.length();
        files++;
      } on FileSystemException {
        // Gone meanwhile.
      }
    }
    return (files: files, bytes: bytes);
  }

  /// Removes every cached file whose URL is not in [keepUrls], and any
  /// half-written file. Returns how many were removed.
  Future<int> prune(Set<String> keepUrls) async {
    if (!await imagesDirectory.exists()) return 0;
    final keep = {for (final url in keepUrls) keyFor(url)};
    var removed = 0;
    await for (final entity in imagesDirectory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final key = name.endsWith(_suffix)
          ? name.substring(0, name.length - _suffix.length)
          : null;
      if (key != null && keep.contains(key)) continue;
      try {
        await entity.delete();
        if (key != null) _present.remove(key);
        removed++;
      } on FileSystemException {
        // In use or gone already; the next prune gets it.
      }
    }
    return removed;
  }
}
