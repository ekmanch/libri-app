import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/wikidata_series.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/upcoming/creator_status.dart';

void main() {
  late List<http.Request> sent;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, Object?> cell(String value, {String type = 'literal'}) => {
    'type': type,
    'value': value,
  };

  Map<String, Object?> item(String id) =>
      cell('http://www.wikidata.org/entity/$id', type: 'uri');

  /// A row of the series query: the candidate book, its author, its
  /// series and ordinal, and one part of the series.
  Map<String, Object?> row({
    required String book,
    String? author,
    required String series,
    String seriesLabel = 'The Lord of the Rings',
    String? ordinal,
    required String part,
    required String partLabel,
    String? partOrdinal,
    String? date,
    String? partOf,
    String? partAuthor,
  }) => {
    'book': item(book),
    if (author != null) 'authorLabel': cell(author),
    'series': item(series),
    'seriesLabel': cell(seriesLabel),
    if (ordinal != null) 'ordinal': cell(ordinal),
    'part': item(part),
    'partLabel': cell(partLabel),
    if (partOrdinal != null) 'partOrdinal': cell(partOrdinal),
    if (date != null) 'date': cell('${date}T00:00:00Z'),
    if (partOf != null) 'partOf': item(partOf),
    if (partAuthor != null) 'partAuthorLabel': cell(partAuthor),
  };

  final lotr = [
    for (final (part, label, ordinal, date) in [
      ('Q208088', 'The Fellowship of the Ring', '1', '1954-07-29'),
      ('Q208133', 'The Two Towers', '2', '1954-11-11'),
      ('Q208137', 'The Return of the King', '3', '1955-10-20'),
    ])
      row(
        book: 'Q208088',
        author: 'J. R. R. Tolkien',
        series: 'Q15228',
        ordinal: '1',
        part: part,
        partLabel: label,
        partOrdinal: ordinal,
        date: date,
      ),
  ];

  WikidataSeries source({
    List<Map<String, Object?>> search = const [],
    List<Map<String, Object?>> rows = const [],
    int sparqlStatus = 200,
  }) {
    sent = [];
    return WikidataSeries(
      MockClient((request) async {
        sent.add(request);
        if (request.url.host == 'www.wikidata.org') {
          return json(200, {'search': search});
        }
        return json(sparqlStatus, {
          'results': {'bindings': rows},
        });
      }),
    );
  }

  test('finds the book by title, then its series and parts in order', () async {
    final wikidata = source(
      search: [
        {'id': 'Q2048', 'label': 'a film'},
        {'id': 'Q208088', 'label': 'The Fellowship of the Ring'},
      ],
      rows: [
        // The film candidate is in no series, so it has no rows.
        ...lotr.reversed,
      ],
    );
    final found = await wikidata.seriesOf(
      'The fellowship of the ring',
      'J.R.R. Tolkien',
    );
    expect(sent[0].url.queryParameters['action'], 'wbsearchentities');
    expect(sent[0].url.queryParameters['search'], 'The fellowship of the ring');
    expect(sent[1].url.host, 'query.wikidata.org');
    expect(sent[1].url.queryParameters['query'], contains('wd:Q208088'));
    expect(sent[1].url.queryParameters['query'], contains('wd:Q2048'));
    expect(found!.number, 1);
    expect(found.parts.name, 'The Lord of the Rings');
    expect(found.parts.parts.map((p) => (p.number, p.title, p.year)), [
      (1, 'The Fellowship of the Ring', 1954),
      (2, 'The Two Towers', 1954),
      (3, 'The Return of the King', 1955),
    ]);
    expect(found.parts.parts.first.source, 'wikidata:Q208088');
  });

  test('a candidate by another author is passed over', () async {
    final wikidata = source(
      search: [
        {'id': 'Q1'},
        {'id': 'Q208088'},
      ],
      rows: [
        row(
          book: 'Q1',
          author: 'Someone Else',
          series: 'Q9',
          seriesLabel: 'Other',
          part: 'Q1',
          partLabel: 'Same title',
        ),
        ...lotr,
      ],
    );
    final found = await wikidata.seriesOf(
      'The Fellowship of the Ring',
      'Tolkien',
    );
    expect(found!.parts.name, 'The Lord of the Rings');
    // Without an author to go by, the first candidate in a series wins.
    final any = await source(
      search: [
        {'id': 'Q1'},
        {'id': 'Q208088'},
      ],
      rows: [
        row(
          book: 'Q1',
          author: 'Someone Else',
          series: 'Q9',
          seriesLabel: 'Other',
          part: 'Q1',
          partLabel: 'Same title',
        ),
        ...lotr,
      ],
    ).seriesOf('The Fellowship of the Ring', null);
    expect(any!.parts.name, 'Other');
  });

  test('no candidates, or none in a series, is null', () async {
    expect(await source().seriesOf('Nothing', null), isNull);
    expect(
      await source(
        search: [
          {'id': 'Q5'},
        ],
      ).seriesOf('Alone', null),
      isNull,
    );
  });

  test(
    'a title that names nothing is asked again without its tacked-on note',
    () async {
      var calls = 0;
      sent = [];
      final wikidata = WikidataSeries(
        MockClient((request) async {
          sent.add(request);
          if (request.url.host == 'www.wikidata.org') {
            calls++;
            final query = request.url.queryParameters['search'];
            return json(200, {
              'search': query == 'Tai-Pan'
                  ? [
                      {'id': 'Q2734297', 'label': 'Tai-Pan'},
                    ]
                  : [],
            });
          }
          return json(200, {
            'results': {
              'bindings': [
                row(
                  book: 'Q2734297',
                  author: 'James Clavell',
                  series: 'Q2866449',
                  seriesLabel: 'The Asian Saga',
                  part: 'Q2734297',
                  partLabel: 'Tai-Pan',
                  date: '1966-01-01',
                ),
              ],
            },
          });
        }),
      );
      final found = await wikidata.seriesOf(
        'Tai-Pan (Asian Saga',
        'James Clavell',
      );
      expect(calls, 2);
      expect(sent.last.url.queryParameters['query'], contains('wd:Q2734297'));
      expect(found!.parts.name, 'The Asian Saga');
      expect(found.number, isNull);
      // A title with nothing tacked on is asked once.
      expect(await source().seriesOf('Dracula', 'Bram Stoker'), isNull);
      expect(sent.length, 1);
    },
  );

  test('coreTitle cuts a parenthesis, a colon or a part before it', () {
    expect(WikidataSeries.coreTitle('Tai-Pan (Asian Saga'), 'Tai-Pan');
    expect(
      WikidataSeries.coreTitle('Shōgun, Part One (The Asian Saga)'),
      'Shōgun',
    );
    expect(
      WikidataSeries.coreTitle(
        'The Fellowship of the Ring: Being the First Part of The Lord of the Rings',
      ),
      'The Fellowship of the Ring',
    );
    expect(WikidataSeries.coreTitle('Berserk, Vol. 43'), 'Berserk');
    expect(WikidataSeries.coreTitle('Dune [Deluxe Edition]'), 'Dune');
    expect(WikidataSeries.coreTitle('Dracula'), 'Dracula');
    expect(WikidataSeries.coreTitle('(untitled)'), '(untitled)');
  });

  test('parts without an ordinal come after the rest, by date', () async {
    // Mostly unnumbered, as Wikidata has the Asian Saga, so none is dropped.
    Map<String, Object?> saga(
      String part,
      String label, {
      String? ordinal,
      required String date,
    }) => row(
      book: 'Q1',
      series: 'Q3562203',
      seriesLabel: 'The Asian Saga',
      part: part,
      partLabel: label,
      partOrdinal: ordinal,
      date: date,
    );
    final wikidata = source(
      search: [
        {'id': 'Q1'},
      ],
      rows: [
        saga('Q2', 'Noble House', date: '1981-01-01'),
        saga('Q3', 'Whirlwind', ordinal: '6', date: '1986-01-01'),
        saga('Q4', 'King Rat', date: '1962-01-01'),
        saga('Q1', 'Shōgun', date: '1975-01-01'),
      ],
    );
    final found = await wikidata.seriesOf('Shōgun', null);
    expect(found!.parts.parts.map((p) => p.title), [
      'Whirlwind',
      'King Rat',
      'Shōgun',
      'Noble House',
    ]);
  });

  test('the parts of a part, undated unnumbered parts and, in a numbered '
      'series, the unnumbered rest are kept as extras (Library › Book series '
      'after the automatic rules)', () async {
    Map<String, Object?> part(
      String id,
      String label, {
      String? ordinal,
      String? date,
      String? partOf,
    }) => row(
      book: 'Q208088',
      author: 'J. R. R. Tolkien',
      series: 'Q15228',
      ordinal: '1',
      part: id,
      partLabel: label,
      partOrdinal: ordinal,
      date: date,
      partOf: partOf,
      partAuthor: 'J. R. R. Tolkien',
    );
    final wikidata = source(
      search: [
        {'id': 'Q208088'},
      ],
      rows: [
        part(
          'Q208088',
          'The Fellowship of the Ring',
          ordinal: '1',
          date: '1954-07-29',
        ),
        part('Q332139', 'Concerning Hobbits'),
        part('Q208133', 'The Two Towers', ordinal: '2', date: '1954-11-11'),
        part(
          'Q208137',
          'The Return of the King',
          ordinal: '3',
          date: '1955-10-20',
        ),
        part(
          'Q334335',
          'Appendices of The Lord of the Rings',
          date: '1954-07-29',
        ),
        part(
          'Q133892392',
          'The First Journey',
          ordinal: '1',
          partOf: 'Q208088',
        ),
        part(
          'Q133892413',
          'The Journey of the Nine Companions',
          ordinal: '2',
          partOf: 'Q208088',
        ),
        part(
          'Q133892737',
          'The End of the Third Age',
          ordinal: '6',
          partOf: 'Q208137',
        ),
      ],
    );
    final found = await wikidata.seriesOf('The Fellowship of the Ring', null);
    final parts = found!.parts.parts;
    expect(parts, hasLength(8));
    expect(
      [
        for (final p in parts)
          if (!p.extra) p.title,
      ],
      [
        'The Fellowship of the Ring',
        'The Two Towers',
        'The Return of the King',
      ],
    );
    expect(parts.first.creator, 'J. R. R. Tolkien');
  });

  test('extraParts: a part of something outside the series is no extra', () {
    WikidataPart part(
      String id, {
      int? number,
      int? year,
      Set<String> partOf = const {},
    }) => (
      id: id,
      title: id,
      number: number,
      year: year,
      released: null,
      partOf: partOf,
      authors: const [],
    );
    expect(
      WikidataSeries.extraParts([
        part('A', number: 1, year: 2000, partOf: {'Q-elsewhere'}),
        part('B', number: 2, year: 2001),
      ]),
      isEmpty,
    );
    // Half numbered is not most: the unnumbered stay.
    expect(
      WikidataSeries.extraParts([part('A', number: 1), part('B', year: 2001)]),
      isEmpty,
    );
  });

  test('a part by other authors says who, each author once', () async {
    final wikidata = source(
      search: [
        {'id': 'Q1'},
      ],
      rows: [
        for (final author in [
          'Brian Herbert',
          'Kevin J. Anderson',
          'Brian Herbert',
        ])
          row(
            book: 'Q1',
            series: 'Q6095696',
            seriesLabel: 'Dune',
            part: 'Q7',
            partLabel: 'Hunters of Dune',
            partOrdinal: '7',
            date: '2006-08-08',
            partAuthor: author,
          ),
      ],
    );
    final found = await wikidata.seriesOf('Dune', null);
    expect(
      found!.parts.parts.single.creator,
      'Brian Herbert, Kevin J. Anderson',
    );
  });

  test('authors match on a surname, case aside', () {
    expect(
      WikidataSeries.sameAuthor('J.R.R. Tolkien', ['J. R. R. Tolkien']),
      isTrue,
    );
    expect(
      WikidataSeries.sameAuthor('Kentaro Miura', ['MIURA Kentarō']),
      isTrue,
    );
    expect(
      WikidataSeries.sameAuthor('Stephen King', ['Peter Jackson']),
      isFalse,
    );
    expect(WikidataSeries.sameAuthor(null, ['Anyone']), isTrue);
    expect(WikidataSeries.sameAuthor('Stephen King', const []), isFalse);
  });

  test('failures are lookup exceptions', () async {
    await expectLater(
      source(
        search: [
          {'id': 'Q1'},
        ],
        sparqlStatus: 500,
      ).seriesOf('x', null),
      throwsA(isA<LookupException>()),
    );
    final offline = WikidataSeries(
      MockClient((_) async => throw const SocketException('down')),
    );
    await expectLater(
      offline.seriesOf('x', null),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.offline,
        ),
      ),
    );
  });

  group('who is no longer active', () {
    Map<String, Object?> who(
      String name,
      String id, {
      String cls = 'Q5',
      String? death,
      String? dissolved,
    }) => {
      'name': cell(name),
      'item': item(id),
      'class': item(cls),
      if (death != null) 'death': cell(death),
      if (dissolved != null) 'dissolved': cell(dissolved),
    };

    test('asks one query for every name and reads the dates', () async {
      sent = [];
      final wikidata = WikidataSeries(
        MockClient((request) async {
          sent.add(request);
          return json(200, {
            'results': {
              'bindings': [
                who('J. R. R. Tolkien', 'Q892', death: '1973-09-02T00:00:00Z'),
                who('Stephen King', 'Q39829'),
                // A living namesake keeps the author active.
                who('John Smith', 'Q1', death: '1900-01-01T00:00:00Z'),
                who('John Smith', 'Q2'),
                // Everyone of that name is dead: the latest year.
                who('Jane Doe', 'Q3', death: '1950-01-01T00:00:00Z'),
                who('Jane Doe', 'Q4', death: '1980-01-01T00:00:00Z'),
              ],
            },
          });
        }),
      );
      final gone = await wikidata.inactiveOf(FollowKind.authors, [
        'J. R. R. Tolkien',
        'Stephen King',
        'John Smith',
        'Jane Doe',
        'Unknown Person',
      ]);
      expect(gone, {
        'J. R. R. Tolkien': const Inactive(InactiveReason.died, year: 1973),
        'Jane Doe': const Inactive(InactiveReason.died, year: 1980),
      });
      final query = sent.single.url.queryParameters['query']!;
      expect(query, contains('"J. R. R. Tolkien"@en'));
      expect(query, contains('wd:Q5'));
      expect(query, contains('wdt:P570'));
      expect(query, contains('wdt:P576'));
    });

    test('a band disbanded, a studio dissolved', () async {
      final rows = [
        who(
          'Creedence Clearwater Revival',
          'Q10',
          cls: 'Q215380',
          dissolved: '1972-10-16T00:00:00Z',
        ),
        who(
          'Telltale Games',
          'Q11',
          cls: 'Q210167',
          dissolved: '2018-10-11T00:00:00Z',
        ),
      ];
      // Only the names asked for come back, as Wikidata would answer.
      final wikidata = WikidataSeries(
        MockClient((request) async {
          final query = request.url.queryParameters['query'] ?? '';
          return json(200, {
            'results': {
              'bindings': [
                for (final row in rows)
                  if (query.contains((row['name'] as Map)['value'] as String))
                    row,
              ],
            },
          });
        }),
      );
      expect(
        await wikidata.inactiveOf(FollowKind.artists, [
          'Creedence Clearwater Revival',
        ]),
        {
          'Creedence Clearwater Revival': const Inactive(
            InactiveReason.disbanded,
            year: 1972,
          ),
        },
      );
      expect(
        await wikidata.inactiveOf(FollowKind.studios, ['Telltale Games']),
        {
          'Telltale Games': const Inactive(
            InactiveReason.dissolved,
            year: 2018,
          ),
        },
      );
      expect(await wikidata.inactiveOf(FollowKind.shows, ['x']), isEmpty);
    });
  });
}
