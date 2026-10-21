import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/igdb_source.dart';
import 'package:library_app/data/lookup/igdb_token_store.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/storage/json_file.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/series.dart';

void main() {
  late Directory dir;
  late List<http.Request> sent;
  late IgdbTokenStore tokens;
  var now = DateTime.utc(2026, 10, 15, 12);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('igdb');
    tokens = IgdbTokenStore(
      JsonFile(File('${dir.path}/igdb_token.json')),
      now: () => now,
    );
  });
  tearDown(() => dir.delete(recursive: true));

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final tlou = {
    'id': 1009,
    'name': 'The Last of Us',
    'first_release_date': 1371168000, // 2013-06-14
    'summary': 'Joel and Ellie cross a ruined United States.',
    'cover': {'id': 1, 'image_id': 'co1r7f'},
    'platforms': [
      {'name': 'PlayStation 3'},
      {'name': 'PC (Microsoft Windows)'},
    ],
    'involved_companies': [
      {
        'company': {'name': 'Naughty Dog'},
        'developer': true,
      },
      {
        'company': {'name': 'Sony'},
        'developer': false,
      },
    ],
    'genres': [
      {'name': 'Shooter'},
      {'name': 'Adventure'},
    ],
  };

  /// Twitch and IGDB from one handler: the token endpoint answers itself.
  IgdbSource source(
    Future<http.Response> Function(http.Request) games, {
    String clientId = 'cid',
    int tokenStatus = 200,
  }) {
    sent = [];
    return IgdbSource(
      MockClient((request) async {
        sent.add(request);
        if (request.url.host == 'id.twitch.tv') {
          return json(tokenStatus, {
            'access_token': 'tok${sent.length}',
            'expires_in': 5184000,
            'token_type': 'bearer',
          });
        }
        return games(request);
      }),
      clientId: clientId,
      clientSecret: 'secret',
      tokens: tokens,
    );
  }

  test('fetches a token once, caches it, and queries games with it', () async {
    final igdb = source((_) async => json(200, [tlou]));
    final hits = await igdb.search(
      'last of us',
      type: MediaType.games,
      limit: 5,
    );
    expect(sent.length, 2);
    final token = sent[0];
    expect(token.method, 'POST');
    expect(token.url.host, 'id.twitch.tv');
    expect(token.url.queryParameters, {
      'client_id': 'cid',
      'client_secret': 'secret',
      'grant_type': 'client_credentials',
    });
    final games = sent[1];
    expect(games.url.toString(), 'https://api.igdb.com/v4/games');
    expect(games.headers['Client-ID'], 'cid');
    expect(games.headers['Authorization'], 'Bearer tok1');
    expect(
      games.body,
      'search "last of us"; fields name,first_release_date,summary,'
      'cover.image_id,platforms.name,involved_companies.company.name,'
      'involved_companies.developer,genres.name; '
      'where version_parent = null; limit 5;',
    );

    final hit = hits.single;
    expect(hit.source, 'igdb:1009');
    expect(hit.released, const Released(2013, 6, 14));
    expect(hit.creator, 'Naughty Dog');
    expect(hit.platforms, ['PlayStation 3', 'PC']);
    expect(hit.tags, ['Shooter', 'Adventure']);
    expect(
      hit.coverUrl,
      'https://images.igdb.com/igdb/image/upload/t_cover_big/co1r7f.jpg',
    );
    expect(await igdb.details(hit), hit);

    // The token is on disk for the next run.
    expect(await tokens.valid(), 'tok1');
    await source((_) async => json(200, [])).search('x', type: MediaType.games);
    expect(sent.single.url.host, 'api.igdb.com');
  });

  test('a token near its expiry is not reused', () async {
    await tokens.save('old', expiresIn: const Duration(hours: 20));
    expect(await tokens.valid(), isNull);
    await tokens.save('fresh', expiresIn: const Duration(days: 60));
    expect(await tokens.valid(), 'fresh');
    now = now.add(const Duration(days: 59, hours: 1));
    expect(await tokens.valid(), isNull);
  });

  test('a refused token is fetched again once', () async {
    await tokens.save('stale', expiresIn: const Duration(days: 30));
    var calls = 0;
    final igdb = source((request) async {
      calls++;
      return request.headers['Authorization'] == 'Bearer stale'
          ? json(401, {'message': 'Authorization Failure'})
          : json(200, [tlou]);
    });
    final hits = await igdb.search('x', type: MediaType.games);
    expect(hits.single.title, 'The Last of Us');
    expect(calls, 2);
    expect(sent.map((r) => r.url.host).toList(), [
      'api.igdb.com',
      'id.twitch.tv',
      'api.igdb.com',
    ]);
    expect(await tokens.valid(), isNot('stale'));

    // Refused twice is a failure, not a loop.
    expect(
      source((_) async => json(401, {})).search('x', type: MediaType.games),
      throwsA(isA<LookupException>().having((e) => e.status, 'status', 401)),
    );
  });

  test('match wants the same name and prefers the year', () async {
    final igdb = source(
      (_) async => json(200, [
        {...tlou, 'id': 2, 'name': 'The Last of Us Part II'},
        {...tlou, 'id': 3, 'first_release_date': 1662508800}, // 2022 remake
        tlou,
      ]),
    );
    expect(
      (await igdb.match(
        'The Last of Us',
        type: MediaType.games,
        year: 2013,
      ))!.source,
      'igdb:1009',
    );
    expect(
      (await igdb.match(
        'the last of us',
        type: MediaType.games,
        year: 2022,
      ))!.source,
      'igdb:3',
    );
    expect(
      (await igdb.match('The Last of Us', type: MediaType.games))!.source,
      'igdb:3',
    );
    expect(await igdb.match('Uncharted', type: MediaType.games), isNull);
  });

  test('coverUrl asks for one game by id', () async {
    final igdb = source(
      (_) async => json(200, [
        {
          'id': 1009,
          'cover': {'image_id': 'co1r7f'},
        },
      ]),
    );
    expect(
      await igdb.coverUrl('igdb:1009', type: MediaType.games),
      'https://images.igdb.com/igdb/image/upload/t_cover_big/co1r7f.jpg',
    );
    expect(sent.last.body, 'fields cover.image_id; where id = 1009; limit 1;');
    expect(
      await source((_) async => json(200, []))
          .coverUrl('igdb:1', type: MediaType.games),
      isNull,
    );
    expect(
      igdb.coverUrl('tmdb:movie:1', type: MediaType.games),
      throwsA(isA<LookupException>()),
    );
  });

  test('quotes in the query are escaped', () async {
    final igdb = source((_) async => json(200, []));
    await igdb.search('Marvel\'s "Spider-Man"', type: MediaType.games);
    expect(
      sent.last.body,
      startsWith(
        r'search "Marvel'
        "'"
        r's \"Spider-Man\""; fields',
      ),
    );
  });

  test('429, a bad body and no connection are failures', () async {
    Future<LookupFailure> failureOf(
      Future<http.Response> Function(http.Request) handler,
    ) async {
      try {
        await source(handler).search('x', type: MediaType.games);
      } on LookupException catch (e) {
        return e.failure;
      }
      fail('did not throw');
    }

    expect(
      await failureOf((_) async => json(429, {})),
      LookupFailure.rateLimited,
    );
    expect(
      await failureOf((_) async => json(200, {'not': 'a list'})),
      LookupFailure.other,
    );
    expect(
      await failureOf((_) => throw const SocketException('down')),
      LookupFailure.offline,
    );
  });

  test('without the client id nothing is asked', () async {
    final igdb = source((_) async => json(200, [tlou]), clientId: '');
    expect(igdb.isConfigured, isFalse);
    await expectLater(
      igdb.search('x', type: MediaType.games),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.notConfigured,
        ),
      ),
    );
    expect(sent, isEmpty);
  });

  group('collections', () {
    final bioshock = {
      'id': 20,
      'name': 'BioShock',
      'collections': [
        {
          'id': 7,
          'name': 'BioShock',
          'games': [
            {
              'id': 21,
              'name': 'BioShock 2',
              'first_release_date': 1265760000,
              'game_type': 0,
            },
            {
              'id': 20,
              'name': 'BioShock',
              'first_release_date': 1187654400,
              'game_type': 0,
            },
            {
              'id': 22,
              'name': 'BioShock Infinite',
              'first_release_date': 1364256000,
              'game_type': {'id': 0, 'type': 'Main Game'},
            },
            {
              'id': 23,
              'name': 'BioShock: The Collection',
              'first_release_date': 1473811200,
              'game_type': 3,
            },
            {
              'id': 24,
              'name': 'BioShock Remastered',
              'first_release_date': 1473811200,
              'game_type': 9,
            },
            {
              'id': 25,
              'name': 'BioShock Infinite: Complete Edition',
              'first_release_date': 1415577600,
              'version_parent': 22,
            },
            {'id': 26, 'name': 'BioShock 4', 'game_type': 0},
          ],
        },
      ],
    };

    final dkc = {
      'id': 1090,
      'name': 'Donkey Kong Country',
      'collections': [
        {
          'id': 242,
          'name': 'Donkey Kong',
          'games': [
            {'id': 1, 'name': 'Donkey Kong', 'game_type': 0},
          ],
        },
        {
          'id': 6066,
          'name': 'Donkey Kong Country',
          'games': [
            {
              'id': 1090,
              'name': 'Donkey Kong Country',
              'first_release_date': 785116800,
              'game_type': 0,
            },
            {
              'id': 1091,
              'name': "Donkey Kong Country 2: Diddy's Kong Quest",
              'first_release_date': 816912000,
              'game_type': 0,
            },
          ],
        },
      ],
    };

    test('details and seriesParts read the collection: main games and remakes, in date order', () async {
      final igdb = source((_) async => json(200, [bioshock]));
      final full = await igdb.details(
        const LookupMatch(
          type: MediaType.games,
          title: 'BioShock',
          source: 'igdb:20',
        ),
      );
      expect(full.series, const Series(name: 'BioShock', number: 1));
      expect(
        sent.last.body,
        'fields name,collections.name,collections.games.name,'
        'collections.games.first_release_date,collections.games.game_type,'
        'collections.games.version_parent; where id = 20; limit 1;',
      );
      final parts = await igdb.seriesParts('igdb:20');
      expect(parts!.parts.map((p) => (p.number, p.title, p.year, p.source)), [
        (1, 'BioShock', 2007, 'igdb:20'),
        (2, 'BioShock 2', 2010, 'igdb:21'),
        (3, 'BioShock Infinite', 2013, 'igdb:22'),
        (4, 'BioShock 4', null, 'igdb:26'),
      ]);
    });

    test(
      'a game in several collections takes the one its title names',
      () async {
        final igdb = source((_) async => json(200, [dkc]));
        final full = await igdb.details(
          const LookupMatch(
            type: MediaType.games,
            title: 'Donkey Kong Country',
            source: 'igdb:1090',
          ),
        );
        expect(
          full.series,
          const Series(name: 'Donkey Kong Country', number: 1),
        );
        final parts = await igdb.seriesParts('igdb:1090');
        expect(parts!.parts.map((p) => p.title), [
          'Donkey Kong Country',
          "Donkey Kong Country 2: Diddy's Kong Quest",
        ]);
        // A title that names none of them takes the first listed.
        final other = source(
          (_) async => json(200, [
            {...dkc, 'name': 'Diddy Kong Racing'},
          ]),
        );
        expect((await other.seriesParts('igdb:1090'))!.name, 'Donkey Kong');
      },
    );

    test('a game in no collection has none', () async {
      final igdb = source((_) async => json(200, [tlou]));
      expect(await igdb.seriesParts('igdb:1009'), isNull);
      final match = const LookupMatch(
        type: MediaType.games,
        title: 'x',
        source: 'igdb:1009',
      );
      expect(await igdb.details(match), match);
    });
  });
}
