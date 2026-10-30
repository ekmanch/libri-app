import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/deezer_source.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/follow_kind.dart';

void main() {
  late List<http.Request> sent;

  DeezerSource source(Future<http.Response> Function(http.Request) handler) {
    sent = [];
    return DeezerSource(
      MockClient((request) {
        sent.add(request);
        return handler(request);
      }),
    );
  }

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  final dirtAlbum = {
    'id': 91627,
    'title': 'Dirt',
    'cover_medium': 'https://cdn/dirt-250.jpg',
    'cover_big': 'https://cdn/dirt-500.jpg',
    'nb_tracks': 13,
    'artist': {'id': 1, 'name': 'Alice in Chains'},
  };
  final roosterTrack = {
    'id': 1016551,
    'title': 'Rooster',
    'artist': {'id': 1, 'name': 'Alice in Chains'},
    'album': {
      'id': 91627,
      'title': 'Dirt',
      'cover_medium': 'https://cdn/dirt-250.jpg',
    },
  };

  test('search asks albums and tracks and lists albums first', () async {
    final deezer = source((request) async {
      switch (request.url.path) {
        case '/search/album':
          expect(request.url.queryParameters, {'q': 'dirt', 'limit': '3'});
          return json({
            'data': [dirtAlbum],
          });
        case '/search/track':
          return json({
            'data': [
              roosterTrack,
              {'id': 2, 'title': 'No album'},
            ],
          });
      }
      fail('unexpected ${request.url}');
    });
    final hits = await deezer.search('dirt', type: MediaType.music, limit: 5);
    expect(sent.length, 2);
    expect(hits.length, 3);
    expect(hits[0].source, 'deezer:album:91627');
    expect(hits[0].creator, 'Alice in Chains');
    expect(hits[0].album, isNull);
    expect(hits[0].coverUrl, 'https://cdn/dirt-250.jpg');
    expect(hits[0].released, isNull);
    expect(hits[1].source, 'deezer:track:1016551');
    expect(hits[1].album, 'Dirt');
    expect(hits[1].albumSource, 'deezer:album:91627');
    expect(hits[1].coverUrl, 'https://cdn/dirt-250.jpg');
    expect(hits[2].albumSource, isNull);
    expect(hits[2].creator, isNull);
  });

  test('details fetch the album for its date, genres and cover', () async {
    final deezer = source((request) async {
      expect(request.url.path, '/album/91627');
      return json({
        ...dirtAlbum,
        'release_date': '1992-09-29',
        'genres': {
          'data': [
            {'name': 'Rock'},
            {'name': 'Metal'},
          ],
        },
      });
    });
    const plain = LookupMatch(
      type: MediaType.music,
      title: 'Dirt',
      source: 'deezer:album:91627',
    );
    final full = await deezer.details(plain);
    expect(full.released, const Released(1992, 9, 29));
    expect(full.tags, ['Rock', 'Metal']);
    expect(full.coverUrl, 'https://cdn/dirt-250.jpg');

    final noDate = await source(
      (_) async => json({...dirtAlbum, 'release_date': '0000-00-00'}),
    ).details(plain);
    expect(noDate.released, isNull);
  });

  test('a track goes through its album for details and cover', () async {
    final deezer = source((request) async {
      if (request.url.path == '/track/1016551') {
        return json({...roosterTrack, 'release_date': '1992-09-29'});
      }
      expect(request.url.path, '/album/91627');
      return json({...dirtAlbum, 'release_date': '1992-09-29'});
    });
    expect(
      await deezer.coverUrl('deezer:track:1016551', type: MediaType.music),
      'https://cdn/dirt-500.jpg',
    );
    expect(sent.map((r) => r.url.path).toList(), [
      '/track/1016551',
      '/album/91627',
    ]);
    expect(
      await deezer.coverUrl('deezer:album:91627', type: MediaType.music),
      'https://cdn/dirt-500.jpg',
    );
    expect(
      deezer.coverUrl('deezer:artist:1', type: MediaType.music),
      throwsA(isA<LookupException>()),
    );
  });

  test(
    'match uses the artist and album syntax and wants both to agree',
    () async {
      final deezer = source(
        (_) async => json({
          'data': [
            {...dirtAlbum, 'id': 5, 'title': 'Dirt (Live)'},
            {
              ...dirtAlbum,
              'id': 6,
              'artist': {'name': 'Someone Else'},
            },
            dirtAlbum,
          ],
        }),
      );
      final hit = await deezer.match(
        'Dirt',
        type: MediaType.music,
        creator: 'Alice In Chains',
      );
      expect(
        sent.single.url.queryParameters['q'],
        'artist:"Alice In Chains" album:"Dirt"',
      );
      expect(hit!.source, 'deezer:album:91627');
      final noArtist = await deezer.match('dirt', type: MediaType.music);
      expect(sent.last.url.queryParameters['q'], 'album:"dirt"');
      expect(noArtist!.source, 'deezer:album:6');
      // Only a remaster on offer: it is still the album.
      final remaster = await source(
        (_) async => json({
          'data': [
            {...dirtAlbum, 'id': 7, 'title': 'Dirt (2022 Remaster)'},
          ],
        }),
      ).match('Dirt', type: MediaType.music, creator: 'Alice in Chains');
      expect(remaster!.source, 'deezer:album:7');
      expect(await deezer.match('Facelift', type: MediaType.music), isNull);
    },
  );

  test('albumTracks lists the album in order with track ids', () async {
    final deezer = source((request) async {
      expect(request.url.path, '/album/91627/tracks');
      expect(request.url.queryParameters['limit'], '200');
      return json({
        'data': [
          {'id': 1016550, 'title': 'Them Bones'},
          {'id': 1016551, 'title': 'Rooster'},
          {'title': 'no id'},
        ],
        'total': 2,
      });
    });
    expect(await deezer.albumTracks('deezer:album:91627'), [
      (id: 'deezer:track:1016550', title: 'Them Bones'),
      (id: 'deezer:track:1016551', title: 'Rooster'),
    ]);
    expect(
      deezer.albumTracks('deezer:track:1'),
      throwsA(isA<LookupException>()),
    );
  });

  test(
    'artistPhotoUrl wants the exact name and skips Various Artists',
    () async {
      final deezer = source(
        (_) async => json({
          'data': [
            {
              'id': 2,
              'name': 'Alice in Chains Tribute',
              'picture_big': 'https://cdn/t.jpg',
            },
            {
              'id': 1,
              'name': 'Alice In Chains',
              'picture_big': 'https://cdn/aic-500.jpg',
            },
          ],
        }),
      );
      expect(
        await deezer.artistPhotoUrl('Alice in Chains'),
        'https://cdn/aic-500.jpg',
      );
      expect(sent.single.url.path, '/search/artist');
      expect(await deezer.artistPhotoUrl('Nirvana'), isNull);
      expect(await deezer.artistPhotoUrl('Various Artists'), isNull);
      expect(sent.length, 2);
    },
  );

  test(
    'error objects at status 200 are failures, "no data" is nothing',
    () async {
      Future<LookupFailure?> failureOf(Object body) async {
        try {
          await source((_) async => json(body))
              .search('x', type: MediaType.music);
        } on LookupException catch (e) {
          return e.failure;
        }
        return null;
      }

      expect(
        await failureOf({
          'error': {
            'type': 'Exception',
            'message': 'Quota limit exceeded',
            'code': 4,
          },
        }),
        LookupFailure.rateLimited,
      );
      expect(
        await failureOf({
          'error': {
            'type': 'OAuthException',
            'message': 'Invalid',
            'code': 300,
          },
        }),
        LookupFailure.other,
      );
      expect(
        await failureOf({
          'error': {'type': 'DataException', 'message': 'no data', 'code': 800},
        }),
        isNull,
      );
      expect(
        await source(
          (_) async => json({
            'error': {
              'type': 'DataException',
              'message': 'no data',
              'code': 800,
            },
          }),
        ).coverUrl('deezer:album:1', type: MediaType.music),
        isNull,
      );
    },
  );

  test('releaseDate: the album\'s date, also for a track', () async {
    final deezer = source((request) async {
      if (request.url.path == '/track/1016551') {
        return json({...roosterTrack, 'release_date': '1992-09-29'});
      }
      return json({...dirtAlbum, 'release_date': '2027-02-05'});
    });
    expect(
      await deezer.releaseDate('deezer:album:91627'),
      const Released(2027, 2, 5),
    );
    expect(
      await deezer.releaseDate('deezer:track:1016551'),
      const Released(2027, 2, 5),
    );
  });

  group('followed artists', () {
    test('finds the artist by exact name and lists the albums ahead', () async {
      final deezer = source((request) async {
        switch (request.url.path) {
          case '/search/artist':
            expect(request.url.queryParameters['q'], 'Alice in Chains');
            return json({
              'data': [
                {'id': 9, 'name': 'Alice in Chains Tribute'},
                {'id': 1, 'name': 'Alice in Chains'},
              ],
            });
          case '/artist/1':
            return json({'id': 1, 'name': 'Alice in Chains'});
          case '/artist/1/albums':
            return json({
              'data': [
                {
                  'id': 300,
                  'title': 'Rainier Fog II',
                  'release_date': '2026-11-20',
                  'record_type': 'album',
                  'cover_medium': 'https://cdn/rf2.jpg',
                },
                {
                  'id': 301,
                  'title': 'A Single',
                  'release_date': '2026-11-01',
                  'record_type': 'single',
                },
                {
                  'id': 302,
                  'title': 'An EP',
                  'release_date': '2026-10-15',
                  'record_type': 'ep',
                },
                {
                  'id': 91627,
                  'title': 'Dirt',
                  'release_date': '1992-09-29',
                  'record_type': 'album',
                },
              ],
            });
        }
        return json({
          'error': {'code': 800, 'message': 'no data'},
        });
      });
      expect(await deezer.findCreator(FollowKind.artists, 'Alice in Chains'), (
        providerId: 'deezer:artist:1',
        inactive: null,
      ));
      final albums = await deezer.creatorReleases(
        'deezer:artist:1',
        FollowKind.artists,
        today: DateTime(2026, 10, 30),
      );
      expect(albums.map((m) => m.title), ['An EP', 'Rainier Fog II']);
      expect(albums.last.source, 'deezer:album:300');
      expect(albums.last.creator, 'Alice in Chains');
      expect(albums.last.released, const Released(2026, 11, 20));
    });
  });
}
