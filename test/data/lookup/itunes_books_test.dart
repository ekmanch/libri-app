import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/itunes_books.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/models/released.dart';

void main() {
  late List<http.Request> sent;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'text/javascript; charset=utf-8'},
  );

  ITunesBooks apple(Future<http.Response> Function(http.Request) handler) {
    sent = [];
    return ITunesBooks(
      MockClient((request) {
        sent.add(request);
        return handler(request);
      }),
      minGap: Duration.zero,
    );
  }

  const artwork =
      'https://is1-ssl.mzstatic.com/image/thumb/Publication211/v4/7e/d5/16/'
      '7ed516bc/9781250411372.jpg/100x100bb.jpg';

  final weightOfAngels = {
    'kind': 'ebook',
    'trackId': 6756269989,
    'trackName': 'The Weight of Angels',
    'artistName': 'John Boyne',
    'releaseDate': '2026-09-29T07:00:00Z',
    'description': '<b>Can one rash decision</b><br /><br />prove &#xa0;it?',
    'genres': ['Fiction & Literature', 'Books', 'LGBTQIA+ Fiction'],
    'artworkUrl100': artwork,
    'price': 15.99,
  };

  test('searches ebooks and parses them: id, date, author, text, genres, '
      'artwork at 200 and 600 px', () async {
    final hits = await apple(
      (_) async => json(200, {
        'resultCount': 4,
        'results': [
          weightOfAngels,
          // Another edition of the same book: dropped.
          {...weightOfAngels, 'trackId': 7},
          {'trackId': 8, 'trackName': 'No Author'},
          {'trackName': 'No id'},
        ],
      }),
    ).search('The Weight of Angels John Boyne', limit: 10);
    final request = sent.single;
    expect(request.url.host, 'itunes.apple.com');
    expect(request.url.path, '/search');
    expect(request.url.queryParameters, {
      'term': 'The Weight of Angels John Boyne',
      'entity': 'ebook',
      'media': 'ebook',
      'limit': '10',
    });
    expect(request.headers['User-Agent'], 'Libri');

    expect(hits, hasLength(2));
    final hit = hits.first;
    expect(hit.source, 'itunes:6756269989');
    expect(hit.title, 'The Weight of Angels');
    expect(hit.creator, 'John Boyne');
    expect(hit.released, const Released(2026, 9, 29));
    expect(hit.releasedFromEbook, isTrue);
    expect(hit.description, 'Can one rash decision\n\nprove it?');
    expect(hit.tags, ['Fiction & Literature', 'LGBTQIA+ Fiction']);
    expect(hit.pages, isNull);
    expect(hit.coverUrl, artwork.replaceFirst('100x100bb', '200x200bb'));
    expect(hit.largeCoverUrl, artwork.replaceFirst('100x100bb', '600x600bb'));
    expect(hits[1].source, 'itunes:8');
    expect(hits[1].creator, isNull);
    expect(hits[1].coverUrl, isNull);
  });

  test('searchTitle joins the title and the author', () async {
    await apple((_) async => json(200, {'results': []}))
        .searchTitle('King Rat', author: 'James Clavell', limit: 5);
    expect(sent.single.url.queryParameters['term'], 'King Rat James Clavell');
    expect(sent.single.url.queryParameters['limit'], '5');
    await apple((_) async => json(200, {'results': []}))
        .searchTitle('King Rat');
    expect(sent.single.url.queryParameters['term'], 'King Rat');
  });

  test('book reads one record by id, or null', () async {
    final hit = await apple((request) async {
      expect(request.url.path, '/lookup');
      expect(request.url.queryParameters, {
        'id': '6756269989',
        'entity': 'ebook',
      });
      return json(200, {
        'results': [weightOfAngels],
      });
    }).book('itunes:6756269989');
    expect(hit?.source, 'itunes:6756269989');
    expect(
      await apple((_) async => json(200, {'resultCount': 0, 'results': []}))
          .book('itunes:1'),
      isNull,
    );
    for (final bad in ['itunes:', 'googlebooks:x', 'itunes']) {
      expect(
        apple((_) async => json(200, {})).book(bad),
        throwsA(isA<LookupException>()),
        reason: bad,
      );
    }
  });

  test('artwork is asked for at any size', () {
    expect(
      ITunesBooks.artworkAt(artwork, 600),
      artwork.replaceFirst('100x100bb', '600x600bb'),
    );
    expect(
      ITunesBooks.artworkAt('https://x/y/cover.png/100x100.png', 600),
      'https://x/y/cover.png/600x600.png',
    );
    expect(
      ITunesBooks.artworkAt('https://x/cover.jpg', 600),
      'https://x/cover.jpg',
    );
  });

  test('403 and 429 are rate limited; a 5xx is "other" with its status', () {
    for (final status in [403, 429]) {
      expect(
        apple((_) async => http.Response('Forbidden', status)).search('x'),
        throwsA(
          isA<LookupException>()
              .having((e) => e.failure, 'failure', LookupFailure.rateLimited)
              .having((e) => e.status, 'status', status),
        ),
        reason: '$status',
      );
    }
    expect(
      apple((_) async => json(503, {})).search('x'),
      throwsA(
        isA<LookupException>()
            .having((e) => e.failure, 'failure', LookupFailure.other)
            .having((e) => e.status, 'status', 503),
      ),
    );
  });
}
