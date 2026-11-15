import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/deezer_source.dart';
import 'package:library_app/data/lookup/itunes_books.dart';
import 'package:library_app/data/lookup/itunes_music.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/music_lookup.dart';
import 'package:library_app/data/lookup/open_library_source.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';

void main() {
  late List<http.Request> sent;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'text/javascript; charset=utf-8'},
  );

  http.Response results(List<Object> items) =>
      json(200, {'resultCount': items.length, 'results': items});

  ITunesBooks books(Future<http.Response> Function(http.Request) handler) {
    sent = [];
    return ITunesBooks(
      MockClient((request) {
        sent.add(request);
        return handler(request);
      }),
      minGap: Duration.zero,
    );
  }

  ITunesMusicSource apple(
    Future<http.Response> Function(http.Request) handler,
  ) => ITunesMusicSource(books(handler));

  const artwork =
      'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/aa/bb/cc/'
      'cover.jpg/100x100bb.jpg';

  Map<String, Object> album(int id, String name, {String artist = 'Kent'}) => {
    'wrapperType': 'collection',
    'collectionType': 'Album',
    'collectionId': id,
    'collectionName': name,
    'artistName': artist,
    'artworkUrl100': artwork,
    'releaseDate': '2002-04-15T07:00:00Z',
    'primaryGenreName': 'Rock',
  };

  Map<String, Object> song(
    int id,
    String name, {
    int disc = 1,
    int track = 1,
    int albumId = 10,
  }) => {
    'wrapperType': 'track',
    'kind': 'song',
    'trackId': id,
    'trackName': name,
    'artistName': 'Kent',
    'collectionId': albumId,
    'collectionName': 'Vapen & ammunition',
    'artworkUrl100': artwork,
    'releaseDate': '2002-04-15T07:00:00Z',
    'discNumber': disc,
    'trackNumber': track,
    'primaryGenreName': 'Rock',
  };

  group('ids', () {
    test('an album or a track id is Apple Music\'s; a plain itunes id is a '
        'book\'s and stays Open Library\'s', () {
      final client = MockClient((_) async => json(200, {}));
      final api = ITunesBooks(client, minGap: Duration.zero);
      final music = ITunesMusicSource(api);
      final openLibrary = OpenLibrarySource(client, apple: api);
      // Open Library comes first in the list, as in the app.
      final service = LookupService([openLibrary, DeezerSource(client), music]);

      expect(ITunesMusicSource.parse('itunes:album:1440650711'), (
        'album',
        '1440650711',
      ));
      expect(ITunesMusicSource.parse('itunes:track:7'), ('track', '7'));
      expect(ITunesMusicSource.parse('itunes:6756269989'), isNull);
      expect(ITunesMusicSource.parse('itunes:artist:7'), isNull);
      expect(ITunesMusicSource.parse('itunes:album:x'), isNull);
      expect(ITunesMusicSource.parse('deezer:album:7'), isNull);

      expect(ITunesBooks.isBook('itunes:6756269989'), isTrue);
      expect(ITunesBooks.isBook('itunes:album:7'), isFalse);
      expect(ITunesBooks.isBook('itunes:track:7'), isFalse);

      expect(service.sourceOf('itunes:album:7'), music);
      expect(service.sourceOf('itunes:track:7'), music);
      expect(service.sourceOf('itunes:6756269989'), openLibrary);
      expect(service.sourceOf('deezer:album:7'), isA<DeezerSource>());
    });

    test('it serves no type, so no search, match or cover matcher asks it', () {
      final music = apple((_) async => json(200, {}));
      final service = LookupService([music]);
      expect(service.sourcesFor(MediaType.music), isEmpty);
      expect(music.search('Kent', type: MediaType.music), completion(isEmpty));
      expect(
        music.match('Vapen & ammunition', type: MediaType.music),
        completion(isNull),
      );
      expect(sent, isEmpty);
    });
  });

  test('a cover and a release date follow an album id, a song\'s its own '
      'record; the Swedish store is asked first, then the US one', () async {
    final music = apple((request) async {
      final q = request.url.queryParameters;
      if (q['country'] == 'SE') return results([]);
      return results([
        q['id'] == '10'
            ? album(10, 'Vapen & ammunition')
            : song(77, 'Dom andra'),
      ]);
    });

    expect(
      await music.coverUrl('itunes:album:10', type: MediaType.music),
      artwork.replaceFirst('100x100', '600x600'),
    );
    expect(sent.map((r) => r.url.queryParameters['country']), ['SE', 'US']);
    expect(sent.last.url.path, '/lookup');
    expect(sent.last.url.queryParameters['id'], '10');

    expect(
      await music.releaseDate('itunes:track:77'),
      Released.tryParse('2002-04-15'),
    );
    expect(
      await music.coverUrl('itunes:track:77', type: MediaType.music),
      isNotNull,
    );
  });

  test('an id of another shape is refused before any request', () async {
    final music = apple((_) async => results([]));
    await expectLater(
      music.coverUrl('itunes:6756269989', type: MediaType.music),
      throwsA(isA<LookupException>()),
    );
    await expectLater(
      music.albumTracks('itunes:track:7'),
      throwsA(isA<LookupException>()),
    );
    expect(sent, isEmpty);
  });

  test(
    'an album\'s tracks come in disc and track order, with track ids',
    () async {
      final music = apple(
        (_) async => results([
          album(10, 'Vapen & ammunition'),
          song(3, 'Pärlor', disc: 2, track: 1),
          song(2, 'Dom andra', track: 2),
          song(1, 'Sundance Kid', track: 1),
          {
            'wrapperType': 'track',
            'kind': 'music-video',
            'trackId': 9,
            'trackName': 'Video',
          },
        ]),
      );
      final tracks = await music.albumTracks('itunes:album:10');
      expect(tracks, [
        (id: 'itunes:track:1', title: 'Sundance Kid'),
        (id: 'itunes:track:2', title: 'Dom andra'),
        (id: 'itunes:track:3', title: 'Pärlor'),
      ]);
      expect(sent.single.url.queryParameters, {
        'id': '10',
        'entity': 'song',
        'country': 'SE',
        'limit': '200',
      });
    },
  );

  group('extended search', () {
    test('asks both stores once each and merges by id, the Swedish rows '
        'first', () async {
      final music = apple((request) async {
        final q = request.url.queryParameters;
        return results(
          q['country'] == 'SE'
              ? [album(10, 'Vapen & ammunition'), album(11, 'Isola')]
              : [album(11, 'Isola'), album(12, 'Kärleken väntar - Single')],
        );
      });
      final hits = await music.extendedSearch(' kent ', MusicScope.albums);
      expect(hits.map((h) => h.source), [
        'itunes:album:10',
        'itunes:album:11',
        'itunes:album:12',
      ]);
      expect(sent.length, 2);
      expect(sent.first.url.queryParameters, {
        'term': 'kent',
        'media': 'music',
        'entity': 'album',
        'country': 'SE',
        'limit': '50',
      });
      // A single is titled without Apple's note and labeled as one.
      expect(hits.last.title, 'Kärleken väntar');
      expect(hits.last.recordType, 'single');
      expect(hits.first.recordType, 'album');
      expect(hits.first.creator, 'Kent');
      expect(hits.first.released, Released.tryParse('2002-04-15'));
      expect(hits.first.tags, ['Rock']);
      expect(hits.first.coverUrl, artwork.replaceFirst('100x100', '200x200'));
    });

    test('songs carry their album and its id', () async {
      final music = apple((_) async => results([song(1, 'Sundance Kid')]));
      final hit = (await music.extendedSearch('kent', MusicScope.songs)).single;
      expect(hit.source, 'itunes:track:1');
      expect(hit.album, 'Vapen & ammunition');
      expect(hit.albumSource, 'itunes:album:10');
      expect(sent.first.url.queryParameters['entity'], 'song');
    });

    test(
      'one store failing leaves the other\'s rows; both failing throws',
      () async {
        final music = apple((request) async {
          return request.url.queryParameters['country'] == 'SE'
              ? json(500, {})
              : results([album(10, 'Isola')]);
        });
        expect(
          (await music.extendedSearch('kent', MusicScope.albums)).length,
          1,
        );

        final down = apple((_) async => json(500, {}));
        await expectLater(
          down.extendedSearch('kent', MusicScope.albums),
          throwsA(isA<LookupException>()),
        );
      },
    );

    test('a refusal stops at the first store', () async {
      final music = apple((_) async => json(403, {}));
      await expectLater(
        music.extendedSearch('kent', MusicScope.albums),
        throwsA(
          isA<LookupException>().having(
            (e) => e.failure,
            'failure',
            LookupFailure.rateLimited,
          ),
        ),
      );
      // The books client's own back-off asks the first store again; the
      // second store is never asked.
      expect(sent.map((r) => r.url.queryParameters['country']).toSet(), {'SE'});
    });
  });

  test('more covers: albums of that title by that artist, editions '
      'included, each with a cover', () async {
    final music = apple(
      (request) async => request.url.queryParameters['country'] == 'US'
          ? results([])
          : results([
              album(10, 'Isola'),
              album(11, 'Isola (Deluxe Edition)'),
              album(12, 'Isola', artist: 'Someone Else'),
              album(13, 'Hagnesta Hill'),
              {...album(14, 'Isola')}..remove('artworkUrl100'),
            ]),
    );
    final covers = await music.moreCovers('Isola', creator: 'Kent');
    expect(covers.map((c) => c.source), ['itunes:album:10', 'itunes:album:11']);
    expect(sent.first.url.queryParameters['term'], 'Isola Kent');
  });
}
