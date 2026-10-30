import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../github/git_blob.dart';
import '../github/github_api.dart';
import '../library_codec.dart';
import '../models/app_settings.dart';
import '../models/library.dart';
import '../operations/library_operation.dart';
import '../operations/settings_operations.dart';
import '../settings_codec.dart';
import '../sync/pending_queue.dart';
import '../sync/sync_meta.dart';
import '../sync/sync_status.dart';
import 'library_repository.dart';
import 'library_sync.dart';
import 'local_cache.dart';
import 'local_library_repository.dart';

/// The library on GitHub, with a copy on the device (DESIGN.md section 9
/// and 10b), and the settings file beside it (`settings.json`, section 8).
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
///
/// `settings.json` goes through the same comparison against its own base,
/// in the same round, and is saved from the settings operations in the
/// queue as a commit of its own (the Contents API commits one file at a
/// time). A file missing on GitHub is no error: the settings are the
/// defaults until a setting is saved, which creates it.
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
       settingsPath = settingsPathFor(path),
       _pending = PendingQueue(_file(directory, 'pending.json')),
       _metaStore = SyncMetaStore(_file(directory, 'sync.json')) {
    _cache = LocalLibraryRepository(
      _file(directory, 'library.json'),
      seed: _download,
    );
    _settings = LocalCache<AppSettings>(
      _file(directory, 'settings.json'),
      seed: _downloadSettings,
      encode: encodeSettings,
      decode: decodeSettings,
    );
  }

  static File _file(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  /// `settings.json` in the folder of the library file: "settings.json" for
  /// "library.json", "data/settings.json" for "data/library.json".
  static String settingsPathFor(String libraryPath) {
    final slash = libraryPath.lastIndexOf('/');
    return slash < 0
        ? 'settings.json'
        : '${libraryPath.substring(0, slash + 1)}settings.json';
  }

  /// "owner/repo".
  final String repository;

  /// The file inside the repo, e.g. `library.json`.
  final String path;

  /// The settings file inside the repo, beside [path].
  final String settingsPath;
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
  late final LocalCache<AppSettings> _settings;
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

  @override
  Future<AppSettings> loadSettings() async {
    await _ensureLoaded();
    return _settings.load();
  }

  @override
  Stream<AppSettings> watchSettings() {
    unawaited(loadSettings().then((_) {}, onError: (Object _) {}));
    return _settings.watch();
  }

  @override
  Future<AppSettings> applySettings(SettingsOperation operation) async {
    await _ensureLoaded();
    final latest = await _settings.load();
    if (operation.apply(latest) == latest) return latest;
    await _pending.add(operation, operation.summary(latest));
    _setStatus(_status.copyWith(pendingCount: _pending.length));
    final result = await _settings.update(operation.apply);
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
      // The files and their bases stay, for the comparison on a reconnect.
      await _cache.flush();
      await _settings.flush();
    } else {
      await _cache.delete();
      await _settings.delete();
      await _metaStore.delete();
    }
    await _pending.delete();
  }

  /// Waits for the writes and the syncs in progress. Does not start any.
  Future<void> flush() async {
    await _syncing;
    await _cache.flush();
    await _settings.flush();
    await _pending.flush();
  }

  void dispose() {
    _debounce?.cancel();
    _statusChanges.close();
    _cache.dispose();
    _settings.dispose();
  }

  // Loading

  Future<Library> _ensureLoaded() async {
    await _pending.load();
    if (!_metaLoaded) {
      // The seed download may have set it meanwhile.
      _meta ??= await _loadMeta();
      _metaLoaded = true;
    }
    final Library library;
    try {
      library = await _cache.load();
      if (_status.pendingCount != _pending.length) {
        _setStatus(_status.copyWith(pendingCount: _pending.length));
      }
    } on GitHubException catch (e) {
      // The first download failed; the load fails with it.
      await _report(e);
      rethrow;
    }
    // The settings after the library, whose base must exist first. Their
    // seed never throws: offline they start as the defaults with no base,
    // and the next check fetches GitHub's copy.
    await _settings.load();
    return library;
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
        settings: _meta?.settings,
      ),
    );
    return raw.text;
  }

  /// The settings cache's seed: GitHub's `settings.json`, or the defaults
  /// when the file is not there. A failed download (offline) also gives the
  /// defaults, but records no base, so the next check fetches the file.
  Future<String> _downloadSettings() async {
    try {
      final remote = await _fetchSettings();
      await _saveSettingsBase(remote.base);
      return remote.text ?? emptySettingsText;
    } on GitHubException catch (e) {
      _log('Could not fetch $settingsPath, starting with the defaults: $e');
      return emptySettingsText;
    }
  }

  /// `settings.json` on GitHub as text with its base; the defaults with a
  /// base that says "not on GitHub" when the file is missing; null text when
  /// [etag] still matches.
  Future<({String? text, FileBase base, bool unchanged})> _fetchSettings({
    String? etag,
  }) async {
    try {
      final raw = await _api.getFileRaw(
        settingsPath,
        branch: branch,
        etag: etag,
      );
      if (raw == null) {
        return (
          text: null,
          base: _meta!.settings!.copyWith(etag: etag),
          unchanged: true,
        );
      }
      final remote = decodeSettings(raw.text);
      return (
        text: raw.text,
        base: FileBase(
          etag: raw.etag,
          remoteSha: raw.blobSha,
          canonicalSha: _settingsShaOf(remote),
        ),
        unchanged: false,
      );
    } on GitHubException catch (e) {
      if (e.failure != GitHubFailure.notFound) rethrow;
      return (
        text: emptySettingsText,
        base: FileBase(
          remoteSha: null,
          canonicalSha: _settingsShaOf(AppSettings.defaults),
        ),
        unchanged: false,
      );
    }
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
    final file = inFlight.path ?? path;
    final isSettings = file == settingsPath && file != path;
    final now = _now();
    final RawFile? raw;
    try {
      raw = await _api.getFileRaw(file, branch: branch);
    } on GitHubException catch (e) {
      if (!isSettings || e.failure != GitHubFailure.notFound) rethrow;
      // The settings file is not there: the save did not land.
      await _pending.clearInFlight();
      return;
    }
    if (raw == null) return;
    if (raw.blobSha == inFlight.blobSha) {
      _log('The save "${inFlight.message}" landed; dropping its operations.');
      if (isSettings) {
        await _saveSettingsBase(
          FileBase(
            etag: raw.etag,
            remoteSha: raw.blobSha,
            canonicalSha: raw.blobSha,
          ),
        );
      } else {
        await _saveMeta(
          SyncMeta(
            etag: raw.etag,
            remoteSha: raw.blobSha,
            canonicalSha: raw.blobSha,
            lastSynced: now,
            lastChecked: now,
            settings: _meta?.settings,
          ),
        );
      }
      await _pending.remove(inFlight.ids);
      return;
    }
    final baseSha = isSettings ? _meta?.settings?.remoteSha : _meta?.remoteSha;
    if (raw.blobSha == baseSha) {
      // The file is as it was before the save: it did not land.
      await _pending.clearInFlight();
      if (isSettings) {
        await _saveSettingsBase(_meta!.settings!.copyWith(etag: raw.etag));
      } else {
        await _saveMeta(_meta!.copyWith(etag: raw.etag, lastChecked: now));
      }
      return;
    }
    // Something else was saved since. The commit list tells whether ours
    // is among it.
    final commits = await _api.commits(file, branch: branch, limit: 5);
    final since = inFlight.startedAt.subtract(const Duration(minutes: 5));
    final landed = commits.any(
      (c) => c.message == inFlight.message && c.date.isAfter(since),
    );
    if (landed) {
      _log('The save "${inFlight.message}" landed under later changes.');
      await _pending.remove(inFlight.ids);
      // The base moves to the save: the later changes are GitHub's alone,
      // and the check that follows pulls them.
      if (isSettings) {
        await _saveSettingsBase(
          FileBase(remoteSha: inFlight.blobSha, canonicalSha: inFlight.blobSha),
        );
      } else {
        await _saveMeta(
          SyncMeta(
            remoteSha: inFlight.blobSha,
            canonicalSha: inFlight.blobSha,
            lastSynced: _meta?.lastSynced,
            lastChecked: now,
            settings: _meta?.settings,
          ),
        );
      }
    } else {
      await _pending.clearInFlight();
    }
    // The check that follows sees a changed file and compares.
  }

  /// The blob sha of the phone's copy in the canonical form.
  String get _localSha => _shaOf(_cache.current!);

  String get _localSettingsSha => _settingsShaOf(_settings.current!);

  /// Asks GitHub whether the files changed and compares both sides to the
  /// base. Pulls when only GitHub changed. Returns true for a conflict:
  /// both changed, and nothing is touched.
  Future<bool> _check() async {
    final conflict = await _checkLibrary();
    return await _checkSettings() || conflict;
  }

  Future<bool> _checkLibrary() async {
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
    await _noteRemoteChange(path);
    return true;
  }

  /// The same comparison for `settings.json`. A file missing on GitHub
  /// counts as "not there" on that side, so creating it on the phone is a
  /// push and someone else creating it is a pull.
  Future<bool> _checkSettings() async {
    final base = _meta?.settings;
    if (base == null) {
      // No base yet (a sync.json from before the file, or a start offline):
      // GitHub's copy, with whatever is queued applied on top.
      await _takeRemoteSettings(null);
      return false;
    }
    final remote = await _fetchSettings(etag: base.etag);
    final remoteChanged =
        !remote.unchanged && remote.base.remoteSha != base.remoteSha;
    final localChanged = _localSettingsSha != base.canonicalSha;
    if (!remoteChanged) {
      if (remote.base.etag != base.etag) {
        await _saveSettingsBase(base.copyWith(etag: remote.base.etag));
      }
      return false;
    }
    if (!localChanged) {
      await _takeRemoteSettings(remote);
      return false;
    }
    _log(
      'The settings changed on GitHub and on this phone since they last '
      'matched; waiting for a choice.',
    );
    await _noteRemoteChange(settingsPath);
    return true;
  }

  /// When GitHub's copy of [file] last changed, for Library › Conflict: keep
  /// which copy? Not worth failing over.
  Future<void> _noteRemoteChange(String file) async {
    try {
      final commits = await _api.commits(file, branch: branch, limit: 1);
      if (commits.isNotEmpty) {
        _setStatus(_status.copyWith(remoteChangedAt: commits.first.date));
      }
    } on GitHubException catch (e) {
      _log('Could not read the last commit: $e');
    }
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
    for (final pending in _pending.libraryOperations) {
      if (!reapply) {
        dropped.add(pending.id);
        continue;
      }
      try {
        library = pending.library!.apply(library);
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
        settings: _meta?.settings,
      ),
    );
  }

  /// [_takeRemote] for the settings: GitHub's copy ([remote], or a fresh
  /// fetch; the defaults when the file is not there) as the cache and the
  /// new base, the queued settings operations on top unless [reapply] is
  /// off.
  Future<void> _takeRemoteSettings(
    ({String? text, FileBase base, bool unchanged})? remote, {
    bool reapply = true,
  }) async {
    remote ??= await _fetchSettings();
    final text = remote.text;
    if (text == null) throw StateError('unconditional request answered 304');
    var settings = decodeSettings(text);
    final dropped = <int>[];
    for (final pending in _pending.settingsOperations) {
      if (!reapply) {
        dropped.add(pending.id);
        continue;
      }
      settings = pending.settings!.apply(settings);
    }
    if (dropped.isNotEmpty) await _pending.remove(dropped);
    await _settings.replace(settings);
    await _saveSettingsBase(remote.base);
  }

  /// Sends the phone's copies as commits, one per file that differs from
  /// its base. Returns true when GitHub refused a sha: the file changed
  /// since the check, which is a conflict unless the check now says
  /// otherwise.
  Future<bool> _push() async {
    if (await _pushLibrary()) return true;
    return _pushSettings();
  }

  /// The library: the queued operations with their summaries, or, with
  /// nothing queued (edits made while the library was kept on the phone),
  /// a plain message.
  Future<bool> _pushLibrary() async {
    final meta = _meta!;
    final operations = _pending.libraryOperations;
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

  /// The settings: the queued settings operations as one commit ("Unfollow
  /// 3 authors"); created when the file is not on GitHub yet.
  Future<bool> _pushSettings() async {
    final base = _meta?.settings;
    if (base == null) return false;
    final operations = _pending.settingsOperations;
    final ids = operations.map((o) => o.id).toList();
    final bytes = utf8.encode(encodeSettings(_settings.current!));
    final sha = gitBlobSha(bytes);
    if (sha == base.canonicalSha) {
      if (ids.isNotEmpty) await _pending.remove(ids);
      return false;
    }
    final message = operations.isEmpty
        ? 'Save the settings changed on this phone'
        : settingsMessage([
            for (final o in operations)
              (operation: o.settings!, summary: o.summary),
          ]);
    await _pending.markInFlight(
      InFlight(
        ids: ids,
        blobSha: sha,
        message: message,
        startedAt: _now(),
        path: settingsPath,
      ),
    );
    _setStatus(_status.copyWith(phase: SyncPhase.saving));
    try {
      final result = await _api.putFile(
        settingsPath,
        branch: branch,
        bytes: bytes,
        message: message,
        sha: base.remoteSha,
      );
      await _saveSettingsBase(
        FileBase(
          etag: '"${result.blobSha}"',
          remoteSha: result.blobSha,
          canonicalSha: result.blobSha,
        ),
      );
      await _pending.remove(ids);
      return false;
    } on GitHubException catch (e) {
      if (e.failure != GitHubFailure.conflict) rethrow;
      await _pending.clearInFlight();
      _log('The settings file changed under the save.');
      _setStatus(_status.copyWith(phase: SyncPhase.checking));
      return _checkSettings();
    }
  }

  /// The user picked a side (Library › Conflict: keep which copy?). Keep mine:
  /// the phone's copies replace GitHub's, whatever is there now. Keep GitHub's:
  /// its copies replace the phone's and the queue is dropped. Both files go
  /// the same way: one choice, however many of them changed.
  Future<void> _resolve({required bool keepMine}) async {
    try {
      await _ensureLoaded();
      final now = _now();
      if (!keepMine) {
        _setStatus(_status.copyWith(phase: SyncPhase.checking));
        await _takeRemote(null, now, reapply: false);
        await _takeRemoteSettings(null, reapply: false);
        _setStatus(_status.copyWith(phase: SyncPhase.idle));
        return;
      }
      _setStatus(_status.copyWith(phase: SyncPhase.saving));
      await _keepMineLibrary(now);
      await _keepMineSettings(now);
      _setStatus(_status.copyWith(phase: SyncPhase.idle));
    } on GitHubException catch (e) {
      _log('Resolving the conflict failed: $e');
      await _report(e);
    }
  }

  Future<void> _keepMineLibrary(DateTime now) async {
    final current = await _api.getFileRaw(path, branch: branch);
    if (current == null) {
      throw StateError('unconditional request answered 304');
    }
    final operations = _pending.libraryOperations;
    final ids = operations.map((o) => o.id).toList();
    final bytes = utf8.encode(encodeLibrary(_cache.current!));
    if (gitBlobSha(bytes) == current.blobSha) {
      // The phone's copy is GitHub's already (only the settings differed).
      await _saved(
        PutResult(blobSha: current.blobSha, commitSha: _meta?.commitSha ?? ''),
      );
      if (ids.isNotEmpty) await _pending.remove(ids);
      return;
    }
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
  }

  Future<void> _keepMineSettings(DateTime now) async {
    final remote = await _fetchSettings();
    final operations = _pending.settingsOperations;
    final ids = operations.map((o) => o.id).toList();
    final bytes = utf8.encode(encodeSettings(_settings.current!));
    final sha = gitBlobSha(bytes);
    if (sha == remote.base.remoteSha ||
        (remote.base.remoteSha == null && sha == remote.base.canonicalSha)) {
      // The phone's settings are GitHub's already (or both are the defaults).
      await _saveSettingsBase(remote.base);
      if (ids.isNotEmpty) await _pending.remove(ids);
      return;
    }
    final message = [
      "Keep this phone's copy of the settings",
      if (operations.isNotEmpty) '',
      for (final o in operations) '- ${o.summary}',
    ].join('\n');
    await _pending.markInFlight(
      InFlight(
        ids: ids,
        blobSha: sha,
        message: message,
        startedAt: now,
        path: settingsPath,
      ),
    );
    final result = await _api.putFile(
      settingsPath,
      branch: branch,
      bytes: bytes,
      message: message,
      sha: remote.base.remoteSha,
    );
    await _saveSettingsBase(
      FileBase(
        etag: '"${result.blobSha}"',
        remoteSha: result.blobSha,
        canonicalSha: result.blobSha,
      ),
    );
    await _pending.remove(ids);
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
        settings: _meta?.settings,
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

  /// The settings base into the meta; nothing is recorded before the
  /// library has a base, since the settings are fetched after it.
  Future<void> _saveSettingsBase(FileBase base) async {
    final meta = _meta;
    if (meta == null) return;
    await _saveMeta(meta.copyWith(settings: base));
  }

  static String _shaOf(Library library) =>
      gitBlobSha(utf8.encode(encodeLibrary(library)));

  static String _settingsShaOf(AppSettings settings) =>
      gitBlobSha(utf8.encode(encodeSettings(settings)));

  /// The status for a failed call. A 404 gets two more calls to tell
  /// what is gone: the repo (or a token that no longer sees it), the
  /// branch, or the file. That is not a failed save: Retry cannot help,
  /// only the connection can be fixed (Settings › Library connection).
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
