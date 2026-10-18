import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/tmdb_source.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';

void main() {
  late List<http.Request> sent;

  TmdbSource source(
    Future<http.Response> Function(http.Request) handler, {
    String token = 'eyJ.tmdb',
  }) {
    sent = [];
    return TmdbSource(
      MockClient((request) {
        sent.add(request);
        return handler(request);
      }),
      token: token,
      timeout: const Duration(milliseconds: 200),
    );
  }

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final mummySearch = {
    'results': [
      {
        'id': 564,
        'title': 'The Mummy',
        'release_date': '1999-04-16',
        'overview': 'An American serving in the French Foreign Legion…',
        'poster_path': '/mummy.jpg',
        'genre_ids': [12, 14],
      },
      {
        'id': 282035,
        'title': 'The Mummy',
        'release_date': '2017-06-06',
        'overview': 'Though safely entombed…',
        'poster_path': null,
      },
      {'id': 9, 'title': 'Untitled', 'release_date': ''},
    ],
  };

  test('searches movies with the token and parses the rows', () async {
    final tmdb = source((_) async => json(200, mummySearch));
    final hits = await tmdb.search('The Mummy', type: MediaType.movies);
    final request = sent.single;
    expect(request.url.host, 'api.themoviedb.org');
    expect(request.url.path, '/3/search/movie');
    expect(request.url.queryParameters, {
      'query': 'The Mummy',
      'include_adult': 'false',
    });
    expect(request.headers['Authorization'], 'Bearer eyJ.tmdb');
    expect(request.headers['User-Agent'], 'Libri');

    expect(hits.length, 3);
    expect(hits[0].source, 'tmdb:movie:564');
    expect(hits[0].released, const Released(1999, 4, 16));
    expect(hits[0].coverUrl, 'https://image.tmdb.org/t/p/w185/mummy.jpg');
    expect(hits[0].creator, isNull);
    expect(hits[0].tags, isEmpty);
    expect(hits[1].coverUrl, isNull);
    expect(hits[2].released, isNull);
    expect(hits[2].description, '');
  });

  test('searches shows by name and first air date', () async {
    final tmdb = source(
      (_) async => json(200, {
        'results': [
          {
            'id': 100088,
            'name': 'The Last of Us',
            'first_air_date': '2023-01-15',
          },
        ],
      }),
    );
    final hits = await tmdb.search(
      'last of us',
      type: MediaType.shows,
      limit: 1,
    );
    expect(sent.single.url.path, '/3/search/tv');
    expect(hits.single.source, 'tmdb:tv:100088');
    expect(hits.single.title, 'The Last of Us');
    expect(hits.single.released, const Released(2023, 1, 15));
  });

  test('details add the director, the genres and the full date', () async {
    final tmdb = source(
      (_) async => json(200, {
        'id': 564,
        'title': 'The Mummy',
        'release_date': '1999-04-16',
        'overview': 'Full overview.',
        'poster_path': '/mummy.jpg',
        'genres': [
          {'id': 12, 'name': 'Adventure'},
          {'id': 14, 'name': 'Fantasy'},
        ],
        'credits': {
          'cast': [
            {'order': 0, 'name': 'Brendan Fraser'},
            {'order': 1, 'name': 'Rachel Weisz'},
            {'order': 2, 'name': 'John Hannah'},
            {'order': 3, 'name': 'Arnold Vosloo'},
          ],
          'crew': [
            {'job': 'Producer', 'name': 'Someone'},
            {'job': 'Director', 'name': 'Stephen Sommers'},
          ],
        },
      }),
    );
    const plain = LookupMatch(
      type: MediaType.movies,
      title: 'The Mummy',
      source: 'tmdb:movie:564',
    );
    final full = await tmdb.details(plain);
    expect(sent.single.url.path, '/3/movie/564');
    expect(sent.single.url.queryParameters, {'append_to_response': 'credits'});
    expect(full.creator, 'Stephen Sommers');
    // The top three billed, in order (A8 suggests them as actor tags).
    expect(full.cast, ['Brendan Fraser', 'Rachel Weisz', 'John Hannah']);
    expect(full.tags, ['Adventure', 'Fantasy']);
    expect(full.description, 'Full overview.');
    expect(full.source, plain.source);
  });

  test('show details use the creators', () async {
    final tmdb = source(
      (_) async => json(200, {
        'id': 100088,
        'name': 'The Last of Us',
        'first_air_date': '2023-01-15',
        'created_by': [
          {'name': 'Craig Mazin'},
          {'name': 'Neil Druckmann'},
        ],
        'genres': [
          {'name': 'Drama'},
        ],
        'credits': {
          'cast': [
            {'name': 'Pedro Pascal'},
            {'name': 'Bella Ramsey'},
          ],
        },
      }),
    );
    final full = await tmdb.details(
      const LookupMatch(
        type: MediaType.shows,
        title: 'The Last of Us',
        source: 'tmdb:tv:100088',
      ),
    );
    expect(sent.single.url.path, '/3/tv/100088');
    // Shows ask for the credits too, for the cast.
    expect(sent.single.url.queryParameters, {'append_to_response': 'credits'});
    expect(full.creator, 'Craig Mazin, Neil Druckmann');
    expect(full.cast, ['Pedro Pascal', 'Bella Ramsey']);
    expect(full.released, const Released(2023, 1, 15));
  });

  final lastOfUsSeasons = {
    'id': 100088,
    'name': 'The Last of Us',
    'seasons': [
      {'season_number': 0, 'air_date': '2023-01-09', 'name': 'Specials'},
      {'season_number': 1, 'air_date': '2023-01-15'},
      {'season_number': 2, 'air_date': '2025-04-13'},
      {'season_number': 3, 'air_date': null},
      {'season_number': 4, 'air_date': ''},
    ],
  };

  test('show details carry the dated seasons, specials left out', () async {
    final tmdb = source((_) async => json(200, lastOfUsSeasons));
    final full = await tmdb.details(
      const LookupMatch(
        type: MediaType.shows,
        title: 'The Last of Us',
        source: 'tmdb:tv:100088',
      ),
    );
    expect(full.seasons, const [
      Season(season: 1, released: Released(2023, 1, 15)),
      Season(season: 2, released: Released(2025, 4, 13)),
    ]);
  });

  test('seasons asks the show alone; a movie has none', () async {
    final tmdb = source((_) async => json(200, lastOfUsSeasons));
    final seasons = await tmdb.seasons('tmdb:tv:100088');
    expect(sent.single.url.path, '/3/tv/100088');
    expect(sent.single.url.queryParameters, isEmpty);
    expect([for (final s in seasons!) s.season], [1, 2]);
    expect(await tmdb.seasons('tmdb:movie:564'), isNull);
  });

  test('every season with a date is listable, announced ones too', () {
    expect(
      Season.listable(const [
        Season(season: 2, released: Released(2025)),
        Season(season: 1, released: Released(2024), status: EntryStatus.done),
        Season(season: 3, released: Released(2027)),
        Season(season: 4),
        Season(season: 0, released: Released(2023)),
      ]),
      const [
        Season(season: 1, released: Released(2024)),
        Season(season: 2, released: Released(2025)),
        Season(season: 3, released: Released(2027)),
      ],
    );
  });

  test('match wants the same title and prefers the year', () async {
    final tmdb = source((_) async => json(200, mummySearch));
    final byYear = await tmdb.match(
      'The Mummy',
      type: MediaType.movies,
      year: 1999,
    );
    expect(
      sent.single.url.queryParameters.containsKey('primary_release_year'),
      isFalse,
    );
    expect(byYear!.source, 'tmdb:movie:564');
    final remake = await tmdb.match(
      'mummy',
      type: MediaType.movies,
      year: 2018,
    );
    expect(remake!.source, 'tmdb:movie:282035');
    expect(
      await tmdb.match('The Mummy', type: MediaType.movies, year: 1950),
      isNull,
    );
    expect(await tmdb.match('Something Else', type: MediaType.movies), isNull);
    expect(
      (await tmdb.match('The Mummy', type: MediaType.movies))!.source,
      'tmdb:movie:564',
    );
  });

  test('maps 429, other statuses and no connection', () async {
    Future<LookupFailure> failureOf(
      Future<http.Response> Function(http.Request) handler,
    ) async {
      try {
        await source(handler).search('x', type: MediaType.movies);
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
      await failureOf(
        (_) async => json(401, {'status_message': 'Invalid API key'}),
      ),
      LookupFailure.other,
    );
    expect(
      await failureOf((_) => throw const SocketException('down')),
      LookupFailure.offline,
    );
    expect(
      await failureOf((_) async => http.Response('<html>', 200)),
      LookupFailure.other,
    );
  });

  test('without a token nothing is asked and the failure says so', () async {
    final tmdb = source((_) async => json(200, mummySearch), token: '');
    expect(tmdb.isConfigured, isFalse);
    await expectLater(
      tmdb.search('x', type: MediaType.movies),
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
}
