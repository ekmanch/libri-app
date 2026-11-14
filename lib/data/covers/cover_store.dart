import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../github/git_blob.dart';
import '../github/github_api.dart';
import '../models/library.dart';
import '../storage/atomic_file.dart';
import '../storage/json_file.dart';
import 'cover_files.dart';

/// The library repo's `covers/` folder as the phone reaches it: the list,
/// a file's bytes, and a save or a removal as a commit of its own. Paths
/// are the ones under `covers/`.
abstract interface class CoverRemote {
  Future<List<CoverFile>> list();
  Future<Uint8List> download(String path);

  /// Creates the file, or replaces the one whose blob sha is [sha].
  Future<void> put(
    String path,
    List<int> bytes, {
    required String message,
    String? sha,
  });

  Future<void> remove(
    String path, {
    required String sha,
    required String message,
  });
}

/// [CoverRemote] over the GitHub client: one tree call for the list, the
/// Contents API for the rest, like the library file.
class GitHubCoverRemote implements CoverRemote {
  const GitHubCoverRemote(
    this._api, {
    required this.branch,
    required this.libraryFile,
  });

  final GitHubApi _api;
  final String branch;

  /// The library file in the repo, which the folder sits beside.
  final String libraryFile;

  String get _root => coversRoot(libraryFile);

  @override
  Future<List<CoverFile>> list() async {
    final prefix = '$_root/';
    final files = await _api.listFiles(
      branch: branch,
      suffix: '',
      prefix: prefix,
    );
    return [
      for (final file in files)
        CoverFile(
          path: file.path.substring(prefix.length),
          size: file.size,
          sha: file.sha,
        ),
    ];
  }

  @override
  Future<Uint8List> download(String path) async {
    final raw = await _api.getFileRaw('$_root/$path', branch: branch);
    if (raw == null) throw StateError('unconditional request answered 304');
    return raw.bytes;
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    required String message,
    String? sha,
  }) => _api.putFile(
    '$_root/$path',
    branch: branch,
    bytes: bytes,
    message: message,
    sha: sha,
  );

  @override
  Future<void> remove(
    String path, {
    required String sha,
    required String message,
  }) => _api.removeFile(
    '$_root/$path',
    branch: branch,
    sha: sha,
    message: message,
  );
}

/// A change to the cover files, queued until the next sync: paths under
/// `covers/`, and the commit message it goes out with.
sealed class CoverChange {
  const CoverChange(this.summary);

  final String summary;

  Map<String, Object?> toJson();

  static CoverChange? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final summary = json['summary'];
    final path = json['path'];
    if (summary is! String) return null;
    switch (json['change']) {
      case 'upload' when path is String && json['sha'] is String:
        return CoverUpload(
          path,
          sha: json['sha'] as String,
          size: (json['size'] as num?)?.toInt() ?? 0,
          summary: summary,
        );
      case 'delete' when path is String:
        return CoverDelete(path, summary: summary);
      case 'move' when json['from'] is String && json['to'] is String:
        return CoverMove(
          from: json['from'] as String,
          to: json['to'] as String,
          summary: summary,
        );
    }
    return null;
  }
}

/// The file this phone wrote to its own `covers/`.
class CoverUpload extends CoverChange {
  const CoverUpload(
    this.path, {
    required this.sha,
    required this.size,
    required String summary,
  }) : super(summary);

  final String path;
  final String sha;
  final int size;

  @override
  Map<String, Object?> toJson() => {
    'change': 'upload',
    'path': path,
    'sha': sha,
    'size': size,
    'summary': summary,
  };
}

class CoverDelete extends CoverChange {
  const CoverDelete(this.path, {required String summary}) : super(summary);

  final String path;

  @override
  Map<String, Object?> toJson() => {
    'change': 'delete',
    'path': path,
    'summary': summary,
  };
}

/// The same file at another path: a type change moves a title's files to
/// the new type's folder.
class CoverMove extends CoverChange {
  const CoverMove({
    required this.from,
    required this.to,
    required String summary,
  }) : super(summary);

  final String from;
  final String to;

  @override
  Map<String, Object?> toJson() => {
    'change': 'move',
    'from': from,
    'to': to,
    'summary': summary,
  };
}

/// The files of `covers/` as the phone knows them, and its own copies
/// (DESIGN.md section 10d).
///
/// The list is GitHub's, from one tree call, kept in `covers.json` under
/// the cache folder, with the queued changes applied on top. The copies
/// are in `covers/` under the data folder, not the cache: an upload that
/// has not reached GitHub yet must survive a cleared cache. A copy is
/// fetched when a screen shows it, and again when GitHub lists another
/// blob under its name.
///
/// A change is queued in `cover_changes.json` and goes out with the next
/// sync, each as a commit of its own through the Contents API: uploads
/// and the new place of a moved file before the library file, so the
/// library never names a cover that is not there, and removals after it.
/// What is sent is worked out from GitHub's list as it is then, so
/// sending the same change twice does nothing.
///
/// Without a [remote] (the library kept on this phone) the folder is the
/// whole list and a change is done at once. Without a [directory] (the
/// tests) nothing is kept on disk.
class CoverStore extends ChangeNotifier {
  CoverStore({
    this.directory,
    this.remote,
    this.listFile,
    this.queueFile,
    DateTime Function()? now,
    void Function(String message)? log,
    this.retryAfter = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now,
       _log = log ?? debugPrint;

  /// `covers/` beside the phone's library file.
  final Directory? directory;
  final CoverRemote? remote;

  /// `covers.json` under the cache folder: GitHub's list as last seen.
  final JsonFile? listFile;

  /// `cover_changes.json` in the data folder: the queue.
  final JsonFile? queueFile;

  /// How long a download that failed waits before it is tried again.
  final Duration retryAfter;
  final DateTime Function() _now;
  final void Function(String) _log;

  static const _version = 1;

  List<CoverFile> _remote = const [];
  List<CoverFile> _files = const [];
  final List<CoverChange> _queue = [];

  /// The blob sha of each copy on this phone, by path.
  final Map<String, String> _local = {};

  /// Without a [directory]: the bytes themselves.
  final Map<String, Uint8List> _memory = {};
  final Map<String, Future<File?>> _fetching = {};
  final Map<String, DateTime> _failedUntil = {};
  Future<void>? _loading;
  Future<void>? _listing;
  DateTime? _listedAt;

  /// Called when a change is queued, so the sync can pick it up.
  VoidCallback? onQueued;

  /// The files to show: GitHub's with the queued changes on top.
  List<CoverFile> get files => _files;

  CoverFile? fileAt(String path) {
    for (final file in _files) {
      if (file.path == path) return file;
    }
    return null;
  }

  /// The changes not on GitHub yet.
  int get pendingCount => _queue.length;
  List<CoverChange> get pending => List.unmodifiable(_queue);

  /// Whether the list has never come, or is older than [coverListingAge].
  bool get isStale {
    final at = _listedAt;
    return at == null || _now().difference(at) > coverListingAge;
  }

  // Loading and listing ------------------------------------------------------

  /// Reads the list of the last session and the queue, once.
  Future<void> load() => _loading ??= () async {
    final json = await listFile?.read();
    if (json != null && json['version'] == _version) {
      _remote = [
        for (final item in json['files'] as List<Object?>? ?? const [])
          ?CoverFile.fromJson(item),
      ];
      final local = json['local'];
      if (local is Map<String, Object?>) {
        for (final MapEntry(:key, :value) in local.entries) {
          if (value is String) _local[key] = value;
        }
      }
    }
    final queue = await queueFile?.read();
    if (queue != null) {
      for (final item in queue['changes'] as List<Object?>? ?? const []) {
        final change = CoverChange.fromJson(item);
        if (change != null) _queue.add(change);
      }
    }
    if (remote == null) await _scan();
    _rebuild();
  }();

  /// Asks GitHub for the list: at the start, after a sync that pulled
  /// changes, and ([ifStale]) when Pick a cover opens on a list more than
  /// a minute old. Never throws: a failed listing keeps the last one.
  Future<void> refresh({bool ifStale = false}) async {
    await load();
    if (ifStale && !isStale) return;
    await (_listing ??= _list().whenComplete(() {
      _listing = null;
    }));
  }

  Future<void> _list() async {
    final remote = this.remote;
    if (remote == null) {
      await _scan();
      _listedAt = _now();
      _rebuild();
      return;
    }
    try {
      _remote = await remote.list();
    } on GitHubException catch (e) {
      _log('Could not list the covers: $e');
      return;
    }
    _listedAt = _now();
    _rebuild();
    await _saveList();
    await _dropStrayCopies();
  }

  /// The folder on this phone as the whole list: the library is kept
  /// here, so there is no GitHub to ask.
  Future<void> _scan() async {
    final directory = this.directory;
    if (directory == null) {
      _remote = [
        for (final MapEntry(:key, :value) in _memory.entries)
          CoverFile(path: key, size: value.length, sha: _local[key] ?? ''),
      ];
      return;
    }
    final found = <CoverFile>[];
    if (await directory.exists()) {
      final root = directory.path;
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        final path = entity.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        final bytes = await entity.readAsBytes();
        final sha = gitBlobSha(bytes);
        _local[path] = sha;
        found.add(CoverFile(path: path, size: bytes.length, sha: sha));
      }
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    _remote = found;
  }

  /// The shown list from GitHub's and the queued changes.
  void _rebuild() {
    final files = {for (final file in _remote) file.path: file};
    for (final change in _queue) {
      switch (change) {
        case CoverUpload():
          files[change.path] = CoverFile(
            path: change.path,
            size: change.size,
            sha: change.sha,
          );
        case CoverDelete():
          files.remove(change.path);
        case CoverMove():
          final moved = files.remove(change.from);
          if (moved != null) {
            files[change.to] = CoverFile(
              path: change.to,
              size: moved.size,
              sha: moved.sha,
            );
          }
      }
    }
    final next = files.values.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (!listEquals(next, _files)) {
      _files = List.unmodifiable(next);
      notifyListeners();
    }
  }

  /// The list is a cache: a failed write costs a listing, no more.
  Future<void> _saveList() async {
    try {
      await listFile?.write({
        'version': _version,
        'files': [for (final file in _remote) file.toJson()],
        'local': _local,
      });
    } on FileSystemException catch (e) {
      _log('Could not write the cover list: $e');
    }
  }

  Future<void> _saveQueue() async {
    await queueFile?.write({
      'changes': [for (final change in _queue) change.toJson()],
    });
  }

  /// Removes the copies of files that are gone from the list.
  Future<void> _dropStrayCopies() async {
    final listed = {for (final file in _files) file.path};
    final stray = [
      for (final path in _local.keys)
        if (!listed.contains(path)) path,
    ];
    for (final path in stray) {
      await _deleteCopy(path);
    }
    if (stray.isNotEmpty) await _saveList();
  }

  // The copies on this phone -------------------------------------------------

  File? _fileFor(String path) {
    final directory = this.directory;
    if (directory == null || path.contains('..')) return null;
    return File(
      [directory.path, ...path.split('/')].join(Platform.pathSeparator),
    );
  }

  /// The copy of [path] on this phone, when it is there and is the file
  /// the list names (a file replaced on GitHub under the same name is
  /// fetched again). Without waiting, for a row's first frame.
  File? readyFile(String path) {
    final listed = fileAt(path);
    if (listed == null || _local[path] != listed.sha) return null;
    return _fileFor(path);
  }

  /// The bytes of the copy of [path], when it is on this phone.
  Future<Uint8List?> readCopy(String path) async {
    final memory = _memory[path];
    if (memory != null) return memory;
    final file = _fileFor(path);
    if (file == null || !_local.containsKey(path)) return null;
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// The copy of [path], fetched first when needed; null when it is not
  /// listed or could not be fetched right now. The bool says whether this
  /// call wrote the file, so a stale decode of the path can be dropped.
  Future<(File, bool)?> fetch(String path) async {
    await load();
    final ready = readyFile(path);
    if (ready != null) return (ready, false);
    final listed = fileAt(path);
    final target = _fileFor(path);
    if (listed == null || target == null) return null;
    final until = _failedUntil[path];
    if (until != null && _now().isBefore(until)) return null;
    // A block body: returning the removed future would make whenComplete
    // wait for it, that is, for itself.
    final file = await (_fetching[path] ??= _fetch(listed, target).whenComplete(
      () {
        _fetching.remove(path);
      },
    ));
    return file == null ? null : (file, true);
  }

  Future<File?> _fetch(CoverFile listed, File target) async {
    // A copy from before the record was lost (a cleared cache) is told by
    // its sha.
    try {
      if (await target.exists() &&
          gitBlobSha(await target.readAsBytes()) == listed.sha) {
        _local[listed.path] = listed.sha;
        await _saveList();
        return target;
      }
      final remote = this.remote;
      if (remote == null) return null;
      final bytes = await remote.download(listed.path);
      await writeBytesAtomically(target, bytes);
      _local[listed.path] = gitBlobSha(bytes);
      _failedUntil.remove(listed.path);
      await _saveList();
      return target;
    } on GitHubException catch (e) {
      _log('Could not fetch the cover ${listed.path}: $e');
      _failedUntil[listed.path] = _now().add(retryAfter);
      return null;
    } on FileSystemException catch (e) {
      _log('Could not keep the cover ${listed.path}: $e');
      _failedUntil[listed.path] = _now().add(retryAfter);
      return null;
    }
  }

  Future<void> _writeCopy(String path, Uint8List bytes, String sha) async {
    final file = _fileFor(path);
    if (file == null) {
      _memory[path] = bytes;
    } else {
      await writeBytesAtomically(file, bytes);
    }
    _local[path] = sha;
  }

  Future<void> _deleteCopy(String path) async {
    _memory.remove(path);
    _local.remove(path);
    final file = _fileFor(path);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // In use or gone already.
    }
  }

  Future<void> _moveCopy(String from, String to) async {
    final sha = _local.remove(from);
    final memory = _memory.remove(from);
    if (memory != null) _memory[to] = memory;
    final source = _fileFor(from);
    final target = _fileFor(to);
    if (source != null && target != null) {
      try {
        if (await source.exists()) {
          await target.parent.create(recursive: true);
          await source.rename(target.path);
        }
      } on FileSystemException {
        // The copy is fetched again at its new place.
        return;
      }
    }
    if (sha != null) _local[to] = sha;
  }

  // Changes ------------------------------------------------------------------

  /// Keeps an upload on this phone, lists it and queues its save.
  /// [summary] is the commit message: "Add a cover for The Mummy".
  Future<CoverFile> add(
    String path,
    Uint8List bytes, {
    required String sha,
    required String summary,
  }) async {
    await load();
    await _writeCopy(path, bytes, sha);
    final file = CoverFile(path: path, size: bytes.length, sha: sha);
    if (remote == null) {
      _remote = [
        for (final other in _remote)
          if (other.path != path) other,
        file,
      ];
    } else {
      _queue.removeWhere(
        (c) =>
            (c is CoverUpload && c.path == path) ||
            (c is CoverDelete && c.path == path),
      );
      final listed = _remote.where((f) => f.path == path).firstOrNull;
      if (listed?.sha != sha) {
        _queue.add(
          CoverUpload(path, sha: sha, size: bytes.length, summary: summary),
        );
      }
      await _saveQueue();
    }
    _rebuild();
    await _saveList();
    onQueued?.call();
    return file;
  }

  /// Removes a file: from the list and this phone at once, from GitHub
  /// with the next sync.
  Future<void> delete(String path, {required String summary}) async {
    await load();
    if (fileAt(path) == null) return;
    if (remote == null) {
      _remote = [
        for (final file in _remote)
          if (file.path != path) file,
      ];
    } else {
      // An upload that never left needs no removal; a move that never
      // left is a removal of the file where GitHub has it.
      var target = path;
      for (final change in [..._queue]) {
        if (change is CoverUpload && change.path == target) {
          _queue.remove(change);
        } else if (change is CoverMove && change.to == target) {
          _queue.remove(change);
          target = change.from;
        }
      }
      if (_remote.any((f) => f.path == target)) {
        _queue.add(CoverDelete(target, summary: summary));
      }
      await _saveQueue();
    }
    await _deleteCopy(path);
    _rebuild();
    await _saveList();
    onQueued?.call();
  }

  /// Moves a file to another folder: a type change takes a title's files
  /// along.
  Future<void> move(String from, String to, {required String summary}) async {
    await load();
    final file = fileAt(from);
    if (file == null || from == to || fileAt(to) != null) return;
    if (remote == null) {
      _remote = [
        for (final other in _remote)
          if (other.path != from) other,
        CoverFile(path: to, size: file.size, sha: file.sha),
      ];
    } else {
      final upload = _queue
          .whereType<CoverUpload>()
          .where((c) => c.path == from)
          .firstOrNull;
      final earlier = _queue
          .whereType<CoverMove>()
          .where((c) => c.to == from)
          .firstOrNull;
      if (upload != null) {
        // Not on GitHub yet: it is simply saved at the new place.
        _queue[_queue.indexOf(upload)] = CoverUpload(
          to,
          sha: upload.sha,
          size: upload.size,
          summary: upload.summary,
        );
      } else if (earlier != null) {
        final index = _queue.indexOf(earlier);
        if (earlier.from == to) {
          _queue.removeAt(index);
        } else {
          _queue[index] = CoverMove(
            from: earlier.from,
            to: to,
            summary: summary,
          );
        }
      } else {
        _queue.add(CoverMove(from: from, to: to, summary: summary));
      }
      await _saveQueue();
    }
    await _moveCopy(from, to);
    _rebuild();
    await _saveList();
    onQueued?.call();
  }

  // Sync ---------------------------------------------------------------------

  /// GitHub's list during a push, kept between its two halves.
  Map<String, CoverFile>? _tree;

  /// Before the library file is saved: every queued upload, and the new
  /// place of every moved file. Throws [GitHubException]; what was sent
  /// before the failure stays sent.
  Future<void> pushFiles() async {
    await load();
    final remote = this.remote;
    _tree = null;
    if (remote == null || _queue.isEmpty) return;
    final tree = {for (final file in await remote.list()) file.path: file};
    _tree = tree;
    _listedAt = _now();
    for (final change in [..._queue]) {
      switch (change) {
        case CoverUpload():
          final listed = tree[change.path];
          if (listed?.sha != change.sha) {
            final bytes = await readCopy(change.path);
            if (bytes == null) {
              _log('The upload ${change.path} is gone from this phone.');
            } else {
              await remote.put(
                change.path,
                bytes,
                message: change.summary,
                sha: listed?.sha,
              );
              tree[change.path] = CoverFile(
                path: change.path,
                size: bytes.length,
                sha: change.sha,
              );
            }
          }
          _queue.remove(change);
          await _saveQueue();
        case CoverMove():
          final source = tree[change.from];
          final target = tree[change.to];
          if (source == null) {
            // Moved or removed by someone else meanwhile.
            _queue.remove(change);
            await _saveQueue();
          } else if (target?.sha != source.sha) {
            final bytes =
                await readCopy(change.to) ?? await remote.download(change.from);
            await remote.put(
              change.to,
              bytes,
              message: change.summary,
              sha: target?.sha,
            );
            tree[change.to] = CoverFile(
              path: change.to,
              size: bytes.length,
              sha: source.sha,
            );
          }
        case CoverDelete():
          break;
      }
    }
    _remote = tree.values.toList();
    _rebuild();
    await _saveList();
  }

  /// After the library file is saved: the removals, and the old place of
  /// every moved file. A file some title of [library] still shows is
  /// never removed.
  Future<void> pushRemovals(Library library) async {
    final remote = this.remote;
    if (remote == null || _queue.isEmpty) return;
    final tree =
        _tree ?? {for (final file in await remote.list()) file.path: file};
    _tree = null;
    final used = {
      for (final entry in library.entries) ?repoCoverPath(entry.coverFrom),
    };
    for (final change in [..._queue]) {
      final (path, summary) = switch (change) {
        CoverDelete() => (change.path, change.summary),
        CoverMove() => (change.from, change.summary),
        CoverUpload() => (null, ''),
      };
      if (path == null) continue;
      final listed = tree[path];
      if (listed != null && !used.contains(path)) {
        await remote.remove(path, sha: listed.sha, message: summary);
        tree.remove(path);
      } else if (listed != null) {
        _log('Keeping $path: a title still shows it.');
      }
      _queue.remove(change);
      await _saveQueue();
    }
    _remote = tree.values.toList();
    _rebuild();
    await _saveList();
  }

  /// Drops the queue ("Keep GitHub's" in a conflict): the list is
  /// GitHub's again.
  Future<void> dropPending() async {
    await load();
    if (_queue.isEmpty) return;
    _queue.clear();
    await _saveQueue();
    _rebuild();
  }

  /// Forgets everything (Disconnect); with [deleteFiles] the copies on
  /// this phone go too.
  Future<void> clear({required bool deleteFiles}) async {
    await load();
    _queue.clear();
    _remote = const [];
    _listedAt = null;
    await queueFile?.delete();
    await listFile?.delete();
    if (deleteFiles) {
      _local.clear();
      _memory.clear();
      final directory = this.directory;
      try {
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } on FileSystemException {
        // Left behind; a reconnect lists GitHub's again.
      }
    }
    _rebuild();
  }

  /// Waits for the writes in progress.
  Future<void> flush() async {
    await listFile?.flush();
    await queueFile?.flush();
  }
}
