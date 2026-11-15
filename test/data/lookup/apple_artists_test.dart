import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/covers/artist_photos.dart';
import 'package:library_app/data/lookup/apple_artists.dart';
import 'package:library_app/data/lookup/itunes_books.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/storage/json_file.dart';

const _page = 'https://music.apple.com/us/artist/massive-attack/1';
const _photo =
    'https://is1-ssl.mzstatic.com/image/thumb/AMCArtistImages126/v4/aa/bb/'
    'cc/file.png';
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

void main() {
  late List<http.Request> sent;
  late Directory dir;

  /// Apple as the tests need it: [artists] answers the name search,
  /// [albums] each artist's album list by id, [pages] each page's HTML.
  late List<Map<String, Object?>> artists;
  late Map<String, List<String>> albums;
  late Map<String, String?> pages;
  int? refuse;

  setUp(() {
    sent = [];
    dir = Directory.systemTemp.createTempSync('libri-apple-artists');
    artists = [
      {
        'wrapperType': 'artist',
        'artistName': 'Massive Attack',
        'artistId': 1,
        'artistLinkUrl': '$_page?uo=4',
      },
      {
        'wrapperType': 'artist',
        'artistName': 'Massive Attack Tribute',
        'artistId': 2,
        'artistLinkUrl': 'https://music.apple.com/us/artist/x/2?uo=4',
      },
    ];
    albums = {
      '1': ['Blue Lines', 'Mezzanine'],
    };
    pages = {
      _page: '<meta property="og:image" content="$_photo/1200x630cw.png">',
    };
    refuse = null;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'text/javascript; charset=utf-8'},
  );

  AppleArtists apple({bool kept = false}) => AppleArtists(
    ITunesBooks(
      MockClient((request) async {
        sent.add(request);
        if (refuse case final status?) return http.Response('', status);
        final url = request.url;
        if (url.host == 'itunes.apple.com' && url.path == '/search') {
          return json({'results': artists});
        }
        if (url.host == 'itunes.apple.com') {
          return json({
            'results': [
              {'wrapperType': 'artist'},
              for (final title in albums[url.queryParameters['id']] ?? [])
                {'wrapperType': 'collection', 'collectionName': title},
            ],
          });
        }
        if (url.host == 'music.apple.com') {
          final html = pages['$url'];
          return html == null
              ? http.Response('', 404)
              : http.Response(html, 200);
        }
        return http.Response.bytes(_jpeg, 200);
      }),
      minGap: Duration.zero,
    ),
    file: kept
        ? JsonFile(
            File('${dir.path}${Platform.pathSeparator}apple_artists.json'),
          )
        : null,
    pageGap: Duration.zero,
    pageJitter: Duration.zero,
  );

  List<String> asked() => [
    for (final request in sent)
      switch (request.url.host) {
        'itunes.apple.com' =>
          '${request.url.path} '
              '${request.url.queryParameters['term'] ?? request.url.queryParameters['id']}',
        _ => '${request.url}',
      },
  ];

  test('the match is one search of the US store for artists of the name, '
      'then each namesake\'s albums; the photo is read off the matched '
      'artist\'s page and fetched at 640 × 640', () async {
    final found = await apple().find('Massive Attack', ['Mezzanine']);
    expect((found as ArtistPhotoFound).bytes, _jpeg);
    expect(asked(), [
      '/search Massive Attack',
      '/lookup 1',
      _page,
      '$_photo/640x640cc.jpg',
    ]);
    expect(sent.first.url.queryParameters, {
      'term': 'Massive Attack',
      'media': 'music',
      'entity': 'musicArtist',
      'attribute': 'artistTerm',
      'limit': '50',
    });
  });

  test('a namesake that lists none of the owned albums is no match, and no '
      'page is read', () async {
    final found = await apple().find('Massive Attack', ['Heligoland']);
    expect((found as ArtistNotFound).reason, MissingReason.noMatch);
    expect(asked(), ['/search Massive Attack', '/lookup 1']);
  });

  test('a page with an album cover, or no page, is no photo', () async {
    pages[_page] =
        '<meta property="og:image" content="https://is1-ssl.mzstatic.com/'
        'image/thumb/Music126/v4/a/cover.jpg/1200x630cw.png">';
    var found = await apple().find('Massive Attack', ['Mezzanine']);
    expect((found as ArtistNotFound).reason, MissingReason.noPhoto);
    pages[_page] = null;
    found = await apple().find('Massive Attack', ['Mezzanine']);
    expect((found as ArtistNotFound).reason, MissingReason.noPhoto);
  });

  test('at most ten namesakes are asked for their albums', () async {
    artists = [
      for (var i = 1; i <= 14; i++) {'artistName': 'Ghost', 'artistId': i},
    ];
    await apple().candidates('Ghost');
    expect(sent.where((r) => r.url.path == '/lookup').length, 10);
  });

  test('a 403 or a 429 is never sent again and stops the photo work for '
      'the session', () async {
    for (final status in [403, 429]) {
      sent = [];
      refuse = status;
      final service = apple();
      await expectLater(
        service.find('Massive Attack', ['Mezzanine']),
        throwsA(
          isA<LookupException>().having(
            (e) => e.failure,
            'failure',
            LookupFailure.rateLimited,
          ),
        ),
      );
      expect(sent.length, 1);
      expect(service.stopped, isTrue);
      refuse = null;
      await expectLater(
        service.find('Massive Attack', ['Mezzanine']),
        throwsA(isA<LookupException>()),
      );
      await expectLater(
        service.photoOn(_page),
        throwsA(isA<LookupException>()),
      );
      expect(sent.length, 1);
    }
  });

  test('a refusal on the page stops the work too; another failure does '
      'not', () async {
    final service = apple();
    pages[_page] = null;
    refuse = 500;
    await expectLater(
      service.namesakes('Massive Attack'),
      throwsA(isA<LookupException>()),
    );
    expect(service.stopped, isFalse);
    refuse = 429;
    await expectLater(service.photoOn(_page), throwsA(isA<LookupException>()));
    expect(service.stopped, isTrue);
  });

  test('an image that is not a JPEG is refused', () async {
    final service = AppleArtists(
      ITunesBooks(
        MockClient((_) async => http.Response('<html>', 200)),
        minGap: Duration.zero,
      ),
    );
    await expectLater(
      service.image('https://is1-ssl.mzstatic.com/a.jpg'),
      throwsA(isA<LookupException>()),
    );
  });

  test('Pick a photo: the matched artist\'s photo and the others of the '
      'name with one album each, their pages unread; nothing is asked '
      'twice, also by the next session', () async {
    artists.add({
      'artistName': 'massive attack',
      'artistId': 3,
      'artistLinkUrl': 'https://music.apple.com/us/artist/other/3',
    });
    albums['3'] = ['Somebody Else\'s Record'];
    final service = apple(kept: true);
    final choices = await service.choices('Massive Attack', ['Mezzanine']);
    expect(choices.suggested, '$_photo/640x640cc.jpg');
    expect(choices.others, [
      (
        id: '3',
        page: 'https://music.apple.com/us/artist/other/3',
        album: 'Somebody Else\'s Record',
      ),
    ]);
    expect(asked(), [
      '/search Massive Attack',
      '/lookup 1',
      '/lookup 3',
      _page,
    ]);

    sent = [];
    final next = apple(kept: true);
    expect(
      (await next.choices('Massive Attack', ['Mezzanine'])).suggested,
      '$_photo/640x640cc.jpg',
    );
    expect(sent, isEmpty);
    // The other artist's page is read when asked for, once.
    expect(
      await next.photoOf('3', 'https://music.apple.com/us/artist/other/3'),
      isNull,
    );
    expect(
      await next.photoOf('3', 'https://music.apple.com/us/artist/other/3'),
      isNull,
    );
    expect(sent.length, 1);
  });
}
