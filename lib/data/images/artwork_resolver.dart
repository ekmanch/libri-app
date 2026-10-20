import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show debugPrint;

import '../lookup/deezer_source.dart';
import '../lookup/lookup_failure.dart';
import '../lookup/lookup_service.dart';
import '../lookup/music_source.dart';
import '../models/entry.dart';
import '../models/media_type.dart';
import '../models/entry_kind.dart';
import '../storage/json_file.dart';

/// Finds the cover image of an entry and the photo of an artist, and
/// remembers what it found in `artwork.json` on the device. An entry with
/// a `source` asks that provider for its cover; one without is matched by
/// title, year and creator (a song by its album), on the device only, so
/// `library.json` never changes. A record is dropped when the entry's
/// title, year, creator or source changed. A miss is tried again after
/// [missRetry]; being offline, rate limited or not set up is not recorded.
/// At most [concurrency] lookups run at once, in the order asked; a
/// request can be released before its turn (the row scrolled away).
class ArtworkResolver {
  ArtworkResolver({
    required this.lookups,
    this.cache,
    this.concurrency = 2,
    DateTime Function()? now,
    this.missRetry = const Duration(days: 14),
    this.writeDelay = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now;

  final LookupService lookups;

  /// `artwork.json`; null keeps the records in memory only (the tests).
  final JsonFile? cache;
  final int concurrency;
  final Duration missRetry;
  final Duration writeDelay;
  final DateTime Function() _now;

  final _entries = <String, _Record>{};
  final _artists = <String, _Record>{};

  /// Why the last lookup of an entry did not work out (offline, rate
  /// limited, a server error, ...); in memory only, cleared by an answer,
  /// so the next session asks again.
  final _failures = <String, LookupFailure>{};
  Future<void>? _loading;
  bool _dirty = false;
  Timer? _writeTimer;

  final _queue = Queue<_Job>();
  final _jobs = <String, _Job>{};
  var _running = 0;

  /// Reads `artwork.json` once.
  Future<void> load() => _loading ??= () async {
    final json = await cache?.read();
    if (json == null) return;
    _readInto(_entries, json['entries']);
    _readInto(_artists, json['artists']);
    if (json['version'] != _version) {
      // Version 1 recorded some failed lookups (a 404, a bad answer, an
      // artist's 5xx) as misses, indistinguishable from real ones: its
      // misses are all looked for again, its covers kept.
      _entries.removeWhere((_, r) => r.url == null);
      _artists.removeWhere((_, r) => r.url == null);
      _markDirty();
    }
  }();

  /// The `artwork.json` format: 2 since misses are only real answers.
  static const _version = 2;

  static void _readInto(Map<String, _Record> into, Object? json) {
    if (json is! Map<String, Object?>) return;
    for (final MapEntry(:key, :value) in json.entries) {
      if (value is Map<String, Object?>) {
        final record = _Record.fromJson(value);
        if (record != null) into[key] = record;
      }
    }
  }

  // Entries ----------------------------------------------------------------

  /// What identifies the entry for the record: a change to any of these
  /// means a new lookup.
  static String keyFor(Entry entry) => [
    entry.title,
    entry.year ?? '',
    entry.creator ?? '',
    entry.album ?? '',
    entry.source ?? '',
  ].join('|');

  _Record? _recordOf(Entry entry) {
    final record = _entries[entry.id];
    if (record == null) return null;
    if (record.key != keyFor(entry)) {
      _entries.remove(entry.id);
      _markDirty();
      return null;
    }
    return record;
  }

  /// The cover URL when it is already known, without waiting. Null before
  /// [load], for a miss, and for an entry never looked at.
  String? cachedCoverUrl(Entry entry) => _recordOf(entry)?.url;

  /// The lookup id the entry was matched to on the device, when known.
  String? cachedSource(Entry entry) => _recordOf(entry)?.source;

  /// The lookup id of an entry without a `source`: the one its cover was
  /// matched to, looking it up when needed (the track list of an album).
  /// Throws [LookupException] when the lookup gave no answer, so being
  /// offline is told from a miss.
  Future<String?> matchedSource(Entry entry) async {
    await load();
    final record = _recordOf(entry);
    if (record != null) return record.source;
    await coverUrl(entry);
    final after = _recordOf(entry);
    if (after == null) {
      final failure = _failures[entry.id];
      if (failure != null) throw LookupException(failure);
    }
    return after?.source;
  }

  /// The cover URL, looking it up when needed; null when there is none
  /// (or none could be fetched right now).
  Future<String?> coverUrl(Entry entry) async {
    await load();
    final record = _recordOf(entry);
    if (record != null) {
      if (record.url != null) return record.url;
      if (_now().difference(record.resolved) < missRetry) return null;
    }
    return _enqueue('entry:${entry.id}', () => _resolveEntry(entry));
  }

  /// Drops the request for [entryId] if it has not started.
  void release(String entryId) => _release('entry:$entryId');

  /// Forgets what was found for [entryId], so the next ask looks again
  /// (after "Look up again" set a source).
  void forget(String entryId) {
    if (_entries.remove(entryId) != null) _markDirty();
  }

  Future<String?> _resolveEntry(Entry entry) async {
    String? url;
    String? source;
    try {
      final found = await _findCover(entry);
      url = found.$1;
      source = found.$2;
    } on LookupException catch (e) {
      // Not an answer, only a lookup that did not work out (offline, a
      // timeout, rate limited, a server error, a bad answer): never
      // recorded, so the next session asks again. Only "no cover" is a miss.
      _failures[entry.id] = e.failure;
      return null;
    }
    _failures.remove(entry.id);
    _entries[entry.id] = _Record(
      key: keyFor(entry),
      url: url,
      source: source,
      resolved: _now(),
    );
    _markDirty();
    return url;
  }

  /// The cover URL and, for an entry matched on the device, the id it was
  /// matched to (the album's, for a song).
  Future<(String?, String?)> _findCover(Entry entry) async {
    if (entry.source case final source?) {
      final provider = lookups.sourceOf(source);
      if (provider == null) return (null, null);
      return (await provider.coverUrl(source, type: entry.type), null);
    }
    final isSong =
        entry.type == MediaType.music && entry.kind == EntryKind.song;
    final title = isSong ? (entry.album ?? entry.title) : entry.title;
    for (final provider in lookups.sourcesFor(entry.type)) {
      final match = await provider.match(
        title,
        type: entry.type,
        year: isSong ? null : entry.year,
        creator: entry.creator,
      );
      if (match != null) return (match.cacheCoverUrl, match.source);
    }
    return (null, null);
  }

  // Artists -----------------------------------------------------------------

  static String _artistKey(String name) => name.trim().toLowerCase();

  MusicSource? get _music {
    for (final source in lookups.sources) {
      if (source.isConfigured && source is MusicSource) {
        return source as MusicSource;
      }
    }
    return null;
  }

  String? cachedArtistPhotoUrl(String name) => _artists[_artistKey(name)]?.url;

  Future<String?> artistPhotoUrl(String name) async {
    await load();
    final key = _artistKey(name);
    if (DeezerSource.noPhoto.contains(key)) return null;
    final record = _artists[key];
    if (record != null) {
      if (record.url != null) return record.url;
      if (_now().difference(record.resolved) < missRetry) return null;
    }
    return _enqueue('artist:$key', () => _resolveArtist(name, key));
  }

  void releaseArtist(String name) => _release('artist:${_artistKey(name)}');

  Future<String?> _resolveArtist(String name, String key) async {
    final music = _music;
    if (music == null) return null;
    final String? url;
    try {
      url = await music.artistPhotoUrl(name);
    } on LookupException {
      // As for covers: only "no photo" is a miss.
      return null;
    }
    _artists[key] = _Record(key: key, url: url, resolved: _now());
    _markDirty();
    return url;
  }

  // Housekeeping ------------------------------------------------------------

  /// Drops the records of entries and artists that are gone and returns
  /// the URLs still wanted, for the image cache's own prune.
  Future<Set<String>> prune({
    required Iterable<Entry> entries,
    required Iterable<String> artists,
  }) async {
    await load();
    final ids = {for (final e in entries) e.id};
    final names = {for (final a in artists) _artistKey(a)};
    final before = _entries.length + _artists.length;
    _entries.removeWhere((id, _) => !ids.contains(id));
    _artists.removeWhere((key, _) => !names.contains(key));
    if (_entries.length + _artists.length != before) _markDirty();
    await flush();
    return {
      for (final r in _entries.values) ?r.url,
      for (final r in _artists.values) ?r.url,
    };
  }

  /// Writes the records now, when something changed, and waits for any
  /// write still on its way.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    final cache = this.cache;
    if (cache == null) {
      _dirty = false;
      return;
    }
    if (_dirty) {
      _dirty = false;
      await cache.write({
        'version': _version,
        'entries': {for (final e in _entries.entries) e.key: e.value.toJson()},
        'artists': {for (final a in _artists.entries) a.key: a.value.toJson()},
      });
    }
    await cache.flush();
  }

  void dispose() {
    _writeTimer?.cancel();
    for (final job in _queue) {
      job.completer.complete(null);
    }
    _queue.clear();
    _jobs.clear();
  }

  void _markDirty() {
    // Nothing to write without a file; no timer either.
    if (cache == null) return;
    _dirty = true;
    if (writeDelay == Duration.zero) {
      // No timer: the tests end with none pending. A failed write of a
      // cache is not worth more than a line in the log.
      unawaited(flush().catchError((Object e) => debugPrint('artwork: $e')));
      return;
    }
    _writeTimer ??= Timer(writeDelay, flush);
  }

  // The queue ---------------------------------------------------------------

  Future<String?> _enqueue(String id, Future<String?> Function() work) {
    final existing = _jobs[id];
    if (existing != null) return existing.completer.future;
    final job = _Job(id, work);
    _jobs[id] = job;
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  void _release(String id) {
    final job = _jobs[id];
    if (job == null || job.started) return;
    _queue.remove(job);
    _jobs.remove(id);
    job.completer.complete(null);
  }

  void _pump() {
    while (_running < concurrency && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      job.started = true;
      _running++;
      job
          .work()
          .then(
            job.completer.complete,
            onError: (Object e, StackTrace s) {
              job.completer.complete(null);
            },
          )
          .whenComplete(() {
            _running--;
            _jobs.remove(job.id);
            _pump();
          });
    }
  }
}

class _Job {
  _Job(this.id, this.work);

  final String id;
  final Future<String?> Function() work;
  final completer = Completer<String?>();
  bool started = false;
}

/// One remembered answer: the URL, or a miss (no URL) with when it was
/// looked for.
class _Record {
  const _Record({
    required this.key,
    this.url,
    this.source,
    required this.resolved,
  });

  final String key;
  final String? url;

  /// The lookup id the entry was matched to, when it has no source of its
  /// own.
  final String? source;
  final DateTime resolved;

  static _Record? fromJson(Map<String, Object?> json) {
    final key = json['key'];
    final resolved = json['resolved'];
    if (key is! String || resolved is! String) return null;
    final date = DateTime.tryParse(resolved);
    if (date == null) return null;
    final url = json['url'];
    final source = json['source'];
    return _Record(
      key: key,
      url: url is String ? url : null,
      source: source is String ? source : null,
      resolved: date,
    );
  }

  Map<String, Object?> toJson() => {
    'key': key,
    if (url != null) 'url': url,
    if (source != null) 'source': source,
    'resolved': resolved.toUtc().toIso8601String(),
  };
}
