import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/google_books.dart';
import 'package:library_app/data/lookup/itunes_books.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/open_library_source.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/lookup/wikidata_series.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/data/models/follow_kind.dart';

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
    'publish_year': [1897, 1898, 1920],
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

  /// Open Library's King Rat, as on 2026-10-20: a 1950 edition that is
  /// nothing of the kind dates a 1962 book.
  final kingRat = {
    'key': '/works/OL2918736W',
    'title': 'King Rat',
    'author_name': ['James Clavell'],
    'first_publish_year': 1950,
    'publish_year': [1950, 1962, 1963, 1965, 2013],
    // The work's cover is a Spanish edition's; the best English edition
    // has its own.
    'cover_i': 13268339,
    'editions': {
      'numFound': 32,
      'docs': [
        {'key': '/books/OL23256803M', 'cover_i': 9524340},
      ],
    },
    'number_of_pages_median': 391,
    'subject': ['Prisoners of war', 'War stories'],
  };

  const artwork =
      'https://is1-ssl.mzstatic.com/image/thumb/Publication123/v4/9d/b3/68/'
      'bhdp-rectangle.jpg/100x100bb.jpg';
  const artwork200 =
      'https://is1-ssl.mzstatic.com/image/thumb/Publication123/v4/9d/b3/68/'
      'bhdp-rectangle.jpg/200x200bb.jpg';
  const artwork600 =
      'https://is1-ssl.mzstatic.com/image/thumb/Publication123/v4/9d/b3/68/'
      'bhdp-rectangle.jpg/600x600bb.jpg';

  /// An Apple Books result as the search lists it.
  Map<String, Object?> ebook(
    int id,
    String title, {
    String? author,
    String? date,
    String? description,
    String? art,
    List<String> genres = const [],
  }) => {
    'kind': 'ebook',
    'trackId': id,
    'trackName': title,
    'artistName': ?author,
    'releaseDate': ?date,
    'description': ?description,
    'artworkUrl100': ?art,
    'genres': genres,
  };

  final appleKingRat = ebook(
    1436057399,
    'King Rat',
    author: 'James Clavell',
    date: '2015-07-28T07:00:00Z',
    description: 'Japanese POW camp <i>Changi</i>, Singapore.',
    art: artwork,
    genres: ['Historical Fiction', 'Books'],
  );

  final weightOfAngels = ebook(
    6756269989,
    'The Weight of Angels',
    author: 'John Boyne',
    date: '2026-09-29T07:00:00Z',
    description: 'A <i>novel</i>.',
    art: artwork,
    genres: ['Fiction & Literature', 'Books'],
  );

  /// Open Library, Apple Books (on the Apple host) and Google Books (on
  /// the Google host), from one handler.
  OpenLibrarySource source(
    Future<http.Response> Function(http.Request) handler, {
    bool withApple = true,
  }) {
    sent = [];
    final client = MockClient((request) {
      sent.add(request);
      return handler(request);
    });
    return OpenLibrarySource(
      client,
      apple: withApple ? ITunesBooks(client, minGap: Duration.zero) : null,
      google: GoogleBooks(client, key: 'g-key'),
    );
  }

  bool isOpenLibrary(http.Request r) => r.url.host == 'openlibrary.org';
  bool isApple(http.Request r) => r.url.host == 'itunes.apple.com';
  bool isGoogle(http.Request r) => r.url.host == 'www.googleapis.com';

  LookupMatch book(
    String source,
    String title, {
    String? creator,
    String? coverUrl,
    String? largeCoverUrl,
    String description = '',
    int? pages,
    Released? released,
    List<String> tags = const [],
  }) => LookupMatch(
    type: MediaType.books,
    title: title,
    source: source,
    creator: creator,
    coverUrl: coverUrl,
    largeCoverUrl: largeCoverUrl,
    description: description,
    pages: pages,
    released: released,
    tags: tags,
  );

  test(
    'searches and parses docs: work id, first year, cover, subjects, pages',
    () async {
      final ol = source(
        (_) async => json(200, {
          'docs': [
            dracula,
            kingRat,
            {'key': '/works/OL1W', 'title': 'No Cover', 'cover_i': -1},
            {'key': '/works/OL2W', 'title': 'Old', 'first_publish_year': 1983},
            {'title': 'No key'},
          ],
        }),
        withApple: false,
      );
      final hits = await ol.search('dracula', type: MediaType.books, limit: 10);
      final request = sent.single;
      expect(request.url.host, 'openlibrary.org');
      expect(request.url.path, '/search.json');
      expect(request.url.queryParameters['q'], 'dracula');
      expect(request.url.queryParameters['limit'], '10');
      expect(request.url.queryParameters['lang'], 'en');
      expect(
        request.url.queryParameters['fields'],
        allOf(
          contains('first_publish_year'),
          contains('publish_year'),
          contains('number_of_pages_median'),
          contains('editions.cover_i'),
        ),
      );
      expect(request.headers['User-Agent'], 'Libri');

      expect(hits.length, 4);
      expect(hits[0].source, 'openlibrary:OL45804W');
      expect(hits[0].released, const Released(1897));
      expect(hits[0].creator, 'Bram Stoker');
      expect(
        hits[0].coverUrl,
        'https://covers.openlibrary.org/b/id/8739161-M.jpg',
      );
      expect(
        hits[0].largeCoverUrl,
        'https://covers.openlibrary.org/b/id/8739161-L.jpg',
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
      // The lone 1950 edition is skipped: 1962 is the first publication.
      expect(hits[1].released, const Released(1962));
      // The English edition's cover, not the work's Spanish one.
      expect(
        hits[1].coverUrl,
        'https://covers.openlibrary.org/b/id/9524340-M.jpg',
      );
      expect(
        hits[1].largeCoverUrl,
        'https://covers.openlibrary.org/b/id/9524340-L.jpg',
      );
      expect(hits[2].coverUrl, isNull);
      expect(hits[2].released, isNull);
      expect(hits[2].pages, isNull);
      // Without the list of years, Open Library's own first year serves.
      expect(hits[3].released, const Released(1983));
    },
  );

  test(
    'a work in one language says which; one with translations does not',
    () async {
      final ol = source(
        (_) async => json(200, {
          'docs': [
            {
              'key': '/works/OL1W',
              'title': 'Akira',
              'language': ['jpn'],
            },
            {
              'key': '/works/OL2W',
              'title': 'Berserk',
              'language': ['jpn', 'eng', 'fre'],
            },
            {'key': '/works/OL3W', 'title': 'Nothing'},
          ],
        }),
        withApple: false,
      );
      final hits = await ol.search('x', type: MediaType.books);
      expect(sent.single.url.queryParameters['fields'], contains('language'));
      expect(hits[0].language, 'jpn');
      expect(hits[1].language, isNull);
      expect(hits[2].language, isNull);
    },
  );

  test('match searches by title and author and checks the year', () async {
    final ol = source(
      (_) async => json(200, {
        'docs': [
          {
            ...dracula,
            'first_publish_year': 2003,
            'publish_year': [2003],
            'key': '/works/OLreprintW',
          },
          dracula,
        ],
      }),
      withApple: false,
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

  test('"King Rat James Clavell" asks both at once and is one row: Open '
      'Library\'s id, year, author and pages, Apple\'s description and '
      'cover; "The Weight of Angels" is Apple\'s own row', () async {
    final appleAsked = Completer<void>();
    final ol = source((request) async {
      if (isOpenLibrary(request)) {
        // Answers only once Apple was asked too: the two run in parallel.
        await appleAsked.future;
        expect(request.url.queryParameters['q'], 'King Rat James Clavell');
        return json(200, {
          'docs': [kingRat],
        });
      }
      appleAsked.complete();
      expect(request.url.path, '/search');
      expect(request.url.queryParameters['term'], 'King Rat James Clavell');
      expect(request.url.queryParameters['entity'], 'ebook');
      expect(request.url.queryParameters['limit'], '10');
      return json(200, {
        'results': [
          appleKingRat,
          // Another edition of the same book: dropped.
          {...appleKingRat, 'trackId': 2},
          weightOfAngels,
        ],
      });
    });
    final hits = await ol.search(
      'King Rat James Clavell',
      type: MediaType.books,
    );
    expect(hits.map((h) => h.source), [
      'openlibrary:OL2918736W',
      'itunes:6756269989',
    ]);
    final rat = hits.first;
    expect(rat.title, 'King Rat');
    expect(rat.released, const Released(1962));
    expect(rat.creator, 'James Clavell');
    expect(rat.pages, 391);
    expect(rat.tags, ['Prisoners of war', 'War stories']);
    expect(rat.description, 'Japanese POW camp Changi, Singapore.');
    expect(rat.coverUrl, artwork200);
    expect(rat.largeCoverUrl, artwork600);

    final angels = hits[1];
    expect(angels.title, 'The Weight of Angels');
    expect(angels.creator, 'John Boyne');
    expect(angels.released, const Released(2026, 9, 29));
    expect(angels.description, 'A novel.');
    expect(angels.tags, ['Fiction & Literature']);
    expect(angels.coverUrl, artwork200);
    expect(angels.pages, isNull);
    expect(ol.issued(angels.source), isTrue);
    expect(ol.issued('openlibrary:OL1W'), isTrue);
    expect(ol.issued('googlebooks:eOTEEQAAQBAJ'), isTrue);
    expect(ol.issued('igdb:1'), isFalse);
  });

  test('searchSteps gives Apple\'s hits while Open Library is slow, then '
      'both merged', () async {
    final openLibraryMayAnswer = Completer<void>();
    final ol = source((request) async {
      if (isOpenLibrary(request)) {
        await openLibraryMayAnswer.future;
        return json(200, {
          'docs': [kingRat],
        });
      }
      return json(200, {
        'results': [appleKingRat, weightOfAngels],
      });
    });
    final steps = <List<String>>[];
    final done = ol.searchSteps('King Rat', type: MediaType.books).listen((
      hits,
    ) {
      steps.add([for (final h in hits) h.source]);
      if (!openLibraryMayAnswer.isCompleted) openLibraryMayAnswer.complete();
    }).asFuture<void>();
    await done;
    expect(steps, [
      ['itunes:1436057399', 'itunes:6756269989'],
      ['openlibrary:OL2918736W', 'itunes:6756269989'],
    ]);
  });

  test('sameMatch finds an early Apple hit as the merged Open Library row '
      'of the same book, else by its own id', () async {
    final openLibraryMayAnswer = Completer<void>();
    final ol = source((request) async {
      if (isOpenLibrary(request)) {
        await openLibraryMayAnswer.future;
        return json(200, {
          'docs': [kingRat],
        });
      }
      return json(200, {
        'results': [appleKingRat, weightOfAngels],
      });
    });
    final steps = <List<LookupMatch>>[];
    await ol.searchSteps('King Rat', type: MediaType.books).listen((hits) {
      steps.add(hits);
      if (!openLibraryMayAnswer.isCompleted) openLibraryMayAnswer.complete();
    }).asFuture<void>();
    final [early, complete] = steps;
    final rat = ol.sameMatch(early.first, complete)!;
    expect(rat.source, 'openlibrary:OL2918736W');
    expect(rat.released, const Released(1962));
    expect(ol.sameMatch(early[1], complete)!.source, 'itunes:6756269989');
    expect(
      ol.sameMatch(
        book('itunes:9', 'Tai-Pan', creator: 'James Clavell'),
        complete,
      ),
      isNull,
    );
  });

  test('searchSteps is one step when Open Library answers first', () async {
    final appleMayAnswer = Completer<void>();
    final ol = source((request) async {
      if (isOpenLibrary(request)) {
        appleMayAnswer.complete();
        return json(200, {
          'docs': [kingRat],
        });
      }
      // Well after Open Library's answer has been read.
      await appleMayAnswer.future;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return json(200, {
        'results': [appleKingRat],
      });
    });
    final steps = await ol
        .searchSteps('King Rat', type: MediaType.books)
        .toList();
    expect(steps, hasLength(1));
    expect(steps.single.single.source, 'openlibrary:OL2918736W');
  });

  test('the merge keeps one row per book with the Open Library id, takes '
      'Apple\'s description and cover for it, and takes turns with the '
      'books only Apple has', () {
    final merged = OpenLibrarySource.mergeBookHits(
      [
        book(
          'openlibrary:OL45804W',
          'Dracula',
          creator: 'Bram Stoker',
          released: const Released(1897),
          pages: 418,
          coverUrl: 'https://covers.openlibrary.org/b/id/1-M.jpg',
          largeCoverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
          tags: ['Vampires'],
        ),
        book('openlibrary:OL2W', 'Carmilla', creator: 'Sheridan Le Fanu'),
        book('openlibrary:OL3W', "Dracula's Guest", creator: 'Bram Stoker'),
      ],
      [
        book(
          'itunes:1',
          'DRACULA',
          creator: 'bram stoker',
          coverUrl: artwork200,
          largeCoverUrl: artwork600,
          description: 'The Count.',
          released: const Released(2003, 1, 1),
          tags: ['Horror'],
        ),
        // Another edition of the same book: dropped.
        book('itunes:2', 'Dracula', creator: 'Bram Stoker'),
        book('itunes:3', 'The Weight of Angels', creator: 'John Boyne'),
        book('itunes:4', 'The Weight of Angels', creator: 'John Boyne'),
        book('itunes:5', 'Dracula', creator: 'Dacre Stoker'),
      ],
    );
    expect(
      [for (final m in merged) m.source],
      [
        'openlibrary:OL45804W',
        'itunes:3',
        'openlibrary:OL2W',
        'itunes:5',
        'openlibrary:OL3W',
      ],
    );
    // Open Library's year, author, subjects and pages stay; Apple's
    // description and cover replace what Open Library had.
    final first = merged.first;
    expect(first.title, 'Dracula');
    expect(first.released, const Released(1897));
    expect(first.creator, 'Bram Stoker');
    expect(first.pages, 418);
    expect(first.tags, ['Vampires']);
    expect(first.description, 'The Count.');
    expect(first.coverUrl, artwork200);
    expect(first.largeCoverUrl, artwork600);
    expect(
      OpenLibrarySource.mergeBookHits(
        [book('openlibrary:OL1W', 'A'), book('openlibrary:OL2W', 'B')],
        [book('itunes:3', 'C')],
        limit: 2,
      ).map((m) => m.source),
      ['openlibrary:OL1W', 'itunes:3'],
    );
  });

  test('an Open Library row without Apple\'s record keeps its own cover, '
      'and takes Apple\'s year and genres only as gaps', () {
    final merged = OpenLibrarySource.withApple(
      book(
        'openlibrary:OL1W',
        'X',
        coverUrl: 'https://covers.openlibrary.org/b/id/1-M.jpg',
        largeCoverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
      ),
      book(
        'itunes:1',
        'X',
        creator: 'Someone',
        released: const Released(2015, 7, 28),
        tags: ['Fiction'],
      ),
    );
    expect(merged.coverUrl, 'https://covers.openlibrary.org/b/id/1-M.jpg');
    expect(merged.largeCoverUrl, 'https://covers.openlibrary.org/b/id/1-L.jpg');
    expect(merged.creator, 'Someone');
    expect(merged.released, const Released(2015, 7, 28));
    expect(merged.tags, ['Fiction']);
    expect(merged.description, '');
  });

  test('the year is marked as the ebook\'s only while Open Library has '
      'none', () {
    final ebook = book(
      'itunes:1',
      'X',
      released: const Released(2015, 7, 28),
    ).copyWith(releasedFromEbook: true);
    final dated = book('openlibrary:OL1W', 'X', released: const Released(1974));
    final undated = book('openlibrary:OL1W', 'X');

    expect(OpenLibrarySource.withApple(dated, ebook).releasedFromEbook, false);
    expect(OpenLibrarySource.withApple(undated, ebook).releasedFromEbook, true);
    final picked = OpenLibrarySource.withOpenLibrary(ebook, dated);
    expect(picked.released, const Released(1974));
    expect(picked.releasedFromEbook, false);
    expect(
      OpenLibrarySource.withOpenLibrary(ebook, undated).releasedFromEbook,
      true,
    );
    expect(
      OpenLibrarySource.withOpenLibrary(ebook, null).releasedFromEbook,
      true,
    );
  });

  group('details of an Open Library pick', () {
    const complete = LookupMatch(
      type: MediaType.books,
      title: 'King Rat',
      source: 'openlibrary:OL2918736W',
      creator: 'James Clavell',
      released: Released(1962),
      description: 'Japanese POW camp Changi, Singapore.',
      coverUrl: artwork200,
      largeCoverUrl: artwork600,
      pages: 391,
    );

    test('ask nothing when the search had it all', () async {
      final ol = source((request) async => fail('asked ${request.url}'));
      expect(await ol.details(complete), complete);
      expect(sent, isEmpty);
    });

    test('ask Apple for a missing description or cover, by title and '
        'author, and nothing more when it has them', () async {
      final ol = source((request) async {
        expect(isApple(request), isTrue, reason: '${request.url}');
        expect(request.url.queryParameters['term'], 'King Rat James Clavell');
        return json(200, {
          'results': [
            ebook(5, 'King Rat Study Guide', author: 'BookRags.com'),
            appleKingRat,
          ],
        });
      });
      final full = await ol.details(
        book(
          'openlibrary:OL2918736W',
          'King Rat',
          creator: 'James Clavell',
          released: const Released(1962),
          pages: 391,
          coverUrl: 'https://covers.openlibrary.org/b/id/13268339-M.jpg',
          largeCoverUrl: 'https://covers.openlibrary.org/b/id/13268339-L.jpg',
        ),
      );
      expect(sent, hasLength(1));
      expect(full.source, 'openlibrary:OL2918736W');
      expect(full.description, 'Japanese POW camp Changi, Singapore.');
      expect(full.coverUrl, artwork200);
      expect(full.largeCoverUrl, artwork600);
      // Open Library's year stays over Apple's edition date.
      expect(full.released, const Released(1962));
      expect(full.pages, 391);
    });

    test('read the work when Apple has no such book, or fails', () async {
      final work = {
        'title': 'Dracula',
        'description': {
          'type': '/type/text',
          'value': 'The <b>Count</b> comes to England.',
        },
        'covers': [-1, 8739161],
      };
      final plain = book(
        'openlibrary:OL45804W',
        'Dracula',
        creator: 'Bram Stoker',
        released: const Released(1897),
        pages: 418,
      );
      final full = await source((request) async {
        if (isApple(request)) {
          return json(200, {
            'results': [ebook(9, 'Dracula', author: 'Dacre Stoker')],
          });
        }
        expect(request.url.path, '/works/OL45804W.json');
        return json(200, work);
      }).details(plain);
      expect(sent, hasLength(2));
      expect(full.description, 'The Count comes to England.');
      expect(
        full.coverUrl,
        'https://covers.openlibrary.org/b/id/8739161-M.jpg',
      );
      expect(
        full.largeCoverUrl,
        'https://covers.openlibrary.org/b/id/8739161-L.jpg',
      );
      expect(full.pages, 418);

      final afterFailure = await source((request) async {
        if (isApple(request)) return json(429, {});
        return json(200, work);
      }).details(plain);
      expect(afterFailure.description, 'The Count comes to England.');

      final withoutApple = await source(
        (_) async => json(200, {'title': 'Dracula'}),
        withApple: false,
      ).details(plain);
      expect(sent, hasLength(1));
      expect(withoutApple.description, '');
      expect(withoutApple.coverUrl, isNull);
    });
  });

  test('details of an Apple pick take Open Library\'s year, author and '
      'page count by title and author; its own when Open Library has '
      'nothing', () async {
    final picked = book(
      'itunes:1436057399',
      'King Rat',
      creator: 'James Clavell',
      released: const Released(2015, 7, 28),
      description: 'Japanese POW camp Changi, Singapore.',
      coverUrl: artwork200,
      largeCoverUrl: artwork600,
      tags: ['Historical Fiction'],
    );
    final full = await source((request) async {
      expect(isOpenLibrary(request), isTrue, reason: '${request.url}');
      expect(request.url.path, '/search.json');
      expect(request.url.queryParameters['title'], 'King Rat');
      expect(request.url.queryParameters['author'], 'James Clavell');
      return json(200, {
        'docs': [kingRat],
      });
    }).details(picked);
    expect(sent, hasLength(1));
    expect(full.source, 'itunes:1436057399');
    expect(full.released, const Released(1962));
    expect(full.creator, 'James Clavell');
    expect(full.pages, 391);
    expect(full.description, 'Japanese POW camp Changi, Singapore.');
    expect(full.coverUrl, artwork200);
    expect(full.tags, ['Historical Fiction']);

    final alone = await source((_) async => json(200, {'docs': []}))
        .details(picked);
    expect(alone, picked);
    final down = await source((_) async => json(503, {})).details(picked);
    expect(down, picked);
  });

  test('one source failing is a partial answer with the other\'s hits; '
      'both failing fails', () async {
    Matcher partialWith(String? source, LookupFailure failure) =>
        isA<PartialLookupException>()
            .having((e) => e.failure, 'failure', failure)
            .having((e) => [for (final m in e.matches) m.source], 'matches', [
              ?source,
            ]);

    await expectLater(
      source((request) async {
        if (isOpenLibrary(request)) {
          return json(200, {
            'docs': [dracula],
          });
        }
        return json(503, {});
      }).search('dracula', type: MediaType.books),
      throwsA(partialWith('openlibrary:OL45804W', LookupFailure.other)),
    );
    // Open Library with nothing and Apple refusing is not "no matches".
    await expectLater(
      source((request) async {
        if (isOpenLibrary(request)) {
          return json(200, {'numFound': 0, 'docs': []});
        }
        return http.Response('Forbidden', 403);
      }).search('The Weight of Angels John Boyne', type: MediaType.books),
      throwsA(partialWith(null, LookupFailure.rateLimited)),
    );
    await expectLater(
      source((request) async {
        if (isOpenLibrary(request)) return json(503, {});
        return json(200, {
          'results': [weightOfAngels],
        });
      }).search('weight of angels', type: MediaType.books),
      throwsA(partialWith('itunes:6756269989', LookupFailure.other)),
    );

    await expectLater(
      source((request) async {
        if (isOpenLibrary(request)) return json(503, {});
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
      if (isOpenLibrary(request)) {
        return json(200, {
          'docs': [dracula],
        });
      }
      return json(503, {});
    }).match('Dracula', type: MediaType.books, creator: 'Bram Stoker');
    expect(found?.source, 'openlibrary:OL45804W');

    await expectLater(
      source((request) async {
        if (isOpenLibrary(request)) {
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

  test('the cover matcher finds a book only Apple has, and takes Apple\'s '
      'cover for a book both have', () async {
    final ol = source((request) async {
      if (isOpenLibrary(request)) {
        expect(request.url.queryParameters['title'], 'The Weight of Angels');
        expect(request.url.queryParameters['author'], 'John Boyne');
        return json(200, {'docs': []});
      }
      expect(
        request.url.queryParameters['term'],
        'The Weight of Angels John Boyne',
      );
      expect(request.url.queryParameters['limit'], '5');
      return json(200, {
        'results': [weightOfAngels],
      });
    });
    final hit = await ol.match(
      'The Weight of Angels',
      type: MediaType.books,
      year: 2025,
      creator: 'John Boyne',
    );
    expect(hit?.source, 'itunes:6756269989');
    expect(hit?.cacheCoverUrl, artwork600);

    final both =
        await source((request) async {
          if (isOpenLibrary(request)) {
            return json(200, {
              'docs': [kingRat],
            });
          }
          return json(200, {
            'results': [appleKingRat],
          });
        }).match(
          'King Rat',
          type: MediaType.books,
          year: 1962,
          creator: 'James Clavell',
        );
    expect(both?.source, 'openlibrary:OL2918736W');
    expect(both?.cacheCoverUrl, artwork600);
  });

  group('coverUrl for an Open Library id', () {
    final byKey = {
      'docs': [
        {
          'key': '/works/OL2918736W',
          'title': 'King Rat',
          'author_name': ['James Clavell'],
          'cover_i': 13268339,
        },
      ],
    };

    test(
      'asks the index for the work, then Apple by title and author',
      () async {
        final url = await source((request) async {
          if (isOpenLibrary(request)) {
            expect(request.url.path, '/search.json');
            expect(request.url.queryParameters['q'], 'key:/works/OL2918736W');
            expect(request.url.queryParameters['limit'], '1');
            return json(200, byKey);
          }
          expect(request.url.queryParameters['term'], 'King Rat James Clavell');
          return json(200, {
            'results': [appleKingRat],
          });
        }).coverUrl('openlibrary:OL2918736W', type: MediaType.books);
        expect(url, artwork600);
        expect(sent, hasLength(2));
      },
    );

    test(
      'falls back to Open Library\'s cover when Apple has none or fails',
      () async {
        for (final apple in [
          json(200, {'results': []}),
          json(503, {}),
        ]) {
          final url = await source((request) async {
            if (isOpenLibrary(request)) return json(200, byKey);
            return apple;
          }).coverUrl('openlibrary:OL2918736W', type: MediaType.books);
          expect(url, 'https://covers.openlibrary.org/b/id/13268339-L.jpg');
          expect(sent, hasLength(2));
        }
      },
    );

    test('reads the work when the index lacks it, and asks Apple by title '
        'alone when the work has no cover', () async {
      final url = await source((request) async {
        if (isApple(request)) fail('asked Apple');
        if (request.url.path == '/search.json') {
          return json(200, {'docs': []});
        }
        expect(request.url.path, '/works/OL45804W.json');
        return json(200, {
          'title': 'Dracula',
          'covers': [8739161],
        });
      }).coverUrl('openlibrary:OL45804W', type: MediaType.books);
      expect(url, 'https://covers.openlibrary.org/b/id/8739161-L.jpg');

      final viaApple = await source((request) async {
        if (isApple(request)) {
          expect(request.url.queryParameters['term'], 'Dracula');
          return json(200, {
            'results': [
              ebook(1, 'Dracula', author: 'Bram Stoker', art: artwork),
            ],
          });
        }
        if (request.url.path == '/search.json') {
          return json(200, {'docs': []});
        }
        return json(200, {'title': 'Dracula'});
      }).coverUrl('openlibrary:OL45804W', type: MediaType.books);
      expect(viaApple, artwork600);

      expect(
        await source((request) async {
          if (request.url.path == '/search.json') {
            return json(200, {'docs': []});
          }
          return json(200, {});
        }).coverUrl('openlibrary:OL45804W', type: MediaType.books),
        isNull,
      );
      expect(
        source((_) async => json(200, {}))
            .coverUrl('igdb:1', type: MediaType.books),
        throwsA(isA<LookupException>()),
      );
    });
  });

  test('coverUrl for an Apple id reads its record, else Open Library by '
      'title and author', () async {
    expect(
      await source((request) async {
        expect(request.url.path, '/lookup');
        expect(request.url.queryParameters['id'], '6756269989');
        return json(200, {
          'results': [weightOfAngels],
        });
      }).coverUrl('itunes:6756269989', type: MediaType.books),
      artwork600,
    );
    expect(
      await source((request) async {
        if (isApple(request)) {
          return json(200, {
            'results': [
              ebook(6756269989, 'The Weight of Angels', author: 'John Boyne'),
            ],
          });
        }
        switch (request.url.path) {
          case '/search.json':
            expect(
              request.url.queryParameters['title'],
              'The Weight of Angels',
            );
            expect(request.url.queryParameters['author'], 'John Boyne');
            return json(200, {
              'docs': [
                {
                  'key': '/works/OL99W',
                  'title': 'The Weight of Angels',
                  'author_name': ['John Boyne'],
                },
              ],
            });
          case '/works/OL99W.json':
            return json(200, {
              'covers': [42],
            });
        }
        fail('unexpected ${request.url}');
      }).coverUrl('itunes:6756269989', type: MediaType.books),
      'https://covers.openlibrary.org/b/id/42-L.jpg',
    );
    expect(
      await source((_) async => json(200, {'results': []}))
          .coverUrl('itunes:1', type: MediaType.books),
      isNull,
    );
  });

  group('a Google Books id from before Apple Books', () {
    Map<String, Object?> record({Map<String, String>? links}) => {
      'id': 'eOTEEQAAQBAJ',
      'volumeInfo': {
        'title': 'The Weight of Angels',
        'authors': ['John Boyne'],
        'publishedDate': '2026',
        'imageLinks': ?links,
      },
    };

    test(
      'coverUrl reads the volume, else asks Apple, else Open Library',
      () async {
        expect(
          await source((request) async {
            expect(request.url.path, '/books/v1/volumes/eOTEEQAAQBAJ');
            expect(request.url.queryParameters['key'], 'g-key');
            return json(
              200,
              record(
                links: {
                  'thumbnail': 'http://g/t.jpg',
                  'medium': 'http://g/m.jpg&edge=curl',
                },
              ),
            );
          }).coverUrl('googlebooks:eOTEEQAAQBAJ', type: MediaType.books),
          'https://g/m.jpg',
        );
        expect(
          await source((request) async {
            if (isGoogle(request)) return json(200, record());
            expect(isApple(request), isTrue);
            return json(200, {
              'results': [weightOfAngels],
            });
          }).coverUrl('googlebooks:eOTEEQAAQBAJ', type: MediaType.books),
          artwork600,
        );
        expect(
          await source((request) async {
            if (isGoogle(request)) return json(200, record());
            if (isApple(request)) return json(200, {'results': []});
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
            fail('unexpected ${request.url}');
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

    test('details read the volume, then Apple and Open Library', () async {
      final full =
          await source((request) async {
            if (isGoogle(request)) {
              return json(200, record(links: {'thumbnail': 'http://g/t.jpg'}));
            }
            if (isApple(request)) {
              return json(200, {
                'results': [weightOfAngels],
              });
            }
            expect(request.url.path, '/search.json');
            return json(200, {
              'docs': [
                {
                  'key': '/works/OL99W',
                  'title': 'The Weight of Angels',
                  'author_name': ['John Boyne'],
                  'first_publish_year': 2026,
                  'number_of_pages_median': 320,
                },
              ],
            });
          }).details(
            book(
              'googlebooks:eOTEEQAAQBAJ',
              'The Weight of Angels',
              creator: 'John Boyne',
            ),
          );
      expect(sent, hasLength(3));
      expect(full.source, 'googlebooks:eOTEEQAAQBAJ');
      expect(full.description, 'A novel.');
      expect(full.coverUrl, artwork200);
      expect(full.released, const Released(2026));
      expect(full.pages, 320);
    });
  });

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

  group('series', () {
    Map<String, Object?> volume(String id, String title, int year) => {
      'key': '/works/$id',
      'title': title,
      'author_name': ['Kentaro Miura'],
      'first_publish_year': year,
      'publish_year': [year],
    };
    final berserkIndex = {
      'docs': [
        volume('OL2W', 'Berserk, Vol. 2', 1991),
        volume('OL1W', 'Berserk, Vol. 1', 1990),
        volume('OL1bW', 'Berserk, Vol. 1', 2003),
        volume('OL43W', 'Berserk, Vol. 43', 2025),
        volume('OLxW', 'Berserk Official Guidebook', 2017),
        volume('OLyW', 'Gigantomakhia, Vol. 1', 2014),
      ],
    };

    test('a pick without Wikidata reads the volume from the title', () async {
      final ol = source((request) async {
        if (isApple(request)) return json(200, {'results': []});
        return json(200, {'description': 'Guts.'});
      });
      final full = await ol.details(
        book('openlibrary:OL43W', 'Berserk, Vol. 43', creator: 'Kentaro Miura'),
      );
      expect(full.series, const Series(name: 'Berserk', number: 43));
      expect(
        (await ol.details(book('openlibrary:OL1W', 'Dracula'))).series,
        isNull,
      );
    });

    test(
      'a pick asks Wikidata first; its series wins over the title',
      () async {
        sent = [];
        final client = MockClient((request) async {
          sent.add(request);
          if (request.url.host == 'www.wikidata.org') {
            return json(200, {
              'search': [
                {'id': 'Q1'},
              ],
            });
          }
          if (request.url.host == 'query.wikidata.org') {
            Map<String, Object?> cell(String v, [String t = 'literal']) => {
              'type': t,
              'value': v,
            };
            return json(200, {
              'results': {
                'bindings': [
                  {
                    'book': cell('http://www.wikidata.org/entity/Q1', 'uri'),
                    'authorLabel': cell('Kentaro Miura'),
                    'series': cell('http://www.wikidata.org/entity/Q9', 'uri'),
                    'seriesLabel': cell('Berserk (manga)'),
                    'ordinal': cell('43'),
                    'part': cell('http://www.wikidata.org/entity/Q1', 'uri'),
                    'partLabel': cell('Berserk 43'),
                    'partOrdinal': cell('43'),
                  },
                ],
              },
            });
          }
          if (isApple(request)) return json(200, {'results': []});
          return json(200, {'description': 'Guts.'});
        });
        final ol = OpenLibrarySource(
          client,
          apple: ITunesBooks(client, minGap: Duration.zero),
          wikidata: WikidataSeries(client),
        );
        final full = await ol.details(
          book(
            'openlibrary:OL43W',
            'Berserk, Vol. 43',
            creator: 'Kentaro Miura',
          ),
        );
        expect(full.series, const Series(name: 'Berserk (manga)', number: 43));
        expect(sent.any((r) => r.url.host == 'www.wikidata.org'), isTrue);

        // Wikidata not answering leaves the series to the title.
        final down = OpenLibrarySource(
          MockClient((request) async {
            if (request.url.host.contains('wikidata')) {
              throw const SocketException('down');
            }
            if (isApple(request)) return json(200, {'results': []});
            return json(200, {'description': 'Guts.'});
          }),
          wikidata: WikidataSeries(
            MockClient((_) async => throw const SocketException('down')),
          ),
        );
        final fallback = await down.details(
          book('openlibrary:OL43W', 'Berserk, Vol. 43'),
        );
        expect(fallback.series, const Series(name: 'Berserk', number: 43));
      },
    );

    test(
      'seriesParts lists the volumes by name and author, one per number',
      () async {
        final ol = source((request) async {
          if (isApple(request)) return json(200, {'results': []});
          final q = request.url.queryParameters;
          if (q['q'] == 'key:/works/OL43W') {
            return json(200, {
              'docs': [volume('OL43W', 'Berserk, Vol. 43', 2025)],
            });
          }
          if (q['title'] == 'Berserk') return json(200, berserkIndex);
          return json(200, {'docs': []});
        });
        final parts = await ol.seriesParts('openlibrary:OL43W');
        expect(parts!.name, 'Berserk');
        expect(parts.parts.map((p) => (p.number, p.title, p.year, p.source)), [
          (1, 'Berserk, Vol. 1', 1990, 'openlibrary:OL1W'),
          (2, 'Berserk, Vol. 2', 1991, 'openlibrary:OL2W'),
          (43, 'Berserk, Vol. 43', 2025, 'openlibrary:OL43W'),
        ]);
        final search = sent.lastWhere(
          (r) => r.url.queryParameters['title'] == 'Berserk',
        );
        expect(search.url.queryParameters['author'], 'Kentaro Miura');
        expect(search.url.queryParameters['limit'], '100');
      },
    );

    test('a volume still to come takes Apple\'s artwork as its cover; one out '
        'keeps Open Library\'s', () async {
      seasonClock = () => DateTime(2026, 10, 31);
      addTearDown(() => seasonClock = DateTime.now);
      final ol = source((request) async {
        if (isApple(request)) {
          final term = request.url.queryParameters['term'];
          return json(200, {
            'results': [
              if (term!.contains('Vol. 44'))
                ebook(
                  44,
                  'Berserk, Vol. 44',
                  author: 'Kentaro Miura',
                  art: artwork,
                ),
            ],
          });
        }
        final q = request.url.queryParameters;
        if (q['q'] == 'key:/works/OL43W') {
          return json(200, {
            'docs': [volume('OL43W', 'Berserk, Vol. 43', 2025)],
          });
        }
        if (q['title'] == 'Berserk') {
          return json(200, {
            'docs': [
              {...volume('OL43W', 'Berserk, Vol. 43', 2025), 'cover_i': 43},
              {...volume('OL44W', 'Berserk, Vol. 44', 2027), 'cover_i': 44},
            ],
          });
        }
        return json(200, {'docs': []});
      });
      final parts = await ol.seriesParts('openlibrary:OL43W');
      expect(parts!.parts.map((p) => (p.number, p.cover)), [
        (43, 'https://covers.openlibrary.org/b/id/43-L.jpg'),
        (44, artwork600),
      ]);
      // Apple is asked for the volume still to come only.
      expect(sent.where(isApple).map((r) => r.url.queryParameters['term']), [
        'Berserk, Vol. 44 Kentaro Miura',
      ]);
    });

    test('seriesParts takes the series name the entry carries', () async {
      final ol = source((request) async {
        if (isApple(request)) return json(200, {'results': []});
        final q = request.url.queryParameters;
        if (q['q'] == 'key:/works/OL5W') {
          return json(200, {
            'docs': [volume('OL5W', 'The Golden Age Arc', 2012)],
          });
        }
        if (q['title'] == 'Berserk') return json(200, berserkIndex);
        return json(200, {'docs': []});
      });
      expect(await ol.seriesParts('openlibrary:OL5W'), isNull);
      final named = await ol.seriesParts('openlibrary:OL5W', name: 'Berserk');
      expect(named!.parts, hasLength(3));
    });
  });

  group('cover choices (Add / edit entry › Pick a cover)', () {
    /// Shōgun as Open Library lists it: the best edition's cover, format and
    /// date; a second work whose cover is the work's own.
    final shogun = {
      'key': '/works/OL2918756W',
      'title': 'Shōgun',
      'author_name': ['James Clavell'],
      'first_publish_year': 1975,
      'cover_i': 2394441,
      'editions': {
        'docs': [
          {
            'key': '/books/OL25881240M',
            'cover_i': 7386793,
            'format': ['Hardcover'],
            'publish_date': ['1980'],
          },
        ],
      },
    };
    final shogunOther = {
      'key': '/works/OL2918755W',
      'title': 'Shōgun',
      'author_name': ['James Clavell'],
      'first_publish_year': 1975,
      'cover_i': 5335340,
      'editions': {
        'docs': [
          {
            'key': '/books/OL22363633M',
            'publish_date': ['1976'],
          },
        ],
      },
    };

    test('every edition with a cover, each with the id of its image', () async {
      final ol = source((request) async {
        if (isApple(request)) {
          return json(200, {
            'results': [
              ebook(
                1,
                'Shōgun, Part One',
                author: 'James Clavell',
                date: '2019-01-01T00:00:00Z',
                art: '$artwork?a',
              ),
              ebook(
                2,
                'Shōgun (TV Tie-in)',
                author: 'James Clavell',
                date: '2024-02-01T00:00:00Z',
                art: '$artwork?b',
              ),
              // Another book by him, and the same title by someone else.
              ebook(3, 'Tai-Pan', author: 'James Clavell', art: '$artwork?c'),
              ebook(4, 'Shōgun', author: 'Someone Else', art: '$artwork?d'),
              ebook(5, 'Shōgun', author: 'James Clavell'),
            ],
          });
        }
        return json(200, {
          'docs': [shogun, shogunOther],
        });
      });
      final choices = await ol.coverChoices(
        'Shōgun, Part One',
        type: MediaType.books,
        creator: 'James Clavell',
      );
      final olRequest = sent.firstWhere(isOpenLibrary);
      expect(olRequest.url.queryParameters['title'], 'Shōgun');
      expect(olRequest.url.queryParameters['author'], 'James Clavell');
      expect(
        olRequest.url.queryParameters['fields'],
        allOf(contains('editions.key'), contains('editions.format')),
      );
      expect(
        [
          for (final c in choices)
            (c.coverFrom, c.editionYear ?? c.released?.year, c.edition),
        ],
        [
          ('openlibrary:OL25881240M', 1980, 'Hardcover'),
          ('itunes:1', 2019, 'Ebook'),
          ('openlibrary:OL2918755W', 1975, null),
          ('itunes:2', 2024, 'TV tie-in'),
        ],
      );
      expect(
        choices.first.cacheCoverUrl,
        'https://covers.openlibrary.org/b/id/7386793-L.jpg',
      );
    });

    test('one source not answering still gives the other\'s covers', () async {
      final ol = source((request) async {
        if (isApple(request)) return json(503, {});
        return json(200, {
          'docs': [shogun],
        });
      });
      await expectLater(
        ol.coverChoices('Shōgun', type: MediaType.books),
        throwsA(
          isA<PartialLookupException>().having(
            (e) => e.matches.single.coverFrom,
            'cover',
            'openlibrary:OL25881240M',
          ),
        ),
      );
    });

    test('a picked cover is that image, never another source\'s', () async {
      final ol = source((request) async {
        if (isApple(request)) {
          return json(200, {
            'results': [ebook(1, 'Shōgun', art: artwork)],
          });
        }
        return json(200, {
          'covers': [5335340],
        });
      });
      expect(
        await ol.pickedCoverUrl(
          'openlibrary:OL25881240M',
          type: MediaType.books,
        ),
        'https://covers.openlibrary.org/b/olid/OL25881240M-L.jpg?default=false',
      );
      expect(sent, isEmpty);
      expect(
        await ol.pickedCoverUrl(
          'openlibrary:OL2918755W',
          type: MediaType.books,
        ),
        'https://covers.openlibrary.org/b/id/5335340-L.jpg',
      );
      expect(sent.single.url.path, '/works/OL2918755W.json');
      expect(
        await ol.pickedCoverUrl('itunes:1', type: MediaType.books),
        artwork600,
      );
    });
  });

  group('followed authors', () {
    test('finds the author key and lists the newest works, each with Apple\'s '
        'cover and description when Apple knows it', () async {
      final ol = source((request) async {
        if (isApple(request)) {
          final term = request.url.queryParameters['term'];
          return json(200, {
            'results': [
              if (term!.startsWith('Never Flinch'))
                ebook(
                  7,
                  'Never Flinch',
                  author: 'Stephen King',
                  date: '2027-05-27T07:00:00Z',
                  description: 'Holly Gibney, <i>again</i>.',
                  art: artwork,
                ),
            ],
          });
        }
        if (request.url.path == '/search/authors.json') {
          expect(request.url.queryParameters['q'], 'Stephen King');
          return json(200, {
            'docs': [
              {'key': 'OL19981A', 'name': 'Stephen King', 'work_count': 900},
              {'key': 'OL1A', 'name': 'Stephen King Jr.'},
            ],
          });
        }
        expect(request.url.path, '/search.json');
        expect(request.url.queryParameters['author_key'], 'OL19981A');
        expect(request.url.queryParameters['sort'], 'new');
        return json(200, {
          'docs': [
            {
              'key': '/works/OL1W',
              'title': 'Never Flinch',
              'author_name': ['Stephen King'],
              'first_publish_year': 2027,
            },
            {
              'key': '/works/OL2W',
              'title': 'This Year',
              'author_name': ['Stephen King'],
              'first_publish_year': 2026,
              'cover_i': 2,
            },
            {
              'key': '/works/OL3W',
              'title': 'It',
              'author_name': ['Stephen King'],
              'first_publish_year': 1986,
            },
          ],
        });
      });
      expect(await ol.findCreator(FollowKind.authors, 'Stephen King'), (
        providerId: 'openlibrary:author:OL19981A',
        inactive: null,
      ));
      final works = await ol.creatorReleases(
        'openlibrary:author:OL19981A',
        FollowKind.authors,
        today: DateTime(2026, 10, 30),
      );
      expect(works.map((m) => m.title), ['Never Flinch', 'This Year']);
      expect(works.first.source, 'openlibrary:OL1W');
      // Open Library's year stays; Apple's cover and description come in.
      expect(works.first.released, const Released(2027));
      expect(works.first.cacheCoverUrl, artwork600);
      expect(works.first.description, 'Holly Gibney, again.');
      // A book Apple does not know keeps Open Library's cover.
      expect(
        works[1].cacheCoverUrl,
        'https://covers.openlibrary.org/b/id/2-L.jpg',
      );
      // Apple asked once per release found, not for the old books.
      expect(sent.where(isApple).map((r) => r.url.queryParameters['term']), [
        'Never Flinch Stephen King',
        'This Year Stephen King',
      ]);
    });
  });
}
