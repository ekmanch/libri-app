import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/anilist_source.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';

void main() {
  late List<http.Request> sent;

  AniListSource source(Future<http.Response> Function(http.Request) handler) {
    sent = [];
    return AniListSource(
      MockClient((request) {
        sent.add(request);
        return handler(request);
      }),
    );
  }

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final akira = {
    'id': 47,
    'title': {'romaji': 'AKIRA', 'english': 'Akira'},
    'startDate': {'year': 1988, 'month': 7, 'day': 16},
    'description': 'A biker gang<br>and Neo-Tokyo. <i>Based on</i> the manga.',
    'coverImage': {
      'large': 'https://img/akira-large.jpg',
      'extraLarge': 'https://img/akira-xl.jpg',
    },
    'studios': {
      'nodes': [
        {'name': 'TMS Entertainment'},
      ],
    },
    'genres': ['Action', 'Sci-Fi'],
  };

  test('posts the search query and parses the media', () async {
    final anilist = source(
      (_) async => json(200, {
        'data': {
          'Page': {
            'media': [
              akira,
              {
                'id': 1,
                'title': {'romaji': 'Nameless'},
                'startDate': {'year': null},
                'coverImage': {},
                'studios': {'nodes': []},
                'genres': [],
              },
            ],
          },
        },
      }),
    );
    final hits = await anilist.search('akira', type: MediaType.anime, limit: 5);
    final request = sent.single;
    expect(request.method, 'POST');
    expect(request.url.host, 'graphql.anilist.co');
    final body = jsonDecode(request.body) as Map<String, Object?>;
    expect(body['variables'], {'search': 'akira', 'perPage': 5});
    expect(body['query'], contains('type: ANIME'));

    expect(hits.length, 2);
    expect(hits[0].title, 'Akira');
    expect(hits[0].source, 'anilist:47');
    expect(hits[0].released, const Released(1988, 7, 16));
    expect(hits[0].creator, 'TMS Entertainment');
    expect(
      hits[0].description,
      'A biker gang\nand Neo-Tokyo. Based on the manga.',
    );
    expect(hits[0].tags, ['Action', 'Sci-Fi']);
    expect(hits[0].coverUrl, 'https://img/akira-large.jpg');
    expect(hits[1].title, 'Nameless');
    expect(hits[1].released, isNull);
    expect(hits[1].creator, isNull);
    expect(hits[1].coverUrl, isNull);
    // Everything came with the search.
    expect(await anilist.details(hits[0]), hits[0]);
    expect(sent.length, 1);
  });

  test('the country of origin gives the language', () async {
    final anilist = source(
      (_) async => json(200, {
        'data': {
          'Page': {
            'media': [
              {...akira, 'countryOfOrigin': 'JP'},
              {...akira, 'id': 2, 'countryOfOrigin': 'KR'},
              {...akira, 'id': 3, 'countryOfOrigin': 'US'},
              {...akira, 'id': 4},
            ],
          },
        },
      }),
    );
    final hits = await anilist.search('akira', type: MediaType.anime);
    final body = jsonDecode(sent.single.body) as Map<String, Object?>;
    expect(body['query'], contains('countryOfOrigin'));
    expect(hits.map((h) => h.language), ['ja', 'ko', null, null]);
  });

  test('match wants the same title and prefers the year', () async {
    final anilist = source(
      (_) async => json(200, {
        'data': {
          'Page': {
            'media': [akira],
          },
        },
      }),
    );
    final hit = await anilist.match('AKIRA', type: MediaType.anime, year: 1988);
    expect((jsonDecode(sent.single.body) as Map)['variables'], {
      'search': 'AKIRA',
      'perPage': 5,
    });
    expect(hit!.source, 'anilist:47');
    // A year off still counts; a different title never does.
    expect(
      (await anilist.match('Akira', type: MediaType.anime, year: 1989))!.source,
      'anilist:47',
    );
    expect(await anilist.match('Paprika', type: MediaType.anime), isNull);
    expect(
      await anilist.match('Paprika', type: MediaType.anime, year: 1988),
      isNull,
    );
  });

  test('coverUrl asks by id for the large cover', () async {
    final anilist = source(
      (_) async => json(200, {
        'data': {'Media': akira},
      }),
    );
    expect(
      await anilist.coverUrl('anilist:47', type: MediaType.anime),
      'https://img/akira-xl.jpg',
    );
    expect((jsonDecode(sent.single.body) as Map)['variables'], {'id': 47});
    expect(
      await source(
        (_) async => json(404, {
          'data': {'Media': null},
          'errors': [
            {'message': 'Not Found.'},
          ],
        }),
      ).coverUrl('anilist:9', type: MediaType.anime),
      isNull,
    );
    expect(
      anilist.coverUrl('tmdb:movie:1', type: MediaType.anime),
      throwsA(isA<LookupException>()),
    );
  });

  test('GraphQL errors, 429 and a bad body are failures', () async {
    Future<LookupFailure> failureOf(Object body, [int status = 200]) async {
      try {
        await source((_) async => json(status, body))
            .search('x', type: MediaType.anime);
      } on LookupException catch (e) {
        return e.failure;
      }
      fail('did not throw');
    }

    expect(
      await failureOf({
        'errors': [
          {'message': 'Too Many Requests.'},
        ],
      }, 429),
      LookupFailure.rateLimited,
    );
    expect(
      await failureOf({
        'data': null,
        'errors': [
          {'message': 'Validation'},
        ],
      }),
      LookupFailure.other,
    );
    expect(await failureOf([1, 2]), LookupFailure.other);
  });
}
