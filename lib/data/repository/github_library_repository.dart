import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../github/git_blob.dart';
import '../github/github_api.dart';
import '../library_codec.dart';
import '../models/library.dart';
import '../operations/library_operation.dart';
import '../sync/pending_queue.dart';
import '../sync/sync_meta.dart';
import '../sync/sync_status.dart';
import 'library_repository.dart';
import 'library_sync.dart';
import 'local_library_repository.dart';

/// The library on GitHub, with a copy on the device (DESIGN.md section 9
/// and 10b).
///
/// Reads: the cache shows at once; a conditional raw request asks GitHub
/// whether the file changed, on load and whenever the UI asks. Writes: an
/// operation goes into `pending.json`, then into the cache; after a short
/// pause every pending operation is sent as one commit whose message is
/// the operation's summary ("Mark The Mummy as done"). Offline, the queue
/// waits for the next trigger.
///
/// Every sync is a three-way comparison against the base in `sync.json`,
/// the blob of the file as it was when both sides last matched: the
/// phone's copy against the base's canonical form, GitHub's blob against
/// the base's blob. Neither changed: nothing to do. Only the phone:
/// push. Only GitHub: pull. Both, or a save refused for a stale sha: a
/// conflict, and nothing moves until the user picks a side.
class GitHubLibraryRepository implements LibraryRepository, LibrarySync {
  GitHubLibraryRepository({
    required Directory directory,
    required this._api,
    required this.repository,
    required this.path,
    required this.branch,
    this.debounce = const Duration(milliseconds: 2500),
    DateTime Function()? now,
    void Function(String message)? log,
  }) : _now = now ?? DateTime.now,
       _log = log ?? debugPrint,
       _pending = PendingQueue(_file(directory, 'pending.json')),
       _metaStore = SyncMetaStore(_file(directory, 'sync.json')) {
    _cache = LocalLibraryRepository(
      _file(directory, 'library.json'),
      seed: _download,
    );
  }

  static File _file(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  /// "owner/repo".
  final String repository;

  /// The file inside the repo, e.g. `library.json`.
  final String path;
  final String branch;

  /// The file the sync meta must be about, or it is no base (see
  /// [SyncMeta.target]).
  String get _target => '$repository:$path@$branch';

  /// How long edits are gathered before they go out as one commit.
  final Duration debounce;

  final GitHubApi _api;
  final DateTime Function() _now;
  final void Function(String) _log;
  late final LocalLibraryRepository _cache;
  final PendingQueue _pending;
  final SyncMetaStore _metaStore;
  SyncMeta? _meta;
  bool _metaLoaded = false;

  SyncStatus _status = SyncStatus.idle;
  final _statusChanges = StreamController<SyncStatus>.broadcast();
  Timer? _debounce;

  /// Syncs run one after another.
  Future<void> _syncing = Future.value();
  bool _checkedOnLoad = false;
  bool _discarded = false;

  // LibraryRepository

  @override
  Future<Library> load() async {
    final library = await _ensureLoaded();
    if (!_checkedOnLoad) {
      _checkedOnLoad = true;
      // In the background: the cache is already showing.
      _enqueue(() => _sync(push: true));
    }
    return library;
  }

  @override
  Stream<Library> watch() {
    // Through load(), so the queue and the meta are read and the check
    // runs; the cache's stream carries the library and any load error.
    unawaited(load().then((_) {}, onError: (Object _) {}));
    return _cache.watch();
  }

  @override
  Future<Library> apply(LibraryOperation operation) async {
    final current = await _ensureLoaded();
    final latest = _cache.current ?? current;
    if (operation.apply(latest) == latest) return latest;
    // The queue first: a crash between the two never leaves a change in
    // the cache that GitHub will not get.
    await _pending.add(operation, operation.summary(latest));
    _setStatus(_status.copyWith(pendingCount: _pending.length));
    final result = await _cache.apply(operation);
    _restartDebounce();
    return result;
  }

  // LibrarySync

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> get statusChanges => _statusChanges.stream;

  @override
  Future<void> checkForChanges() => _enqueue(() => _sync(push: true));

  @override
  Future<void> syncNow() {
    _debounce?.cancel();
    return _enqueue(() => _sync(push: true));
  }

  @override
  Future<void> resolveConflict({required bool keepMine}) {
    _debounce?.cancel();
    return _enqueue(() => _resolve(keepMine: keepMine));
  }

  @override
  Future<void> discard({bool keepLibrary = false}) async {
    _discarded = true;
    _debounce?.cancel();
    await _syncing;
    if (keepLibrary) {
      // The file and its base stay, for the comparison on a reconnect.
      await _cache.flush();
    } else {
      await _cache.delete();
      await _metaStore.delete();
    }
    await _pending.delete();
  }

  /// Waits for the writes and the syncs in progress. Does not start any.
  Future<void> flush() async {
    await _syncing;
    await _cache.flush();
    await _pending.flush();
  }

  void dispose() {
    _debounce?.cancel();
    _statusChanges.close();
    _cache.dispose();
  }

  // Loading

  Future<Library> _ensureLoaded() async {
    await _pending.load();
    if (!_metaLoaded) {
      // The seed download may have set it meanwhile.
      _meta ??= await _loadMeta();
      _metaLoaded = true;
    }
    try {
      final library = await _cache.load();
      if (_status.pendingCount != _pending.length) {
        _setStatus(_status.copyWith(pendingCount: _pending.length));
      }
      return library;
    } on GitHubException catch (e) {
      // The first download failed; the load fails with it.
      await _report(e);
      rethrow;
    }
  }

  /// The stored base, unless it is about another file.
  Future<SyncMeta?> _loadMeta() async {
    final meta = await _metaStore.load();
    if (meta == null) return null;
    if (meta.target != null && meta.target != _target) {
      _log('The sync meta is for ${meta.target}, not $_target: no base.');
      return null;
    }
    return meta;
  }

  /// The cache's seed on a new install: the file from GitHub.
  Future<String> _download() async {
    final raw = await _api.getFileRaw(path, branch: branch);
    if (raw == null) throw StateError('unconditional request answered 304');
    final remote = decodeLibrary(raw.text);
    final now = _now();
    await _saveMeta(
      SyncMeta(
        etag: raw.etag,
        remoteSha: raw.blobSha,
        canonicalSha: _shaOf(remote),
        lastSynced: _pending.isEmpty ? now : null,
        lastChecked: now,
      ),
    );
    return raw.text;
  }

  // Syncing

  Future<void> _enqueue(Future<void> Function() task) {
    final run = _syncing.then((_) => _discarded ? null : task());
    _syncing = run.catchError((Object _) {});
    return run;
  }

  void _restartDebounce() {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      _enqueue(() => _sync(push: true));
    });
  }

  /// One round: settle a save whose answer was lost, compare both sides
  /// to the base, then pull, push, or stop at a conflict. Failures end up
  /// in the status.
  Future<void> _sync({required bool push}) async {
    try {
      await _ensureLoaded();
      _setStatus(_status.copyWith(phase: SyncPhase.checking));
      await _resolveInFlight();
      var conflict = await _check();
      if (!conflict && push) conflict = await _push();
      _setStatus(
        _status.copyWith(phase: conflict ? SyncPhase.conflict : SyncPhase.idle),
      );
    } on GitHubException catch (e) {
      _log('Sync failed: $e');
      await _report(e);
    } on Object catch (e, stack) {
      // A bug, or a file GitHub holds that the app cannot read. Shown as
      // a failure rather than lost in the chain.
      _log('Sync failed unexpectedly: $e\n$stack');
      _setStatus(_status.copyWith(phase: SyncPhase.failed));
    }
  }

  /// A save was started and its answer never came. Find out whether it
  /// landed before anything is sent again, so no change is saved twice.
  Future<void> _resolveInFlight() async {
    final inFlight = _pending.inFlight;
    if (inFlight == null) return;
    final raw = await _api.getFileRaw(path, branch: branch);
    if (raw == null) return;
    final now = _now();
    if (raw.blobSha == inFlight.blobSha) {
      _log('The save "${inFlight.message}" landed; dropping its operations.');
      await _saveMeta(
        SyncMeta(
          etag: raw.etag,
          remoteSha: raw.blobSha,
          canonicalSha: raw.blobSha,
          lastSynced: now,
          lastChecked: now,
        ),
      );
      await _pending.remove(inFlight.ids);
      return;
    }
    if (raw.blobSha == _meta?.remoteSha) {
      // The file is as it was before the save: it did not land.
      await _pending.clearInFlight();
      await _saveMeta(_meta!.copyWith(etag: raw.etag, lastChecked: now));
      return;
    }
    // Something else was saved since. The commit list tells whether ours
    // is among it.
    final commits = await _api.commits(path, branch: branch, limit: 5);
    final since = inFlight.startedAt.subtract(const Duration(minutes: 5));
    final landed = commits.any(
      (c) => c.message == inFlight.message && c.date.isAfter(since),
    );
    if (landed) {
      _log('The save "${inFlight.message}" landed under later changes.');
      await _pending.remove(inFlight.ids);
      // The base moves to the save: the later changes are GitHub's alone,
      // and the check that follows pulls them.
      await _saveMeta(
        SyncMeta(
          remoteSha: inFlight.blobSha,
          canonicalSha: inFlight.blobSha,
          lastSynced: _meta?.lastSynced,
          lastChecked: now,
        ),
      );
    } else {
      await _pending.clearInFlight();
    }
    // The check that follows sees a changed file and compares.
  }

  /// The blob sha of the phone's copy in the canonical form.
  String get _localSha => _shaOf(_cache.current!);

  /// Asks GitHub whether the file changed and compares both sides to the
  /// base. Pulls when only GitHub changed. Returns true for a conflict:
  /// both changed, and nothing is touched.
  Future<bool> _check() async {
    final meta = _meta;
    final now = _now();
    if (meta == null) {
      // No base (a lost sync.json, or one for another file): GitHub's
      // copy, with whatever is queued applied on top.
      await _takeRemote(null, now);
      return false;
    }
    final raw = await _api.getFileRaw(path, branch: branch, etag: meta.etag);
    final remoteChanged = raw != null && raw.blobSha != meta.remoteSha;
    final localChanged = _localSha != meta.canonicalSha;
    if (!remoteChanged) {
      await _saveMeta(
        meta.copyWith(
          etag: raw?.etag ?? meta.etag,
          lastChecked: now,
          lastSynced: localChanged ? null : now,
        ),
      );
      return false;
    }
    if (!localChanged) {
      await _takeRemote(raw, now);
      return false;
    }
    _log(
      'The file changed on GitHub and on this phone since they last '
      'matched; waiting for a choice.',
    );
    await _saveMeta(meta.copyWith(lastChecked: now));
    // For D17: when GitHub's copy last changed. Not worth failing over.
    try {
      final commits = await _api.commits(path, branch: branch, limit: 1);
      if (commits.isNotEmpty) {
        _setStatus(_status.copyWith(remoteChangedAt: commits.first.date));
      }
    } on GitHubException catch (e) {
      _log('Could not read the last commit: $e');
    }
    return true;
  }

  /// Takes GitHub's copy ([raw], or a fresh download) as the cache and
  /// the new base. With [reapply] the queued operations go on top of it,
  /// dropping any that no longer applies; without it the queue is
  /// dropped whole ("Keep GitHub's").
  Future<void> _takeRemote(
    RawFile? raw,
    DateTime now, {
    bool reapply = true,
  }) async {
    raw ??= await _api.getFileRaw(path, branch: branch);
    if (raw == null) throw StateError('unconditional request answered 304');
    final remote = decodeLibrary(raw.text);
    var library = remote;
    final dropped = <int>[];
    for (final pending in _pending.operations) {
      if (!reapply) {
        dropped.add(pending.id);
        continue;
      }
      try {
        library = pending.operation.apply(library);
      } on Object catch (e) {
        _log('Dropping "${pending.summary}", it no longer applies: $e');
        dropped.add(pending.id);
      }
    }
    if (dropped.isNotEmpty) await _pending.remove(dropped);
    await _cache.replace(library);
    await _saveMeta(
      SyncMeta(
        etag: raw.etag,
        remoteSha: raw.blobSha,
        canonicalSha: _shaOf(remote),
        lastSynced: _pending.isEmpty ? now : _meta?.lastSynced,
        lastChecked: now,
      ),
    );
  }

  /// Sends the phone's copy as one commit when it differs from the base:
  /// the queued operations with their summaries, or, with nothing queued
  /// (edits made while the library was kept on the phone), a plain
  /// message. Returns true when GitHub refused the sha: the file changed
  /// since the check, which is a conflict unless the check now says
  /// otherwise.
  Future<bool> _push() async {
    final meta = _meta!;
    final operations = _pending.operations;
    final ids = operations.map((o) => o.id).toList();
    final bytes = utf8.encode(encodeLibrary(_cache.current!));
    final sha = gitBlobSha(bytes);
    if (sha == meta.canonicalSha) {
      // Nothing to send: the changes cancel out, or are there already.
      if (ids.isNotEmpty) await _pending.remove(ids);
      return false;
    }
    final message = operations.isEmpty
        ? 'Save the changes made on this phone'
        : _message(operations);
    await _pending.markInFlight(
      InFlight(ids: ids, blobSha: sha, message: message, startedAt: _now()),
    );
    _setStatus(_status.copyWith(phase: SyncPhase.saving));
    try {
      final result = await _api.putFile(
        path,
        branch: branch,
        bytes: bytes,
        message: message,
        sha: meta.remoteSha,
      );
      await _saved(result);
      await _pending.remove(ids);
      return false;
    } on GitHubException catch (e) {
      if (e.failure != GitHubFailure.conflict) rethrow;
      // A rejected save never landed. The file changed under it: both
      // sides changed, unless the check finds the phone's copy on GitHub.
      await _pending.clearInFlight();
      _log('The file changed under the save.');
      _setStatus(_status.copyWith(phase: SyncPhase.checking));
      return _check();
    }
  }

  /// The user picked a side (D17). Keep mine: the phone's copy replaces
  /// GitHub's, whatever is there now. Keep GitHub's: its copy replaces
  /// the phone's and the queue is dropped.
  Future<void> _resolve({required bool keepMine}) async {
    try {
      await _ensureLoaded();
      final now = _now();
      if (!keepMine) {
        _setStatus(_status.copyWith(phase: SyncPhase.checking));
        await _takeRemote(null, now, reapply: false);
        _setStatus(_status.copyWith(phase: SyncPhase.idle));
        return;
      }
      _setStatus(_status.copyWith(phase: SyncPhase.saving));
      final current = await _api.getFileRaw(path, branch: branch);
      if (current == null) {
        throw StateError('unconditional request answered 304');
      }
      final operations = _pending.operations;
      final ids = operations.map((o) => o.id).toList();
      final bytes = utf8.encode(encodeLibrary(_cache.current!));
      final message = [
        "Keep this phone's copy of the library",
        if (operations.isNotEmpty) '',
        for (final o in operations) '- ${o.summary}',
      ].join('\n');
      await _pending.markInFlight(
        InFlight(
          ids: ids,
          blobSha: gitBlobSha(bytes),
          message: message,
          startedAt: now,
        ),
      );
      final result = await _api.putFile(
        path,
        branch: branch,
        bytes: bytes,
        message: message,
        sha: current.blobSha,
      );
      await _saved(result);
      await _pending.remove(ids);
      _setStatus(_status.copyWith(phase: SyncPhase.idle));
    } on GitHubException catch (e) {
      _log('Resolving the conflict failed: $e');
      await _report(e);
    }
  }

  /// The base after a successful save: the file is what the phone wrote.
  Future<void> _saved(PutResult result) async {
    final now = _now();
    await _saveMeta(
      SyncMeta(
        // The raw ETag is the quoted blob sha (checked live), so the
        // next check can be conditional without a download first.
        etag: '"${result.blobSha}"',
        remoteSha: result.blobSha,
        canonicalSha: result.blobSha,
        commitSha: result.commitSha,
        lastSynced: now,
        lastChecked: now,
      ),
    );
  }

  /// One operation: its summary. Several: the first and how many more,
  /// with every summary listed in the body.
  static String _message(List<PendingOperation> operations) {
    final first = operations.first.summary;
    if (operations.length == 1) return first;
    final others = operations.length - 1;
    final subject = '$first and $others other change${others == 1 ? '' : 's'}';
    final body = operations.map((o) => '- ${o.summary}').join('\n');
    return '$subject\n\n$body';
  }

  Future<void> _saveMeta(SyncMeta meta) async {
    meta = meta.copyWith(target: _target);
    _meta = meta;
    _setStatus(
      _status.copyWith(
        lastSynced: meta.lastSynced,
        lastChecked: meta.lastChecked,
        pendingCount: _pending.length,
      ),
    );
    await _metaStore.save(meta);
  }

  static String _shaOf(Library library) =>
      gitBlobSha(utf8.encode(encodeLibrary(library)));

  /// The status for a failed call. A 404 gets two more calls to tell
  /// what is gone: the repo (or a token that no longer sees it), the
  /// branch, or the file. That is not a failed save: Retry cannot help,
  /// only the connection can be fixed (D6).
  Future<void> _report(GitHubException e) async {
    if (e.failure != GitHubFailure.notFound) {
      _setStatus(_status.copyWith(phase: _phaseFor(e.failure)));
      return;
    }
    MissingPart missing;
    try {
      await _api.getRepo();
      try {
        await _api.commits(path, branch: branch, limit: 1);
        missing = MissingPart.file;
      } on GitHubException catch (e) {
        if (e.failure != GitHubFailure.notFound) rethrow;
        missing = MissingPart.branch;
      }
    } on GitHubException catch (e) {
      if (e.failure != GitHubFailure.notFound) {
        // Offline or refused while asking: that state, then.
        _setStatus(_status.copyWith(phase: _phaseFor(e.failure)));
        return;
      }
      missing = MissingPart.repository;
    }
    _log('Not found on GitHub: the ${missing.name}.');
    _setStatus(_status.copyWith(phase: SyncPhase.notFound, missing: missing));
  }

  static SyncPhase _phaseFor(GitHubFailure failure) => switch (failure) {
    GitHubFailure.unauthorized ||
    GitHubFailure.forbidden => SyncPhase.tokenProblem,
    GitHubFailure.offline => SyncPhase.offline,
    _ => SyncPhase.failed,
  };

  void _setStatus(SyncStatus status) {
    final next = status.copyWith(pendingCount: _pending.length);
    if (next == _status) return;
    _status = next;
    if (!_statusChanges.isClosed) _statusChanges.add(next);
  }
}
