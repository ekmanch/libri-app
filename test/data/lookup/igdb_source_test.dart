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
import 'package:library_app/data/lookup/lookup_source.dart';
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
    // The token, the games named "last of us", then the search.
    expect(sent.length, 3);
    final token = sent[0];
    expect(token.method, 'POST');
    expect(token.url.host, 'id.twitch.tv');
    expect(token.url.queryParameters, {
      'client_id': 'cid',
      'client_secret': 'secret',
      'grant_type': 'client_credentials',
    });
    final games = sent[2];
    expect(games.url.toString(), 'https://api.igdb.com/v4/games');
    expect(games.headers['Client-ID'], 'cid');
    expect(games.headers['Authorization'], 'Bearer tok1');
    const fields =
        'fields name,first_release_date,summary,'
        'cover.image_id,platforms.name,involved_companies.company.name,'
        'involved_companies.developer,genres.name,'
        'language_supports.language.locale,language_supports.language_support_type,'
        'platforms.platform_type,total_rating_count,parent_game';
    expect(
      sent[1].body,
      '$fields; where version_parent = null & game_type != (13, 14) & '
      'name ~ "last of us"; sort total_rating_count desc; limit 5;',
    );
    expect(
      games.body,
      'search "last of us"; $fields; '
      'where version_parent = null & game_type != (13, 14); limit 5;',
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
    expect(sent.map((r) => r.url.host).toSet(), {'api.igdb.com'});
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
    expect(calls, 3);
    expect(sent.map((r) => r.url.host).toList(), [
      'api.igdb.com',
      'id.twitch.tv',
      'api.igdb.com',
      'api.igdb.com',
    ]);
    expect(await tokens.valid(), isNot('stale'));

    // Refused twice is a failure, not a loop.
    expect(
      source((_) async => json(401, {})).search('x', type: MediaType.games),
      throwsA(isA<LookupException>().having((e) => e.status, 'status', 401)),
    );
  });

  test(
    'the one audio language is the game\'s language; several say nothing',
    () async {
      Map<String, Object?> game(int id, List<(String, int)> supports) => {
        ...tlou,
        'id': id,
        'language_supports': [
          for (final (locale, type) in supports)
            {
              'language': {'locale': locale},
              'language_support_type': type,
            },
        ],
      };
      final igdb = source(
        (_) async => json(200, [
          game(1, [('ja-JP', 1), ('en-US', 2), ('en-US', 3)]),
          game(2, [('ja-JP', 1), ('en-US', 1)]),
          game(3, [('en-US', 2)]),
          game(4, []),
        ]),
      );
      final hits = await igdb.search('x', type: MediaType.games);
      expect(hits[0].language, 'ja-JP');
      expect(hits[1].language, isNull);
      expect(hits[2].language, isNull);
      expect(hits[3].language, isNull);
    },
  );

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

  test('games named exactly the query come first, a port before its '
      'arcade original, and fill half the list', () async {
    Map<String, Object?> game(
      int id,
      String name,
      List<(int, int)> platforms, {
      int? rating,
      int? parent,
    }) => {
      'id': id,
      'name': name,
      'platforms': [
        for (final (pid, type) in platforms) {'id': pid, 'platform_type': type},
      ],
      'total_rating_count': ?rating,
      'parent_game': ?parent,
    };
    final arcade = game(3186, 'Street Fighter II', [(52, 2)], rating: 376);
    final snes = game(
      321621,
      'Street Fighter II',
      [(19, 1)],
      rating: 12,
      parent: 3186,
    );
    final amiga = game(240001, 'Street Fighter II', [(16, 6)], parent: 3186);
    final lcd = game(198928, 'Street Fighter II', [(411, 5)], parent: 3186);
    final dos = game(321622, 'Street Fighter II', [(13, 4)], parent: 3186);
    final turbo = game(4238, 'Super Street Fighter II Turbo', [(52, 2)]);
    final champion = game(39496, 'Street Fighter II: Champion Edition', [
      (52, 2),
    ]);
    final igdb = source(
      (request) async => request.body.startsWith('search')
          ? json(200, [arcade, turbo, champion])
          : json(200, [arcade, snes, amiga, lcd, dos]),
    );
    final hits = await igdb.search(
      'Street Fighter II',
      type: MediaType.games,
      limit: 6,
    );
    expect(hits.map((h) => h.source), [
      'igdb:321621', // The most rated port, then its arcade original.
      'igdb:3186',
      'igdb:321622', // DOS before Amiga, a home computer.
      'igdb:4238', // Half the list is named hits; the search's own follow.
      'igdb:39496',
      'igdb:240001',
    ]);
  });

  test('platforms: IGDB\'s list, named as the app names them, kept on the '
      'phone for a month and kept when IGDB does not answer', () async {
    final file = JsonFile(File('${dir.path}/igdb_platforms.json'));
    var answer = (http.Request _) async => json(200, [
      {
        'id': 19,
        'name': 'Super Nintendo Entertainment System',
        'abbreviation': 'SNES',
        'alternative_name': 'SNES, Super Nintendo',
      },
      {
        'id': 6,
        'name': 'PC (Microsoft Windows)',
        'abbreviation': 'PC',
        'alternative_name': 'mswin',
      },
      {'id': 52, 'name': 'Arcade', 'abbreviation': 'Arcade'},
    ]);
    sent = [];
    IgdbSource build() {
      return IgdbSource(
        MockClient((request) async {
          sent.add(request);
          if (request.url.host == 'id.twitch.tv') {
            return json(200, {'access_token': 'tok', 'expires_in': 5184000});
          }
          return answer(request);
        }),
        clientId: 'cid',
        clientSecret: 'secret',
        tokens: tokens,
        platformsFile: file,
        now: () => now,
      );
    }

    // Records compare their lists by identity, so the names are joined.
    List<String> flat(List<GamePlatform> list) => [
      for (final p in list) '${p.id} ${p.name}: ${p.aka.join(' | ')}',
    ];
    final platforms = flat(await build().platforms());
    expect(platforms, [
      '52 Arcade: ',
      '6 PC: mswin | PC (Microsoft Windows)',
      '19 Super Nintendo: SNES | Super Nintendo Entertainment System',
    ]);
    expect(sent.last.url.path, '/v4/platforms');
    expect(
      sent.last.body,
      'fields name,abbreviation,alternative_name; limit 500;',
    );

    // Within a month a new run reads the file.
    sent.clear();
    expect(flat(await build().platforms()), platforms);
    expect(sent, isEmpty);

    // After a month IGDB is asked; not answering, the old list stands.
    now = now.add(const Duration(days: 31));
    answer = (_) async => json(500, {});
    expect(flat(await build().platforms()), platforms);
    expect(sent.where((r) => r.url.path == '/v4/platforms'), isNotEmpty);
    await file.delete();
    await expectLater(build().platforms(), throwsA(isA<LookupException>()));
  });

  test('a search on a platform asks once, narrowed, and dates each game by '
      'its release there', () async {
    final igdb = source(
      (_) async => json(200, [
        {
          ...tlou,
          'release_dates': [
            {'platform': 9, 'date': 1371168000, 'date_format': 0},
            {'platform': 48, 'date': 1406851200, 'date_format': 0},
            {'platform': 48, 'date': 1414713600, 'date_format': 0},
          ],
        },
        {
          ...tlou,
          'id': 2,
          'release_dates': [
            // A year-only date sits on December 31.
            {'platform': 48, 'date': 1419984000, 'date_format': 2},
          ],
        },
        {...tlou, 'id': 3},
      ]),
    );
    const ps4 = (id: 48, name: 'PlayStation 4', aka: <String>[]);
    final hits = await igdb.searchOnPlatform('last of us', ps4, limit: 5);
    expect(sent.where((r) => r.url.host == 'api.igdb.com'), hasLength(1));
    expect(
      sent.last.body,
      endsWith(
        ',release_dates.platform,release_dates.date,release_dates.date_format; '
        'where version_parent = null & game_type != (13, 14) & '
        'platforms = (48); limit 5;',
      ),
    );
    expect(hits.map((h) => h.released), [
      const Released(2014, 8, 1),
      const Released(2014),
      const Released(2013, 6, 14), // None there: its first release.
    ]);
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
        'fields name,parent_game,collections.name,collections.games.name,'
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

    test('a title that names a collection inside it takes that one; the '
        'entry\'s series name wins', () async {
      // Rise of the Tomb Raider is in "Tomb Raider: Survivor" and in
      // "Tomb Raider".
      final rise = {
        'id': 7323,
        'name': 'Rise of the Tomb Raider',
        'collections': [
          {
            'id': 1,
            'name': 'Tomb Raider: Survivor',
            'games': [
              {'id': 7323, 'name': 'Rise of the Tomb Raider'},
            ],
          },
          {
            'id': 2,
            'name': 'Tomb Raider',
            'games': [
              {'id': 912, 'name': 'Tomb Raider', 'first_release_date': 0},
              {
                'id': 7323,
                'name': 'Rise of the Tomb Raider',
                'first_release_date': 1447113600,
              },
            ],
          },
        ],
      };
      final igdb = source((_) async => json(200, [rise]));
      final full = await igdb.details(
        const LookupMatch(
          type: MediaType.games,
          title: 'Rise of the Tomb Raider',
          source: 'igdb:7323',
        ),
      );
      expect(full.series, const Series(name: 'Tomb Raider', number: 2));
      expect(
        (await igdb.seriesParts(
          'igdb:7323',
          name: 'Tomb Raider: Survivor',
        ))!.name,
        'Tomb Raider: Survivor',
      );
    });

    test('Street Fighter II counts its revisions and leaves out the '
        'spin-offs', () async {
      final sf2 = {
        'id': 3186,
        'name': 'Street Fighter II',
        'collections': [
          {
            'id': 2879,
            'name': 'Street Fighter II',
            'games': [
              {
                'id': 3186,
                'name': 'Street Fighter II',
                'first_release_date': 667958400,
                'game_type': 0,
              },
              {
                'id': 39496,
                'name': 'Street Fighter II: Champion Edition',
                'first_release_date': 702086400,
                'game_type': 10,
              },
              {
                'id': 45192,
                'name': 'Street Fighter II: Movie',
                'first_release_date': 817776000,
                'game_type': 0,
              },
              {
                'id': 21796,
                'name': 'Super Street Fighter II Turbo HD Remix',
                'first_release_date': 1227571200,
                'game_type': 9,
              },
              {
                'id': 231006,
                'name': 'Street Fighter II',
                'first_release_date': 700000000,
                'game_type': 11,
              },
            ],
          },
        ],
      };
      final igdb = source((_) async => json(200, [sf2]));
      expect((await igdb.seriesParts('igdb:3186'))!.parts.map((p) => p.title), [
        'Street Fighter II',
        'Street Fighter II: Champion Edition',
        'Super Street Fighter II Turbo HD Remix',
      ]);
      // Another collection keeps the plain rule.
      final other = source(
        (_) async => json(200, [
          {
            ...sf2,
            'collections': [
              {...(sf2['collections']! as List).single as Map, 'id': 1},
            ],
          },
        ]),
      );
      expect(
        (await other.seriesParts('igdb:3186'))!.parts.map((p) => p.title),
        ['Street Fighter II', 'Street Fighter II: Movie'],
      );
    });

    test('a port takes the number of the game it is a port of', () async {
      final port = {
        ...bioshock,
        'id': 30,
        'parent_game': 21,
        'name': 'BioShock 2',
      };
      final igdb = source((_) async => json(200, [port]));
      final full = await igdb.details(
        const LookupMatch(
          type: MediaType.games,
          title: 'BioShock 2',
          source: 'igdb:30',
        ),
      );
      expect(full.series, const Series(name: 'BioShock', number: 2));
    });

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
