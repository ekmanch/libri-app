import 'dart:convert';
import 'dart:typed_data';

import '../data/github/git_blob.dart';
import '../data/github/github_api.dart';
import '../data/library_codec.dart';

/// A GitHub repo in memory, for the widget tests, the repository tests
/// and the FIRST_RUN dev switch: files with blob shas and ETags, saves
/// that check the sha like the Contents API, a commit list and a branch
/// list. The files are the same on every branch; the branch of each file
/// call is recorded in [lastBranch]. Failures can be injected with
/// [failure] and [failNextPut].
class FakeGitHubApi implements GitHubApi {
  FakeGitHubApi({
    Map<String, String> files = const {},
    this.defaultBranch = 'main',
    Map<String, DateTime>? branches,
    this.canPush = true,
    this.latency = Duration.zero,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _branches.addAll(branches ?? {defaultBranch: _now()});
    files.forEach(setFile);
  }

  /// The repo the canvas draws in First run › Pick a branch and Pick an
  /// existing file: the branches `main` (the default, updated two days ago),
  /// `app-sync-test` (last week) and `dev` (August), listed out of order; the
  /// fixture as `library.json`, updated two days ago; a smaller copy in
  /// `backup/library-2025.json` from March; and `data/old-lists.json`, which is
  /// not a library.
  factory FakeGitHubApi.demo(
    String fixtureText, {
    Duration latency = Duration.zero,
    DateTime Function()? now,
  }) {
    final today = (now ?? DateTime.now)();
    final api = FakeGitHubApi(
      latency: latency,
      now: now,
      branches: {
        'dev': DateTime(today.year, 8, 9),
        'main': today.subtract(const Duration(days: 2)),
        'app-sync-test': today.subtract(const Duration(days: 7)),
      },
    );
    final fixture = decodeLibrary(fixtureText);
    api.setFile(
      'library.json',
      fixtureText,
      message: 'Mark The Mummy as done',
      date: today.subtract(const Duration(days: 2)),
    );
    api.setFile(
      'backup/library-2025.json',
      encodeLibrary(
        fixture.copyWith(
          entries: fixture.entries.take(fixture.entries.length ~/ 2).toList(),
          plans: const [],
        ),
      ),
      message: 'Back up the library',
      date: DateTime(today.year, 3, 14),
    );
    api.setFile(
      'data/old-lists.json',
      '[1, 2]\n',
      message: 'Keep the old lists',
    );
    return api;
  }

  /// [FakeGitHubApi.demo] whose fixture is read on the first call: the
  /// FIRST_RUN dev switch, where the asset loads after the app starts.
  factory FakeGitHubApi.demoDeferred(
    Future<String> Function() loadFixture, {
    Duration latency = Duration.zero,
  }) {
    final api = FakeGitHubApi(latency: latency);
    api._loading = loadFixture().then((text) {
      final demo = FakeGitHubApi.demo(text, latency: latency);
      api._files.addAll(demo._files);
      api._commits.addAll(demo._commits);
      api._branches
        ..clear()
        ..addAll(demo._branches);
      api._commitCount = demo._commitCount;
    });
    return api;
  }

  /// How long the FIRST_RUN dev switch's calls take, so the progress
  /// states show.
  static const demoLatency = Duration(milliseconds: 700);

  Future<void>? _loading;

  final String defaultBranch;
  bool canPush;

  /// How long every call takes, so the dev flow shows its progress.
  Duration latency;
  final DateTime Function() _now;
  final Map<String, Uint8List> _files = {};
  final Map<String, List<CommitInfo>> _commits = {};
  final Map<String, DateTime> _branches = {};
  int _commitCount = 0;

  /// The branch named by the last file call (read, save, tree or commits),
  /// for assertions that the chosen branch is used.
  String? lastBranch;

  /// When set, every call fails with it.
  GitHubFailure? failure;

  /// How many calls still pass before [failure] applies: a connection
  /// that drops midway.
  int failAfter = 0;

  /// The next save fails with this, without saving.
  GitHubFailure? failNextPut;

  /// The next save saves, then fails with this: a lost answer.
  GitHubFailure? loseNextPutResponse;

  /// Every call, for assertions: `GET path`, `GET path etag`, `PUT path`.
  final List<String> requests = [];

  int get putCount => requests.where((r) => r.startsWith('PUT')).length;

  /// The file's text, or null.
  String? text(String path) {
    final bytes = _files[path];
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// Sets a file as if someone else pushed it, with a commit.
  void setFile(String path, String text, {String? message, DateTime? date}) {
    _files[path] = Uint8List.fromList(utf8.encode(text));
    _record(path, message ?? 'Edit $path', date: date);
  }

  /// Removes a file as if someone else deleted it, with a commit: reads
  /// of it answer 404, its commit list still knows it.
  void deleteFile(String path) {
    _files.remove(path);
    _record(path, 'Delete $path');
  }

  /// Removes a branch: every file call on it answers 404, like GitHub.
  void deleteBranch(String name) => _branches.remove(name);

  /// A call on a branch the repo does not have: 404.
  void _checkBranch(String branch) {
    if (!_branches.containsKey(branch)) {
      throw const GitHubException(
        GitHubFailure.notFound,
        status: 404,
        message: 'Branch not found',
      );
    }
  }

  void _record(String path, String message, {DateTime? date}) {
    _commitCount++;
    _commits
        .putIfAbsent(path, () => [])
        .insert(
          0,
          CommitInfo(
            sha: 'commit-$_commitCount',
            message: message,
            date: date ?? _now(),
          ),
        );
  }

  Future<void> _call(String request) async {
    requests.add(request);
    await _loading;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failure case final failure?) {
      if (failAfter > 0) {
        failAfter--;
      } else {
        throw GitHubException(failure);
      }
    }
  }

  static String _etag(List<int> bytes) => '"${gitBlobSha(bytes)}"';

  @override
  Future<RepoInfo> getRepo() async {
    await _call('GET repo');
    return RepoInfo(defaultBranch: defaultBranch, canPush: canPush);
  }

  @override
  Future<List<BranchInfo>> listBranches() async {
    await _call('GET branches');
    return [
      for (final MapEntry(key: name, value: updated) in _branches.entries)
        BranchInfo(name: name, updated: updated),
    ];
  }

  @override
  Future<RawFile?> getFileRaw(
    String path, {
    required String branch,
    String? etag,
  }) async {
    lastBranch = branch;
    await _call('GET $path${etag == null ? '' : ' $etag'}');
    _checkBranch(branch);
    final bytes = _files[path];
    if (bytes == null) {
      throw const GitHubException(GitHubFailure.notFound, status: 404);
    }
    if (etag != null && etag == _etag(bytes)) return null;
    return RawFile(Uint8List.fromList(bytes), etag: _etag(bytes));
  }

  @override
  Future<PutResult> putFile(
    String path, {
    required String branch,
    required List<int> bytes,
    required String message,
    String? sha,
  }) async {
    lastBranch = branch;
    await _call('PUT $path');
    _checkBranch(branch);
    if (failNextPut case final failure?) {
      failNextPut = null;
      throw GitHubException(failure);
    }
    final current = _files[path];
    if (current == null ? sha != null : sha != gitBlobSha(current)) {
      throw const GitHubException(GitHubFailure.conflict, status: 422);
    }
    _files[path] = Uint8List.fromList(bytes);
    _record(path, message);
    if (loseNextPutResponse case final failure?) {
      loseNextPutResponse = null;
      throw GitHubException(failure);
    }
    return PutResult(
      blobSha: gitBlobSha(bytes),
      commitSha: _commits[path]!.first.sha,
    );
  }

  @override
  Future<List<TreeFile>> listFiles({
    required String branch,
    String suffix = '.json',
  }) async {
    lastBranch = branch;
    await _call('GET tree');
    _checkBranch(branch);
    return [
      for (final MapEntry(key: path, value: bytes) in _files.entries)
        if (path.endsWith(suffix))
          TreeFile(path: path, size: bytes.length, sha: gitBlobSha(bytes)),
    ];
  }

  @override
  Future<List<CommitInfo>> commits(
    String path, {
    required String branch,
    int limit = 5,
  }) async {
    lastBranch = branch;
    await _call('GET commits $path');
    _checkBranch(branch);
    return (_commits[path] ?? const []).take(limit).toList();
  }
}
