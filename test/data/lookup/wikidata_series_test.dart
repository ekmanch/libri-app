import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/wikidata_series.dart';

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
    final wikidata = source(
      search: [
        {'id': 'Q208088'},
      ],
      rows: [
        ...lotr,
        row(
          book: 'Q208088',
          author: 'J. R. R. Tolkien',
          series: 'Q15228',
          ordinal: '1',
          part: 'Q77',
          partLabel: 'A later companion',
          date: '1980-01-01',
        ),
        row(
          book: 'Q208088',
          author: 'J. R. R. Tolkien',
          series: 'Q15228',
          ordinal: '1',
          part: 'Q78',
          partLabel: 'An early companion',
          date: '1960-01-01',
        ),
      ],
    );
    final found = await wikidata.seriesOf('The Fellowship of the Ring', null);
    expect(found!.parts.parts.map((p) => p.title).toList().sublist(3), [
      'An early companion',
      'A later companion',
    ]);
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
}
