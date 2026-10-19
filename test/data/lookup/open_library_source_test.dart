import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:async';

import 'package:library_app/data/lookup/google_books.dart';
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

  /// Open Library and, on the Google host, Google Books, from one handler.
  OpenLibrarySource source(
    Future<http.Response> Function(http.Request) handler, {
    bool withGoogle = true,
  }) {
    sent = [];
    final client = MockClient((request) {
      sent.add(request);
      return handler(request);
    });
    return OpenLibrarySource(
      client,
      google: withGoogle ? GoogleBooks(client, key: 'g-key') : null,
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
        withGoogle: false,
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
      withGoogle: false,
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
      released: Released(1897),
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
                'id': 'x',
                'volumeInfo': {
                  'title': 'Dracula',
                  'imageLinks': {
                    'thumbnail': 'http://books.google.com/books/content?id=x&zoom=1&edge=curl&source=gbs_api',
                  },
                },
              },
              {
                'id': 'y',
                'volumeInfo': {
                  'title': 'Dracula',
                  'description': 'Google&#39;s <p>summary</p>',
                  'pageCount': 0,
                },
              },
              {
                'id': 'z',
                'volumeInfo': {'title': 'Dracula', 'pageCount': 488},
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
      final fill = GoogleBooks(
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
                    'title': 'Dracula',
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
            'volumeInfo': {
              'title': 'Dracula',
              'description': 'The <b>Count</b>.',
            },
          });
        }),
      );
      sent = [];
      final filled = await fill.lookUp('Dracula', author: 'Bram Stoker');
      expect(sent.length, 2);
      expect(filled.description, 'The Count.');
      expect(filled.coverUrl, 'https://g/abc.jpg');

      // Nothing listed: the search is tried again, but no record is read.
      sent = [];
      final none = await GoogleBooks(
        MockClient((request) async {
          sent.add(request);
          return json(200, {'totalItems': 0});
        }),
        minGap: Duration.zero,
      ).lookUp('Nothing');
      expect(none.description, isNull);
      expect(sent, hasLength(GoogleBooks.emptyTries));
      expect(sent.every((r) => r.url.path == '/books/v1/volumes'), isTrue);
    },
  );

  group('a Google search that fails or comes back empty', () {
    /// Answers with [statuses] in turn, the last one from then on; 204
    /// stands for a 200 with an empty list.
    GoogleBooks google(List<int> statuses) {
      sent = [];
      var i = 0;
      return GoogleBooks(
        MockClient((request) async {
          sent.add(request);
          final status = statuses[i < statuses.length ? i++ : i - 1];
          return status == 204
              // An empty list: what a struggling Google sometimes answers.
              ? json(200, {'kind': 'books#volumes', 'totalItems': 0})
              : status == 200
              ? json(200, {
                  'items': [
                    {
                      'id': 'eOTEEQAAQBAJ',
                      'volumeInfo': {'title': 'The Weight of Angels'},
                    },
                  ],
                })
              : json(status, {
                  'error': {'message': 'Service temporarily unavailable.'},
                });
        }),
        minGap: Duration.zero,
      );
    }

    test('is sent again until it answers', () async {
      final hits = await google([503, 503, 200])
          .search('The Weight of Angels John Boyne');
      expect(hits.single.source, 'googlebooks:eOTEEQAAQBAJ');
      expect(sent, hasLength(3));
    });

    test('fails with the last error after every try', () async {
      await expectLater(
        google([503]).search('x'),
        throwsA(
          isA<LookupException>()
              .having((e) => e.status, 'status', 503)
              .having((e) => e.failure, 'failure', LookupFailure.other),
        ),
      );
      expect(sent, hasLength(GoogleBooks.searchTries));
    });

    test('an empty list is tried again, and believed the third time or '
        'when the rest failed', () async {
      final found = await google([204, 503, 204, 200]).search('Dracula');
      expect(found, hasLength(1));
      expect(sent, hasLength(4));

      expect(await google([204]).search('zzqxqv'), isEmpty);
      expect(sent, hasLength(GoogleBooks.emptyTries));

      expect(await google([204, 503]).search('zzqxqv'), isEmpty);
      expect(sent, hasLength(GoogleBooks.searchTries));
    });

    test('anything but a server error is not tried again', () async {
      for (final status in [429, 400, 403]) {
        await expectLater(
          google([status]).search('x'),
          throwsA(isA<LookupException>()),
        );
        expect(sent, hasLength(1), reason: '$status');
      }
    });

    test('the fill-in for an Open Library pick is sent again too', () async {
      final filled = await google([500, 200]).lookUp('The Weight of Angels');
      expect(sent.first.url.path, '/books/v1/volumes');
      expect(sent[1].url.path, '/books/v1/volumes');
      expect(filled.coverUrl, isNull);
    });
  });

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
          withGoogle: false,
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
              'id': 'x',
              'volumeInfo': {
                'title': 'Dracula',
                'description': 'The Count.',
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

  /// A Google Books volume as the search lists it.
  Map<String, Object?> volume(
    String id,
    String title, {
    List<String> authors = const [],
    String? date,
    String? thumbnail,
    String? description,
    int? pages,
  }) => {
    'id': id,
    'volumeInfo': {
      'title': title,
      'authors': authors,
      'publishedDate': ?date,
      'description': ?description,
      'pageCount': ?pages,
      if (thumbnail != null) 'imageLinks': {'thumbnail': thumbnail},
    },
  };

  final weightOfAngels = volume(
    'eOTEEQAAQBAJ',
    'The Weight of Angels',
    authors: ['John Boyne'],
    date: '2026-02-19',
    thumbnail: 'http://books.google.com/books/content?id=eOTEEQAAQBAJ&zoom=1',
    description: 'A <i>novel</i>.',
  );

  LookupMatch book(
    String source,
    String title, {
    String? creator,
    String? coverUrl,
    int? pages,
    Released? released,
  }) => LookupMatch(
    type: MediaType.books,
    title: title,
    source: source,
    creator: creator,
    coverUrl: coverUrl,
    pages: pages,
    released: released,
  );

  group('the same book', () {
    test('is the same title and author, case and punctuation aside', () {
      expect(
        sameBook(
          book(
            'openlibrary:OL1W',
            'The Weight of Angels',
            creator: 'John Boyne',
          ),
          book('googlebooks:a', 'the weight of angels', creator: 'JOHN BOYNE'),
        ),
        isTrue,
      );
      // One author in common is enough; the order does not matter.
      expect(
        sameBook(
          book(
            'openlibrary:OL2W',
            'Good Omens',
            creator: 'Terry Pratchett, Neil Gaiman',
          ),
          book('googlebooks:b', 'Good Omens', creator: 'Neil Gaiman'),
        ),
        isTrue,
      );
    });

    test('is not another title, nor another author, nor a missing one', () {
      final ol = book('openlibrary:OL1W', 'Dracula', creator: 'Bram Stoker');
      expect(
        sameBook(ol, book('googlebooks:a', 'Carmilla', creator: 'Bram Stoker')),
        isFalse,
      );
      expect(
        sameBook(ol, book('googlebooks:b', 'Dracula', creator: 'Dacre Stoker')),
        isFalse,
      );
      expect(sameBook(ol, book('googlebooks:c', 'Dracula')), isFalse);
      expect(
        sameBook(
          book('openlibrary:OL9W', 'Beowulf'),
          book('googlebooks:d', 'Beowulf'),
        ),
        isTrue,
      );
    });
  });

  test('the merge keeps one row per book with the Open Library id, fills its '
      'gaps from Google, and takes turns with the books only Google has', () {
    final merged = OpenLibrarySource.mergeBookHits(
      [
        book(
          'openlibrary:OL45804W',
          'Dracula',
          creator: 'Bram Stoker',
          pages: 418,
        ),
        book('openlibrary:OL2W', 'Carmilla', creator: 'Sheridan Le Fanu'),
        book('openlibrary:OL3W', "Dracula's Guest", creator: 'Bram Stoker'),
      ],
      [
        book(
          'googlebooks:a',
          'DRACULA',
          creator: 'bram stoker',
          coverUrl: 'https://g/a.jpg',
          pages: 500,
          released: const Released(2003),
        ),
        // Another edition of the same book: dropped.
        book('googlebooks:b', 'Dracula', creator: 'Bram Stoker'),
        book('googlebooks:c', 'The Weight of Angels', creator: 'John Boyne'),
        book('googlebooks:d', 'The Weight of Angels', creator: 'John Boyne'),
        book('googlebooks:e', 'Dracula', creator: 'Dacre Stoker'),
      ],
    );
    expect(
      [for (final m in merged) m.source],
      [
        'openlibrary:OL45804W',
        'googlebooks:c',
        'openlibrary:OL2W',
        'googlebooks:e',
        'openlibrary:OL3W',
      ],
    );
    // What Open Library had stays; what it lacked comes from Google.
    expect(merged.first.title, 'Dracula');
    expect(merged.first.pages, 418);
    expect(merged.first.coverUrl, 'https://g/a.jpg');
    expect(merged.first.released, const Released(2003));
    expect(
      OpenLibrarySource.mergeBookHits(
        [book('openlibrary:OL1W', 'A'), book('openlibrary:OL2W', 'B')],
        [book('googlebooks:c', 'C')],
        limit: 2,
      ).map((m) => m.source),
      ['openlibrary:OL1W', 'googlebooks:c'],
    );
  });

  test('"The Weight of Angels John Boyne" finds the book only Google Books '
      'has, asking both at once', () async {
    final googleAsked = Completer<void>();
    final ol = source((request) async {
      if (request.url.host == 'openlibrary.org') {
        // Answers only once Google was asked too: the two run in parallel.
        await googleAsked.future;
        return json(200, {'numFound': 0, 'docs': []});
      }
      googleAsked.complete();
      expect(request.url.path, '/books/v1/volumes');
      expect(
        request.url.queryParameters['q'],
        'The Weight of Angels John Boyne',
      );
      expect(request.url.queryParameters['maxResults'], '10');
      return json(200, {
        'items': [weightOfAngels, weightOfAngels],
      });
    });
    final hits = await ol.search(
      'The Weight of Angels John Boyne',
      type: MediaType.books,
    );
    expect(hits, hasLength(1));
    final hit = hits.single;
    expect(hit.source, 'googlebooks:eOTEEQAAQBAJ');
    expect(hit.title, 'The Weight of Angels');
    expect(hit.creator, 'John Boyne');
    expect(hit.released, const Released(2026, 2, 19));
    expect(hit.description, 'A novel.');
    expect(
      hit.coverUrl,
      'https://books.google.com/books/content?id=eOTEEQAAQBAJ&zoom=1',
    );
    expect(ol.issued(hit.source), isTrue);
    expect(ol.issued('openlibrary:OL1W'), isTrue);
    expect(ol.issued('igdb:1'), isFalse);
  });

  test('one source failing is a partial answer with the other\'s hits; '
      'both failing fails', () async {
    Matcher partialWith(String? source, LookupFailure failure) =>
        isA<PartialLookupException>()
            .having((e) => e.failure, 'failure', failure)
            .having((e) => [for (final m in e.matches) m.source], 'matches', [
              ?source,
            ]);

    // Google's text search down (a 503 "backendFailed" for every query on
    // 2026-10-19): Open Library's hits, and the failure.
    await expectLater(
      source((request) async {
        if (request.url.host == 'openlibrary.org') {
          return json(200, {
            'docs': [dracula],
          });
        }
        return json(503, {
          'error': {'message': 'Service temporarily unavailable.'},
        });
      }).search('dracula', type: MediaType.books),
      throwsA(partialWith('openlibrary:OL45804W', LookupFailure.other)),
    );
    // Open Library with nothing and Google down is not "no matches".
    await expectLater(
      source((request) async {
        if (request.url.host == 'openlibrary.org') {
          return json(200, {'numFound': 0, 'docs': []});
        }
        return json(429, {});
      }).search('The Weight of Angels John Boyne', type: MediaType.books),
      throwsA(partialWith(null, LookupFailure.rateLimited)),
    );
    await expectLater(
      source((request) async {
        if (request.url.host == 'openlibrary.org') return json(503, {});
        return json(200, {
          'items': [weightOfAngels],
        });
      }).search('weight of angels', type: MediaType.books),
      throwsA(partialWith('googlebooks:eOTEEQAAQBAJ', LookupFailure.other)),
    );

    await expectLater(
      source((request) async {
        if (request.url.host == 'openlibrary.org') return json(503, {});
        return json(429, {});
      }).search('x', type: MediaType.books),
      throwsA(
        allOf(
          isNot(isA<PartialLookupException>()),
          isA<LookupException>().having(
            (e) => e.failure,
            'failure',
            LookupFailure.other,
          ),
        ),
      ),
    );
  });

  test('the cover matcher takes a hit while one source is down, but a miss '
      'then is a failure, so it is asked again', () async {
    final found = await source((request) async {
      if (request.url.host == 'openlibrary.org') {
        return json(200, {
          'docs': [dracula],
        });
      }
      return json(503, {});
    }).match('Dracula', type: MediaType.books, creator: 'Bram Stoker');
    expect(found?.source, 'openlibrary:OL45804W');

    await expectLater(
      source((request) async {
        if (request.url.host == 'openlibrary.org') {
          return json(200, {'docs': []});
        }
        return json(503, {});
      }).match(
        'The Weight of Angels',
        type: MediaType.books,
        creator: 'John Boyne',
      ),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.other,
        ),
      ),
    );
  });

  test('the cover matcher finds a book only Google Books has', () async {
    final ol = source((request) async {
      if (request.url.host == 'openlibrary.org') {
        expect(request.url.queryParameters['title'], 'The Weight of Angels');
        return json(200, {'docs': []});
      }
      expect(
        request.url.queryParameters['q'],
        'intitle:"The Weight of Angels" inauthor:"John Boyne"',
      );
      return json(200, {
        'items': [weightOfAngels],
      });
    });
    final hit = await ol.match(
      'The Weight of Angels',
      type: MediaType.books,
      year: 2025,
      creator: 'John Boyne',
    );
    expect(hit?.source, 'googlebooks:eOTEEQAAQBAJ');
    expect(hit?.cacheCoverUrl, startsWith('https://books.google.com/'));
  });

  test('details of a Google pick read its volume and fill the rest from '
      'Open Library', () async {
    final ol = source((request) async {
      switch (request.url.path) {
        case '/books/v1/volumes/eOTEEQAAQBAJ':
          return json(200, {
            'id': 'eOTEEQAAQBAJ',
            'volumeInfo': {
              'title': 'The Weight of Angels',
              'authors': ['John Boyne'],
              'publishedDate': '2026',
              'imageLinks': {
                'thumbnail': 'http://g/t.jpg',
                'medium': 'http://g/m.jpg&edge=curl',
              },
            },
          });
        case '/search.json':
          expect(request.url.queryParameters['title'], 'The Weight of Angels');
          expect(request.url.queryParameters['author'], 'John Boyne');
          return json(200, {
            'docs': [
              {
                'key': '/works/OL99W',
                'title': 'The Weight of Angels',
                'author_name': ['John Boyne'],
                'first_publish_year': 2025,
                'number_of_pages_median': 320,
              },
            ],
          });
        case '/works/OL99W.json':
          return json(200, {'description': 'From Open Library.'});
      }
      fail('unexpected ${request.url}');
    });
    final full = await ol.details(
      book(
        'googlebooks:eOTEEQAAQBAJ',
        'The Weight of Angels',
        creator: 'John Boyne',
      ),
    );
    expect(full.source, 'googlebooks:eOTEEQAAQBAJ');
    expect(full.description, 'From Open Library.');
    expect(full.pages, 320);
    // Google's own year and cover stay; only gaps are filled.
    expect(full.released, const Released(2026));
    expect(full.coverUrl, 'https://g/t.jpg');
    expect(full.largeCoverUrl, 'https://g/m.jpg');
  });

  test(
    'coverUrl handles a Google id: its own cover, else Open Library\'s',
    () async {
      Map<String, Object?> record({Map<String, String>? links}) => {
        'id': 'eOTEEQAAQBAJ',
        'volumeInfo': {
          'title': 'The Weight of Angels',
          'authors': ['John Boyne'],
          'imageLinks': ?links,
        },
      };
      expect(
        await source((request) async {
          expect(request.url.path, '/books/v1/volumes/eOTEEQAAQBAJ');
          return json(
            200,
            record(
              links: {
                'thumbnail': 'http://g/t.jpg',
                'medium': 'http://g/m.jpg',
              },
            ),
          );
        }).coverUrl('googlebooks:eOTEEQAAQBAJ', type: MediaType.books),
        'https://g/m.jpg',
      );
      expect(
        await source((request) async {
          switch (request.url.path) {
            case '/search.json':
              return json(200, {
                'docs': [
                  {
                    'key': '/works/OL99W',
                    'title': 'The Weight of Angels',
                    'author_name': ['John Boyne'],
                    'cover_i': 42,
                  },
                ],
              });
            case '/works/OL99W.json':
              return json(200, {});
          }
          return json(200, record());
        }).coverUrl('googlebooks:eOTEEQAAQBAJ', type: MediaType.books),
        'https://covers.openlibrary.org/b/id/42-L.jpg',
      );
      expect(
        source((_) async => json(200, {}))
            .coverUrl('googlebooks:', type: MediaType.books),
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
