import 'dart:convert';

import 'package:http/http.dart' as http;

import '../net/http_transport.dart';
import 'github_api.dart';

/// [GitHubApi] over the REST API with a fine-grained token.
class GitHubHttpApi implements GitHubApi {
  GitHubHttpApi(
    this._client, {
    required this._token,
    required this._repository,
    Uri? baseUrl,
    this.timeout = defaultHttpTimeout,
    this.userAgent = 'Libri',
  }) : _baseUrl = baseUrl ?? Uri.https('api.github.com');

  final http.Client _client;
  final String _token;

  /// "owner/repo".
  final String _repository;
  final Uri _baseUrl;
  final Duration timeout;
  final String userAgent;

  static const _apiVersion = '2022-11-28';
  static const _rawMediaType = 'application/vnd.github.raw+json';
  static const _jsonMediaType = 'application/vnd.github+json';

  Uri _uri(List<String> segments, [Map<String, String>? query]) =>
      _baseUrl.replace(
        pathSegments: [
          ..._baseUrl.pathSegments.where((s) => s.isNotEmpty),
          'repos',
          ..._repository.split('/'),
          ...segments,
        ],
        queryParameters: query,
      );

  Map<String, String> _headers(String accept, [Map<String, String>? extra]) => {
    'Authorization': 'Bearer $_token',
    'Accept': accept,
    'X-GitHub-Api-Version': _apiVersion,
    'User-Agent': userAgent,
    ...?extra,
  };

  /// Runs [request] and turns transport errors into [GitHubFailure.offline].
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await sendOrOffline(request, timeout: timeout);
    } on NetworkUnreachable catch (e) {
      throw GitHubException(GitHubFailure.offline, message: e.message);
    }
  }

  /// Throws for any status outside [ok].
  void _check(http.Response response, Set<int> ok) {
    final status = response.statusCode;
    if (ok.contains(status)) return;
    final remaining = response.headers['x-ratelimit-remaining'];
    final failure = switch (status) {
      401 => GitHubFailure.unauthorized,
      403 when remaining == '0' => GitHubFailure.rateLimited,
      429 => GitHubFailure.rateLimited,
      403 => GitHubFailure.forbidden,
      404 => GitHubFailure.notFound,
      409 || 422 => GitHubFailure.conflict,
      _ => GitHubFailure.other,
    };
    throw GitHubException(failure, status: status, message: _message(response));
  }

  static String _message(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map && json['message'] is String) {
        return json['message'] as String;
      }
    } on Object {
      // Not JSON; fall through.
    }
    return response.reasonPhrase ?? '';
  }

  Map<String, Object?> _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;

  @override
  Future<RepoInfo> getRepo() async {
    final response = await _send(
      () => _client.get(_uri(const []), headers: _headers(_jsonMediaType)),
    );
    _check(response, const {200});
    final json = _json(response);
    final permissions = json['permissions'];
    return RepoInfo(
      defaultBranch: json['default_branch'] as String? ?? 'main',
      canPush: permissions is Map && permissions['push'] == true,
    );
  }

  @override
  Future<List<BranchInfo>> listBranches() async {
    final response = await _send(
      () => _client.get(
        _uri(const ['branches'], {'per_page': '$maxBranches'}),
        headers: _headers(_jsonMediaType),
      ),
    );
    _check(response, const {200});
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<Object?>;
    // The branches list carries only the head's sha; its date is one more
    // request per branch, made in parallel.
    return Future.wait([
      for (final item in list.cast<Map<String, Object?>>())
        _branch(
          item['name'] as String,
          (item['commit'] as Map<String, Object?>)['sha'] as String,
        ),
    ]);
  }

  Future<BranchInfo> _branch(String name, String headSha) async {
    final response = await _send(
      () => _client.get(
        _uri(['commits', headSha]),
        headers: _headers(_jsonMediaType),
      ),
    );
    _check(response, const {200});
    return BranchInfo(name: name, updated: _commitDate(_json(response)));
  }

  /// The committer date of a commit object from the commits API.
  static DateTime _commitDate(Map<String, Object?> item) => DateTime.parse(
    (((item['commit'] as Map<String, Object?>)['committer']
            as Map<String, Object?>)['date']
        as String),
  );

  @override
  Future<RawFile?> getFileRaw(
    String path, {
    required String branch,
    String? etag,
  }) async {
    final response = await _send(
      () => _client.get(
        _uri(['contents', ...path.split('/')], {'ref': branch}),
        headers: _headers(_rawMediaType, {'If-None-Match': ?etag}),
      ),
    );
    if (response.statusCode == 304) return null;
    _check(response, const {200});
    return RawFile(response.bodyBytes, etag: response.headers['etag']);
  }

  @override
  Future<PutResult> putFile(
    String path, {
    required String branch,
    required List<int> bytes,
    required String message,
    String? sha,
  }) async {
    final response = await _send(
      () => _client.put(
        _uri(['contents', ...path.split('/')]),
        headers: _headers(_jsonMediaType, {'Content-Type': 'application/json'}),
        body: jsonEncode({
          'message': message,
          'content': base64Encode(bytes),
          'branch': branch,
          'sha': ?sha,
        }),
      ),
    );
    _check(response, const {200, 201});
    final json = _json(response);
    final content = json['content'] as Map<String, Object?>;
    final commit = json['commit'] as Map<String, Object?>;
    return PutResult(
      blobSha: content['sha'] as String,
      commitSha: commit['sha'] as String,
    );
  }

  /// Removes a file in one commit. Not part of [GitHubApi]: the app never
  /// deletes; the live test cleans up after itself with it.
  Future<void> deleteFile(
    String path, {
    required String branch,
    required String sha,
    required String message,
  }) async {
    final response = await _send(
      () => _client.delete(
        _uri(['contents', ...path.split('/')]),
        headers: _headers(_jsonMediaType, {'Content-Type': 'application/json'}),
        body: jsonEncode({'message': message, 'sha': sha, 'branch': branch}),
      ),
    );
    _check(response, const {200});
  }

  @override
  Future<List<TreeFile>> listFiles({
    required String branch,
    String suffix = '.json',
  }) async {
    final response = await _send(
      () => _client.get(
        _uri(['git', 'trees', branch], {'recursive': '1'}),
        headers: _headers(_jsonMediaType),
      ),
    );
    _check(response, const {200});
    final tree = _json(response)['tree'] as List<Object?>? ?? const [];
    return [
      for (final item in tree.cast<Map<String, Object?>>())
        if (item['type'] == 'blob' && (item['path'] as String).endsWith(suffix))
          TreeFile(
            path: item['path'] as String,
            size: (item['size'] as num?)?.toInt() ?? 0,
            sha: item['sha'] as String,
          ),
    ];
  }

  @override
  Future<List<CommitInfo>> commits(
    String path, {
    required String branch,
    int limit = 5,
  }) async {
    final response = await _send(
      () => _client.get(
        _uri(
          const ['commits'],
          {'path': path, 'sha': branch, 'per_page': '$limit'},
        ),
        headers: _headers(_jsonMediaType),
      ),
    );
    _check(response, const {200});
    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<Object?>;
    return [
      for (final item in list.cast<Map<String, Object?>>())
        CommitInfo(
          sha: item['sha'] as String,
          message:
              ((item['commit'] as Map<String, Object?>)['message']
                  as String?) ??
              '',
          date: _commitDate(item),
        ),
    ];
  }
}
