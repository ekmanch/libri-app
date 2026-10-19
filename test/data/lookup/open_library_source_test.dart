import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/google_books_fill_in.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/open_library_source.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';

void main() {
  late List<http.Request> sent;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final dracula = {
    'key': '/works/OL45804W',
    'title': 'Dracula',
    'author_name': ['Bram Stoker'],
    'first_publish_year': 1897,
    'cover_i': 8739161,
    'number_of_pages_median': 418,
    'subject': [
      'Vampires',
      'award:bram_stoker_award=1897',
      'Fiction, horror, general',
      'Horror',
      'English fiction -- 19th century -- History and criticism',
      'Transylvania (Romania) -- Fiction',
      'Gothic',
      'Classic',
      'Extra',
      'Another',
    ],
  };

  /// Open Library and, on the Google host, the fill-in, from one handler.
  OpenLibrarySource source(
    Future<http.Response> Function(http.Request) handler, {
    bool withFillIn = true,
  }) {
    sent = [];
    final client = MockClient((request) {
      sent.add(request);
      return handler(request);
    });
    return OpenLibrarySource(
      client,
      fillIn: withFillIn ? GoogleBooksFillIn(client, key: 'g-key') : null,
    );
  }

  test(
    'searches and parses docs: work id, first year, cover, subjects, pages',
    () async {
      final ol = source(
        (_) async => json(200, {
          'docs': [
            dracula,
            {'key': '/works/OL1W', 'title': 'No Cover', 'cover_i': -1},
            {'title': 'No key'},
          ],
        }),
      );
      final hits = await ol.search('dracula', type: MediaType.books, limit: 10);
      final request = sent.single;
      expect(request.url.host, 'openlibrary.org');
      expect(request.url.path, '/search.json');
      expect(request.url.queryParameters['q'], 'dracula');
      expect(request.url.queryParameters['limit'], '10');
      expect(
        request.url.queryParameters['fields'],
        allOf(
          contains('first_publish_year'),
          contains('number_of_pages_median'),
        ),
      );
      expect(request.headers['User-Agent'], 'Libri');

      expect(hits.length, 2);
      expect(hits[0].source, 'openlibrary:OL45804W');
      expect(hits[0].released, const Released(1897));
      expect(hits[0].creator, 'Bram Stoker');
      expect(
        hits[0].coverUrl,
        'https://covers.openlibrary.org/b/id/8739161-M.jpg',
      );
      expect(hits[0].tags, [
        'Vampires',
        'Horror',
        'Gothic',
        'Classic',
        'Extra',
        'Another',
      ]);
      expect(hits[0].description, '');
      expect(hits[0].pages, 418);
      expect(hits[1].coverUrl, isNull);
      expect(hits[1].released, isNull);
      expect(hits[1].pages, isNull);
    },
  );

  test('match searches by title and author and checks the year', () async {
    final ol = source(
      (_) async => json(200, {
        'docs': [
          {...dracula, 'first_publish_year': 2003, 'key': '/works/OLreprintW'},
          dracula,
        ],
      }),
    );
    final hit = await ol.match(
      'Dracula',
      type: MediaType.books,
      year: 1897,
      creator: 'Bram Stoker',
    );
    expect(sent.single.url.queryParameters['title'], 'Dracula');
    expect(sent.single.url.queryParameters['author'], 'Bram Stoker');
    expect(hit!.source, 'openlibrary:OL45804W');

    // Same title and author, another year: still the book.
    final otherYear = await ol.match(
      'Dracula',
      type: MediaType.books,
      year: 1950,
      creator: 'Bram Stoker',
    );
    expect(otherYear!.source, 'openlibrary:OLreprintW');
    // No author and the wrong year: not sure enough.
    expect(
      await ol.match('Dracula', type: MediaType.books, year: 1950),
      isNull,
    );
    expect(
      (await ol.match('dracula', type: MediaType.books))!.title,
      'Dracula',
    );
    expect(await ol.match('Carmilla', type: MediaType.books), isNull);
  });

  test('details take the description from the work, else from Google, and '
      'the page count from the search, else from Google', () async {
    final ol = source((request) async {
      if (request.url.host == 'openlibrary.org') {
        return json(200, {
          'title': 'Dracula',
          'description': {
            'type': '/type/text',
            'value': 'The <b>Count</b> comes to England.',
          },
          'covers': [-1, 8739161],
        });
      }
      fail('Google Books asked although nothing was missing');
    });
    const plain = LookupMatch(
      type: MediaType.books,
      title: 'Dracula',
      source: 'openlibrary:OL45804W',
      creator: 'Bram Stoker',
      pages: 418,
    );
    final full = await ol.details(plain);
    expect(sent.single.url.path, '/works/OL45804W.json');
    expect(full.description, 'The Count comes to England.');
    expect(full.coverUrl, 'https://covers.openlibrary.org/b/id/8739161-M.jpg');
    expect(full.pages, 418);

    final filled =
        await source((request) async {
          if (request.url.host == 'openlibrary.org') {
            return json(200, {'title': 'Dracula'});
          }
          expect(request.url.host, 'www.googleapis.com');
          expect(
            request.url.queryParameters['q'],
            'intitle:"Dracula" inauthor:"Bram Stoker"',
          );
          expect(request.url.queryParameters['key'], 'g-key');
          expect(request.url.queryParameters['printType'], 'books');
          return json(200, {
            'items': [
              {
                'volumeInfo': {
                  'imageLinks': {
                    'thumbnail': 'http://books.google.com/books/content?id=x&zoom=1&edge=curl&source=gbs_api',
                  },
                },
              },
              {
                'volumeInfo': {
                  'description': 'Google&#39;s <p>summary</p>',
                  'pageCount': 0,
                },
              },
              {
                'volumeInfo': {'pageCount': 488},
              },
            ],
          });
        }).details(
          LookupMatch(
            type: plain.type,
            title: plain.title,
            source: plain.source,
            creator: plain.creator,
          ),
        );
    expect(sent.length, 2);
    expect(filled.description, "Google's summary");
    expect(filled.pages, 488);
    expect(
      filled.coverUrl,
      'https://books.google.com/books/content?id=x&zoom=1&source=gbs_api',
    );
  });

  test(
    'the fill-in reads the volume itself when the list has no text',
    () async {
      final fill = GoogleBooksFillIn(
        MockClient((request) async {
          sent.add(request);
          if (request.url.path.endsWith('/volumes')) {
            expect(request.url.queryParameters['maxResults'], '10');
            expect(request.url.queryParameters['projection'], 'full');
            return json(200, {
              'items': [
                {
                  'id': 'abc',
                  'volumeInfo': {
                    'imageLinks': {'thumbnail': 'http://g/abc.jpg'},
                  },
                },
                {
                  'id': 'def',
                  'volumeInfo': {'title': 'Dracula'},
                },
              ],
            });
          }
          expect(request.url.path, '/books/v1/volumes/abc');
          return json(200, {
            'id': 'abc',
            'volumeInfo': {'description': 'The <b>Count</b>.'},
          });
        }),
      );
      sent = [];
      final filled = await fill.lookUp('Dracula', author: 'Bram Stoker');
      expect(sent.length, 2);
      expect(filled.description, 'The Count.');
      expect(filled.coverUrl, 'https://g/abc.jpg');

      // Nothing listed: nothing asked further.
      final none = await GoogleBooksFillIn(
        MockClient((request) async {
          sent.add(request);
          return json(200, {'totalItems': 0});
        }),
      ).lookUp('Nothing');
      expect(none.description, isNull);
      expect(sent.length, 3);
    },
  );

  test('a failing fill-in leaves the gaps open rather than failing', () async {
    final ol = source((request) async {
      if (request.url.host == 'openlibrary.org') {
        return json(200, {'title': 'X'});
      }
      return json(429, {
        'error': {'message': 'quota'},
      });
    });
    final full = await ol.details(
      const LookupMatch(
        type: MediaType.books,
        title: 'X',
        source: 'openlibrary:OL1W',
      ),
    );
    expect(full.description, '');
    expect(full.coverUrl, isNull);
    expect(full.pages, isNull);
    final none =
        await source(
          (_) async => json(200, {'title': 'X'}),
          withFillIn: false,
        ).details(
          const LookupMatch(
            type: MediaType.books,
            title: 'X',
            source: 'openlibrary:OL1W',
          ),
        );
    expect(none.coverUrl, isNull);
    expect(sent.length, 1);
  });

  test(
    'coverUrl gives the large cover, or asks Google by the work title',
    () async {
      expect(
        await source(
          (_) async => json(200, {
            'title': 'Dracula',
            'covers': [8739161],
          }),
        ).coverUrl('openlibrary:OL45804W', type: MediaType.books),
        'https://covers.openlibrary.org/b/id/8739161-L.jpg',
      );
      final viaGoogle = await source((request) async {
        if (request.url.host == 'openlibrary.org') {
          return json(200, {'title': 'Dracula'});
        }
        expect(request.url.queryParameters['q'], 'intitle:"Dracula"');
        return json(200, {
          'items': [
            {
              'volumeInfo': {
                'imageLinks': {'thumbnail': 'http://g/x.jpg'},
              },
            },
          ],
        });
      }).coverUrl('openlibrary:OL45804W', type: MediaType.books);
      expect(viaGoogle, 'https://g/x.jpg');
      expect(
        source((_) async => json(200, {}))
            .coverUrl('igdb:1', type: MediaType.books),
        throwsA(isA<LookupException>()),
      );
    },
  );

  test('429 is rate limited', () async {
    expect(
      source((_) async => json(429, {})).search('x', type: MediaType.books),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.rateLimited,
        ),
      ),
    );
  });
}
