import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../covers/cover_files.dart';
import '../lookup/lookup_failure.dart';
import '../models/entry.dart';
import '../models/entry_kind.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../net/http_transport.dart';
import '../net/network_kind.dart';
import 'artwork_resolver.dart';
import 'image_cache_store.dart';
import 'image_fetcher.dart';
import 'large_cover.dart';

/// How a run of [LargeCoverPass] ended.
enum LargeCoverRunEnd {
  /// Everything that could be fetched was.
  done,

  /// Offline, or on mobile data while Only on Wi-Fi is on: worth another
  /// try in a while.
  interrupted,

  /// The app went to the background, or another run was under way.
  halted,
}

/// What the last run found, for the line in Settings › About.
typedef LargeCoverProgress = ({
  /// The larger versions the library has: one per cover a source offers
  /// larger.
  int wanted,

  /// How many of them this run downloaded, and how long that took.
  int fetched,
  Duration took,
});

/// Fetches the larger version of every cover in the background (owner's
/// decision, 2026-11-21), so Library › Cover, larger is sharp without a
/// wait.
///
/// A run has two parts. First every cover gets the image the lists show:
/// an entry never looked up is looked up and its image fetched, one at a
/// time, so a list never waits behind more than one of these. Then the
/// larger versions ([largeCoverUrl]) that are not on the phone are fetched,
/// [concurrency] at a time, in the library's order. What is on the phone is
/// skipped, so a run continues where the last one stopped.
///
/// Nothing is asked on mobile data while Only on Wi-Fi is on, and nothing
/// starts while a list is waiting for a lookup or an image. A source that
/// answers 429, or 403 twice in a row, is left alone for the session;
/// being offline ends the run. At the end the larger versions no entry
/// shows any more (a deleted entry's, a changed cover's old one) are
/// removed, unless some entry's cover could not be found out this time.
class LargeCoverPass {
  LargeCoverPass({
    required this.resolver,
    required this.small,
    required this.large,
    this.network = const FixedNetworkKind(),
    this.concurrency = 3,
    this.idleCheck = const Duration(milliseconds: 400),
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  final ArtworkResolver resolver;

  /// The images the lists show.
  final ImageCacheStore small;

  /// The larger versions, in a folder of their own.
  final ImageCacheStore large;
  final NetworkKind network;

  /// How many larger versions are downloaded at once. They come from the
  /// sources' image servers, which have no request limit of their own
  /// (the limits are on their APIs); three keeps the phone's connection
  /// free for what a screen asks for.
  final int concurrency;

  /// How often a held-back fetch looks whether the lists are done.
  final Duration idleCheck;
  final void Function(String) _log;

  bool _running = false;
  bool _halted = false;

  /// Lookups were refused this session (rate limited): no more are asked.
  bool _lookupsRefused = false;

  /// The entries whose lookup or image failed this session, by id.
  final _passed = <String>{};

  /// The larger versions that failed this session.
  final _failed = <String>{};

  /// The image servers left alone for the session, and how many 403s in a
  /// row each has given.
  final _stoppedHosts = <String>{};
  final _refusals = <String, int>{};

  LargeCoverProgress? _progress;

  bool get isRunning => _running;

  /// What the last finished run found; null before the first.
  LargeCoverProgress? get progress => _progress;

  /// Stops the run under way after the downloads already started (the app
  /// went to the background).
  void halt() => _halted = true;

  /// One run over [library]. [wifiOnly] is asked before every fetch, so
  /// the switch applies at once.
  Future<LargeCoverRunEnd> run(
    Library library, {
    required bool Function() wifiOnly,
  }) async {
    if (_running) return LargeCoverRunEnd.halted;
    _running = true;
    _halted = false;
    final watch = Stopwatch()..start();
    try {
      await resolver.load();
      final shown = _shownEntries(library);

      // The images the lists show, first.
      var unsettled = false;
      var step = 0;
      for (final entry in shown) {
        if (_halted) return LargeCoverRunEnd.halted;
        // The loop is long: the frames in between get their turn.
        if (++step % 50 == 0) await Future<void>.delayed(Duration.zero);
        var url = resolver.cachedCoverUrl(entry);
        if (url == null) {
          if (resolver.isSettled(entry)) continue;
          if (_lookupsRefused || _passed.contains(entry.id)) {
            unsettled = true;
            continue;
          }
          if (!await _mayFetch(wifiOnly)) return LargeCoverRunEnd.interrupted;
          if (!await _whenIdle()) return LargeCoverRunEnd.halted;
          url = await resolver.coverUrl(entry);
          if (url == null) {
            if (resolver.isSettled(entry)) continue;
            unsettled = true;
            switch (resolver.failureOf(entry)) {
              case LookupFailure.offline:
                return LargeCoverRunEnd.interrupted;
              case LookupFailure.rateLimited:
                _lookupsRefused = true;
              case _:
                _passed.add(entry.id);
            }
            continue;
          }
        }
        if (isRepoCover(url) || small.cachedFile(url) != null) continue;
        if (_passed.contains(entry.id)) continue;
        if (!await _mayFetch(wifiOnly)) return LargeCoverRunEnd.interrupted;
        if (!await _whenIdle()) return LargeCoverRunEnd.halted;
        Object? error;
        final image = await small.get(url, onError: (e) => error = e);
        if (image == null) {
          if (error is NetworkUnreachable) return LargeCoverRunEnd.interrupted;
          _passed.add(entry.id);
        }
      }

      // Then their larger versions.
      final wanted = <String>{};
      for (final entry in shown) {
        final url = resolver.cachedCoverUrl(entry);
        if (url == null || isRepoCover(url)) continue;
        final larger = largeCoverUrl(
          url,
          square: entry.type == MediaType.music,
        );
        if (larger != null) wanted.add(larger);
      }
      final todo = [
        for (final url in wanted)
          if (large.cachedFile(url) == null && !_failed.contains(url)) url,
      ];
      var next = 0;
      var fetched = 0;
      LargeCoverRunEnd? ended;
      Future<void> worker() async {
        while (next < todo.length && ended == null) {
          final url = todo[next++];
          final host = Uri.tryParse(url)?.host ?? '';
          if (_stoppedHosts.contains(host)) continue;
          if (!await _mayFetch(wifiOnly)) {
            ended ??= LargeCoverRunEnd.interrupted;
            return;
          }
          if (!await _whenIdle()) {
            ended ??= LargeCoverRunEnd.halted;
            return;
          }
          if (ended != null || _stoppedHosts.contains(host)) return;
          Object? error;
          final image = await large.get(url, onError: (e) => error = e);
          if (image != null) {
            fetched++;
            _refusals.remove(host);
            continue;
          }
          if (error is NetworkUnreachable) {
            ended ??= LargeCoverRunEnd.interrupted;
            return;
          }
          _failed.add(url);
          final status = switch (error) {
            ImageFetchException(:final status) => status,
            _ => 0,
          };
          // A refusal: 429 at once; 403 only twice in a row, since one
          // 403 may be a file the server does not have.
          final refusals = status == 403 ? (_refusals[host] ?? 0) + 1 : 0;
          if (status == 403) _refusals[host] = refusals;
          if (status == 429 || refusals >= 2) {
            _stoppedHosts.add(host);
            _log('$host refused: no more larger covers from it for now.');
          }
        }
      }

      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
      _progress = (
        wanted: wanted.length,
        fetched: fetched,
        took: watch.elapsed,
      );
      if (ended case final ended?) return ended;
      // Every cover is known, so what is not wanted is nobody's.
      if (!unsettled) await large.prune(wanted);
      return LargeCoverRunEnd.done;
    } finally {
      _running = false;
    }
  }

  Future<bool> _mayFetch(bool Function() wifiOnly) async =>
      !(wifiOnly() && await network.isOnMobileData());

  /// Waits until no list is waiting for a lookup or an image; false when
  /// the run was halted meanwhile.
  Future<bool> _whenIdle() async {
    while (!_halted && (small.isBusy || resolver.isBusy)) {
      await Future<void>.delayed(idleCheck);
    }
    return !_halted;
  }

  /// The entry each entry of [library] shows the cover of, once each, in
  /// the library's order: a song's album while it is in the library with
  /// one of the owner's own covers (as `CoverImage` shows it), else the
  /// entry itself.
  static List<Entry> _shownEntries(Library library) {
    String norm(String? text) => (text ?? '').trim().toLowerCase();
    final albums = <String, Entry>{};
    for (final entry in library.entries) {
      if (entry.type == MediaType.music && entry.kind != EntryKind.song) {
        albums.putIfAbsent(
          '${norm(entry.creator)}\n${norm(entry.title)}',
          () => entry,
        );
      }
    }
    final seen = <String>{};
    final out = <Entry>[];
    for (final entry in library.entries) {
      var shown = entry;
      if (entry.type == MediaType.music &&
          entry.kind == EntryKind.song &&
          !isRepoCover(entry.coverFrom) &&
          norm(entry.album).isNotEmpty &&
          norm(entry.creator).isNotEmpty) {
        final album = albums['${norm(entry.creator)}\n${norm(entry.album)}'];
        if (album != null && isRepoCover(album.coverFrom)) shown = album;
      }
      if (seen.add(shown.id)) out.add(shown);
    }
    return out;
  }
}
