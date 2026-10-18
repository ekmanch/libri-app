// Talks to a real GitHub repo. Opt in with the token in the environment:
//
//   LIBRI_LIVE_TOKEN=github_pat_… flutter test test/data/github/github_live_test.dart
//
// LIBRI_LIVE_REPO names the repo (default ekmanch/libri-scratch). The test
// works in its own file, live/<timestamp>.json, and removes it at the end.
// The token is never written anywhere.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_app/data/github/git_blob.dart';
import 'package:library_app/data/github/github_api.dart';
import 'package:library_app/data/github/github_http_api.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/long_lists.dart';

void main() {
  final token = Platform.environment['LIBRI_LIVE_TOKEN'];
  final repository =
      Platform.environment['LIBRI_LIVE_REPO'] ?? 'ekmanch/libri-scratch';
  if (token == null || token.isEmpty) {
    test(
      'live GitHub calls',
      () {},
      skip: 'Set LIBRI_LIVE_TOKEN to run against $repository.',
    );
    return;
  }

  final client = http.Client();
  final api = GitHubHttpApi(client, token: token, repository: repository);
  late String branch;
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final path = 'live/$stamp.json';
  late String seed;
  String? sha;

  setUpAll(() async {
    final info = await api.getRepo();
    expect(info.canPush, isTrue, reason: 'the token must be able to write');
    branch = info.defaultBranch;
    // The real library, as the scratch repo holds it; else the fixture.
    try {
      seed = (await api.getFileRaw('library.json', branch: branch))!.text;
    } on GitHubException {
      seed = await File(FixtureLibraryRepository.assetPath).readAsString();
    }
    decodeLibrary(seed); // It must be a library.
    // ignore: avoid_print
    print('Seed: ${seed.length} bytes, branch $branch, file $path');
  });

  tearDownAll(() async {
    if (sha != null) {
      await api.deleteFile(
        path,
        branch: branch,
        sha: sha!,
        message: 'Remove the live test file',
      );
    }
    client.close();
  });

  test('create', () async {
    final bytes = utf8.encode(seed);
    final result = await api.putFile(
      path,
      branch: branch,
      bytes: bytes,
      message: 'Create the live test file',
    );
    sha = result.blobSha;
    expect(result.blobSha, gitBlobSha(bytes), reason: 'the local blob sha');
    expect(result.commitSha, hasLength(40));
  });

  test('read, conditional read and the ETag', () async {
    final raw = await api.getFileRaw(path, branch: branch);
    expect(raw!.text, seed);
    expect(raw.blobSha, sha);
    expect(raw.etag, isNotNull);
    // ignore: avoid_print
    print(
      'ETag ${raw.etag} ${raw.etag == '"${raw.blobSha}"' ? 'is' : 'is not'} '
      'the quoted blob sha',
    );
    final again = await api.getFileRaw(path, branch: branch, etag: raw.etag);
    expect(again, isNull, reason: '304 for the same ETag');
  });

  test('save with the sha, then a stale sha is a conflict', () async {
    final library = decodeLibrary(seed);
    final edited = encodeLibrary(
      library.copyWith(
        entries: [
          library.entries.first.copyWith(note: 'Edited by the live test'),
          ...library.entries.skip(1),
        ],
      ),
    );
    final bytes = utf8.encode(edited);
    final result = await api.putFile(
      path,
      branch: branch,
      bytes: bytes,
      message: 'Edit the live test file',
      sha: sha,
    );
    final stale = sha!;
    sha = result.blobSha;
    expect(result.blobSha, gitBlobSha(bytes));
    await expectLater(
      () => api.putFile(
        path,
        branch: branch,
        bytes: utf8.encode(seed),
        message: 'Must not land',
        sha: stale,
      ),
      throwsA(
        isA<GitHubException>().having(
          (e) => e.failure,
          'failure',
          GitHubFailure.conflict,
        ),
      ),
    );
    final raw = await api.getFileRaw(path, branch: branch);
    expect(raw!.text, edited);
  });

  test('a file over 1 MB is saved and read back whole', () async {
    var library = decodeLibrary(seed);
    var text = encodeLibrary(library);
    var perType = 200;
    while (utf8.encode(text).length < 1200 * 1024) {
      library = padForLongLists(decodeLibrary(seed), perType: perType);
      text = encodeLibrary(library);
      perType *= 2;
    }
    final bytes = utf8.encode(text);
    // ignore: avoid_print
    print(
      'Large file: ${bytes.length} bytes, ${library.entries.length} entries',
    );
    final result = await api.putFile(
      path,
      branch: branch,
      bytes: bytes,
      message: 'Save a large live test file',
      sha: sha,
    );
    sha = result.blobSha;
    expect(result.blobSha, gitBlobSha(bytes));
    final raw = await api.getFileRaw(path, branch: branch);
    expect(raw!.bytes.length, bytes.length);
    expect(raw.blobSha, result.blobSha);
    expect(raw.text, text);
    expect(decodeLibrary(raw.text).entries, hasLength(library.entries.length));
  });

  test('the branches list has the default branch with a date', () async {
    final branches = await api.listBranches();
    final head = branches.singleWhere((b) => b.name == branch);
    expect(head.updated, isNotNull);
  });

  test('the tree and the commits know the file', () async {
    final files = await api.listFiles(branch: branch);
    expect(files.map((f) => f.path), contains(path));
    final commits = await api.commits(path, branch: branch, limit: 5);
    expect(commits.first.message, 'Save a large live test file');
    expect(commits, hasLength(3));
  });
}
