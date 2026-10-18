import 'dart:convert';
import 'dart:typed_data';

import 'git_blob.dart';

/// Why a GitHub call failed, as far as the app cares.
enum GitHubFailure {
  /// 401: the token is wrong or expired.
  unauthorized,

  /// 403 for any reason but the rate limit: the token lacks a permission.
  forbidden,

  /// 404: no such repo or file, or a token that cannot see the repo (a
  /// fine-grained token answers 404, not 403, for those).
  notFound,

  /// 409 or 422 on a write: the file changed under us, or already exists.
  conflict,

  /// 403 or 429 with the rate limit used up; try again later.
  rateLimited,

  /// No connection, or the server did not answer in time.
  offline,

  /// Anything else, including a 5xx.
  other,
}

class GitHubException implements Exception {
  const GitHubException(this.failure, {this.status, this.message = ''});

  final GitHubFailure failure;

  /// The HTTP status, when there was a response.
  final int? status;
  final String message;

  @override
  String toString() =>
      'GitHubException(${failure.name}${status == null ? '' : ' $status'}'
      '${message.isEmpty ? '' : ': $message'})';
}

/// What `GET /repos/{owner}/{repo}` tells the app.
class RepoInfo {
  const RepoInfo({required this.defaultBranch, required this.canPush});

  final String defaultBranch;

  /// Whether the token may write to the repo.
  final bool canPush;
}

/// A file downloaded in the raw format.
class RawFile {
  RawFile(this.bytes, {this.etag});

  final Uint8List bytes;

  /// The response's ETag, for the next conditional request. Opaque.
  final String? etag;

  /// The text, always decoded as UTF-8: the raw media type carries no
  /// charset, and `http` would fall back to Latin-1 otherwise.
  late final String text = utf8.decode(bytes);

  /// The sha git gives these bytes, computed locally ([gitBlobSha]).
  late final String blobSha = gitBlobSha(bytes);
}

/// The result of a successful write.
class PutResult {
  const PutResult({required this.blobSha, required this.commitSha});

  final String blobSha;
  final String commitSha;
}

/// A blob in the repo's tree.
class TreeFile {
  const TreeFile({required this.path, required this.size, required this.sha});

  final String path;
  final int size;
  final String sha;
}

/// A commit, from the commits list.
class CommitInfo {
  const CommitInfo({
    required this.sha,
    required this.message,
    required this.date,
  });

  final String sha;
  final String message;
  final DateTime date;
}

/// How many branches [GitHubApi.listBranches] returns at most: one page.
const maxBranches = 100;

/// A branch, from the branches list.
class BranchInfo {
  const BranchInfo({required this.name, this.updated});

  final String name;

  /// When the commit at its head was made; null when not known.
  final DateTime? updated;
}

/// The GitHub calls the app makes, against one repository. Every method
/// throws a [GitHubException] on failure.
abstract interface class GitHubApi {
  Future<RepoInfo> getRepo();

  /// The repo's branches (up to [maxBranches]), in the order GitHub lists
  /// them, each with when its head was committed.
  Future<List<BranchInfo>> listBranches();

  /// The file in the raw format (works to 100 MB). With [etag] the request
  /// is conditional, and null means "unchanged" (304).
  Future<RawFile?> getFileRaw(
    String path, {
    required String branch,
    String? etag,
  });

  /// Creates ([sha] null) or replaces the file in one commit. Replacing
  /// needs the blob sha of the file being replaced; a stale sha, or a
  /// create on an existing file, fails with [GitHubFailure.conflict].
  Future<PutResult> putFile(
    String path, {
    required String branch,
    required List<int> bytes,
    required String message,
    String? sha,
  });

  /// Every blob on [branch] whose path ends in [suffix].
  Future<List<TreeFile>> listFiles({
    required String branch,
    String suffix = '.json',
  });

  /// The newest commits that touched [path], newest first.
  Future<List<CommitInfo>> commits(
    String path, {
    required String branch,
    int limit = 5,
  });
}
