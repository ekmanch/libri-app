import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/github/github_api.dart';
import 'package:library_app/data/github/github_http_api.dart';

void main() {
  late List<http.Request> sent;

  GitHubHttpApi api(Future<http.Response> Function(http.Request) handler) {
    sent = [];
    return GitHubHttpApi(
      MockClient((request) {
        sent.add(request);
        return handler(request);
      }),
      token: 'github_pat_x',
      repository: 'ekmanch/library',
      timeout: const Duration(milliseconds: 200),
    );
  }

  http.Response json(int status, Object body, [Map<String, String>? headers]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json', ...?headers},
      );

  test('sends the token, the API version and a user agent', () async {
    final client = api(
      (_) async => json(200, {
        'default_branch': 'main',
        'permissions': {'push': true},
      }),
    );
    final repo = await client.getRepo();
    expect(repo.defaultBranch, 'main');
    expect(repo.canPush, isTrue);
    final request = sent.single;
    expect(
      request.url.toString(),
      'https://api.github.com/repos/ekmanch/library',
    );
    expect(request.headers['Authorization'], 'Bearer github_pat_x');
    expect(request.headers['X-GitHub-Api-Version'], '2022-11-28');
    expect(request.headers['User-Agent'], 'Libri');
  });

  test('a repo the token cannot push to', () async {
    final client = api(
      (_) async => json(200, {
        'default_branch': 'trunk',
        'permissions': {'push': false, 'pull': true},
      }),
    );
    final repo = await client.getRepo();
    expect(repo.defaultBranch, 'trunk');
    expect(repo.canPush, isFalse);
  });

  group('getFileRaw', () {
    test('asks for the raw format on the branch and decodes UTF-8', () async {
      final client = api(
        (_) async => http.Response.bytes(
          utf8.encode('{"title": "Pokémon"}\n'),
          200,
          headers: {'etag': '"abc"'},
        ),
      );
      final file = await client.getFileRaw('data/library.json', branch: 'main');
      expect(file!.text, '{"title": "Pokémon"}\n');
      expect(file.etag, '"abc"');
      expect(file.blobSha, hasLength(40));
      final request = sent.single;
      expect(
        request.url.toString(),
        'https://api.github.com/repos/ekmanch/library/contents/data/library.json?ref=main',
      );
      expect(request.headers['Accept'], 'application/vnd.github.raw+json');
      expect(request.headers.containsKey('If-None-Match'), isFalse);
    });

    test('a conditional request that answers 304 is null', () async {
      final client = api((_) async => http.Response('', 304));
      final file = await client.getFileRaw(
        'library.json',
        branch: 'main',
        etag: '"abc"',
      );
      expect(file, isNull);
      expect(sent.single.headers['If-None-Match'], '"abc"');
    });

    test('404 is notFound with GitHub\'s message', () async {
      final client = api((_) async => json(404, {'message': 'Not Found'}));
      await expectLater(
        () => client.getFileRaw('nope.json', branch: 'main'),
        throwsA(
          isA<GitHubException>()
              .having((e) => e.failure, 'failure', GitHubFailure.notFound)
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', 'Not Found'),
        ),
      );
    });
  });

  group('putFile', () {
    test(
      'sends the base64 content, the message, the branch and the sha',
      () async {
        final client = api(
          (_) async => json(200, {
            'content': {'sha': 'newsha'},
            'commit': {'sha': 'commitsha'},
          }),
        );
        final result = await client.putFile(
          'library.json',
          branch: 'main',
          bytes: utf8.encode('{}\n'),
          message: 'Mark The Mummy as done',
          sha: 'oldsha',
        );
        expect(result.blobSha, 'newsha');
        expect(result.commitSha, 'commitsha');
        final request = sent.single;
        expect(request.method, 'PUT');
        expect(
          request.url.toString(),
          'https://api.github.com/repos/ekmanch/library/contents/library.json',
        );
        expect(jsonDecode(request.body), {
          'message': 'Mark The Mummy as done',
          'content': base64Encode(utf8.encode('{}\n')),
          'branch': 'main',
          'sha': 'oldsha',
        });
      },
    );

    test('creating a file sends no sha and accepts 201', () async {
      final client = api(
        (_) async => json(201, {
          'content': {'sha': 'newsha'},
          'commit': {'sha': 'c'},
        }),
      );
      await client.putFile(
        'library.json',
        branch: 'main',
        bytes: const [],
        message: 'Create Libri library',
      );
      expect(jsonDecode(sent.single.body), isNot(contains('sha')));
    });

    test('409 and 422 are conflicts', () async {
      for (final status in [409, 422]) {
        final client = api((_) async => json(status, {'message': 'stale'}));
        await expectLater(
          () => client.putFile(
            'library.json',
            branch: 'main',
            bytes: const [],
            message: 'x',
            sha: 'old',
          ),
          throwsA(
            isA<GitHubException>().having(
              (e) => e.failure,
              'failure',
              GitHubFailure.conflict,
            ),
          ),
        );
      }
    });
  });

  group('failures', () {
    Future<GitHubFailure> failureOf(
      Future<http.Response> Function(http.Request) handler,
    ) async {
      try {
        await api(handler).getRepo();
      } on GitHubException catch (e) {
        return e.failure;
      }
      fail('did not throw');
    }

    test('401 is unauthorized', () async {
      expect(
        await failureOf((_) async => json(401, {})),
        GitHubFailure.unauthorized,
      );
    });

    test('403 is forbidden, unless the rate limit is used up', () async {
      expect(
        await failureOf((_) async => json(403, {})),
        GitHubFailure.forbidden,
      );
      expect(
        await failureOf(
          (_) async => json(403, {}, {'x-ratelimit-remaining': '0'}),
        ),
        GitHubFailure.rateLimited,
      );
      expect(
        await failureOf((_) async => json(429, {})),
        GitHubFailure.rateLimited,
      );
    });

    test('a 5xx is other', () async {
      expect(
        await failureOf((_) async => http.Response('', 502)),
        GitHubFailure.other,
      );
    });

    test('no connection is offline', () async {
      expect(
        await failureOf((_) => throw const SocketException('unreachable')),
        GitHubFailure.offline,
      );
      expect(
        await failureOf((_) => throw http.ClientException('closed')),
        GitHubFailure.offline,
      );
    });

    test('a request that never answers is offline', () async {
      expect(
        await failureOf(
          (_) =>
              Future.delayed(const Duration(seconds: 5), () => json(200, {})),
        ),
        GitHubFailure.offline,
      );
    });
  });

  test('listFiles keeps the blobs with the suffix', () async {
    final client = api(
      (_) async => json(200, {
        'tree': [
          {'path': 'library.json', 'type': 'blob', 'size': 270556, 'sha': 'a'},
          {'path': 'docs', 'type': 'tree', 'sha': 'b'},
          {'path': 'docs/old.json', 'type': 'blob', 'size': 12, 'sha': 'c'},
          {'path': 'README.md', 'type': 'blob', 'size': 5, 'sha': 'd'},
        ],
      }),
    );
    final files = await client.listFiles(branch: 'main');
    expect(files.map((f) => f.path), ['library.json', 'docs/old.json']);
    expect(files.first.size, 270556);
    expect(
      sent.single.url.toString(),
      'https://api.github.com/repos/ekmanch/library/git/trees/main?recursive=1',
    );
  });

  test(
    'listBranches asks for one page, then each head commit for its date',
    () async {
      final client = api((request) async {
        final path = request.url.path;
        if (path.endsWith('/branches')) {
          return json(200, [
            {
              'name': 'dev',
              'commit': {'sha': 'd1'},
            },
            {
              'name': 'main',
              'commit': {'sha': 'm1'},
            },
          ]);
        }
        final sha = path.split('/').last;
        return json(200, {
          'sha': sha,
          'commit': {
            'committer': {
              'date': sha == 'm1'
                  ? '2026-10-16T08:00:00Z'
                  : '2026-08-09T10:00:00Z',
            },
          },
        });
      });
      final branches = await client.listBranches();
      expect(branches.map((b) => b.name), ['dev', 'main']);
      expect(branches[0].updated, DateTime.utc(2026, 8, 9, 10));
      expect(branches[1].updated, DateTime.utc(2026, 10, 16, 8));
      expect(
        sent.first.url.toString(),
        'https://api.github.com/repos/ekmanch/library/branches?per_page=100',
      );
      expect(sent.skip(1).map((r) => r.url.path).toSet(), {
        '/repos/ekmanch/library/commits/d1',
        '/repos/ekmanch/library/commits/m1',
      });
    },
  );

  test('commits lists the newest commits that touched the path', () async {
    final client = api(
      (_) async => json(200, [
        {
          'sha': 'c1',
          'commit': {
            'message': 'Mark The Mummy as done',
            'committer': {'date': '2026-10-13T20:00:00Z'},
          },
        },
      ]),
    );
    final commits = await client.commits(
      'library.json',
      branch: 'main',
      limit: 3,
    );
    expect(commits.single.sha, 'c1');
    expect(commits.single.message, 'Mark The Mummy as done');
    expect(commits.single.date, DateTime.utc(2026, 10, 13, 20));
    expect(
      sent.single.url.toString(),
      'https://api.github.com/repos/ekmanch/library/commits?path=library.json&sha=main&per_page=3',
    );
  });

  group('the token expiration header', () {
    final seen = <DateTime>[];
    GitHubHttpApi client(
      int status, {
      Map<String, String> headers = const {},
      Object body = const {'default_branch': 'main'},
    }) {
      seen.clear();
      return GitHubHttpApi(
        MockClient((_) async => json(status, body, headers)),
        token: 'github_pat_x',
        repository: 'ekmanch/library',
        onTokenExpiration: seen.add,
      );
    }

    test('is reported on a successful answer, as a UTC moment', () async {
      await client(
        200,
        headers: {
          'github-authentication-token-expiration': '2025-11-10 16:20:42 +0500',
        },
      ).getRepo();
      expect(seen, [DateTime.utc(2025, 11, 10, 11, 20, 42)]);
    });

    test('is read when GitHub writes it in UTC', () async {
      await client(
        200,
        headers: {
          'github-authentication-token-expiration': '2025-11-10 11:20:42 UTC',
        },
      ).getRepo();
      expect(seen, [DateTime.utc(2025, 11, 10, 11, 20, 42)]);
    });

    test('is not reported on a refused request', () async {
      await expectLater(
        client(
          401,
          headers: {
            'github-authentication-token-expiration':
                '2025-11-10 16:20:42 +0500',
          },
          body: {'message': 'Bad credentials'},
        ).getRepo(),
        throwsA(isA<GitHubException>()),
      );
      expect(seen, isEmpty);
    });

    test('a missing or unreadable header reports nothing', () async {
      await client(200).getRepo();
      await client(
        200,
        headers: {'github-authentication-token-expiration': 'never'},
      ).getRepo();
      expect(seen, isEmpty);
    });
  });
}
