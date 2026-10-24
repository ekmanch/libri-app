import 'package:http/http.dart' as http;

import '../net/http_transport.dart';
import 'http_lookup_source.dart';
import 'lookup_source.dart';
import 'rate_limiter.dart';

/// Which series a book belongs to, and its number, from Wikidata (Library ›
/// Book in a long series). No key. The book is found by its title with the
/// entity search (case does not matter there, and Open Library titles are
/// often in sentence case), then one SPARQL query reads its "part of the
/// series" statement (P179) with the series ordinal (P1545), and every other
/// part of that series with its ordinal and publication date (P577). The
/// author (P50) tells the book from a film or a game of the same name.
/// The parts are cleaned up as they come in ([cleanParts]).
class WikidataSeries with LookupHttp {
  WikidataSeries(
    this.client, {
    Uri? apiUrl,
    Uri? sparqlUrl,
    this.timeout = defaultHttpTimeout,
    this.userAgent = 'Libri',
  }) : _apiUrl = apiUrl ?? Uri.https('www.wikidata.org', '/w/api.php'),
       _sparqlUrl = sparqlUrl ?? Uri.https('query.wikidata.org', '/sparql'),
       limiter = RateLimiter(const Duration(seconds: 1));

  @override
  final http.Client client;
  @override
  final Duration timeout;
  @override
  final String userAgent;
  @override
  final RateLimiter limiter;

  final Uri _apiUrl;
  final Uri _sparqlUrl;

  /// How many entity-search hits are looked at for a title.
  static const candidates = 10;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  /// The item ids the entity search finds for [title].
  Future<List<String>> _search(String title) async {
    final response = await send(
      () => client.get(
        _apiUrl.replace(
          queryParameters: {
            'action': 'wbsearchentities',
            'search': title,
            'language': 'en',
            'type': 'item',
            'limit': '$candidates',
            'format': 'json',
          },
        ),
        headers: _headers,
      ),
    );
    check(response);
    final json = decodeObject(response);
    return [
      for (final hit in objectsAt(json, 'search'))
        if (stringAt(hit, 'id') case final id?
            when RegExp(r'^Q\d+$').hasMatch(id))
          id,
    ];
  }

  /// One query for the candidates: each one's series statement with its
  /// ordinal and the names of its authors, and every part of the series
  /// with its ordinal, date, authors and what it is a part of (P361).
  static String query(List<String> ids) =>
      '''
SELECT ?book ?authorLabel ?series ?seriesLabel ?ordinal ?part ?partLabel ?partOrdinal ?date ?partOf ?partAuthorLabel WHERE {
  VALUES ?book { ${ids.map((id) => 'wd:$id').join(' ')} }
  ?book p:P179 ?statement . ?statement ps:P179 ?series .
  OPTIONAL { ?statement pq:P1545 ?ordinal }
  OPTIONAL { ?book wdt:P50 ?author }
  ?part p:P179 ?partStatement . ?partStatement ps:P179 ?series .
  OPTIONAL { ?partStatement pq:P1545 ?partOrdinal }
  OPTIONAL { ?part wdt:P577 ?date }
  OPTIONAL { ?part wdt:P361 ?partOf }
  OPTIONAL { ?part wdt:P50 ?partAuthor }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 5000''';

  Future<List<Map<String, Object?>>> _sparql(String query) async {
    final response = await send(
      () => client.get(
        _sparqlUrl.replace(queryParameters: {'query': query, 'format': 'json'}),
        headers: _headers,
      ),
    );
    check(response);
    final json = decodeObject(response);
    final results = json['results'] as Map<String, Object?>? ?? const {};
    return objectsAt(results, 'bindings');
  }

  static String? _value(Map<String, Object?> row, String key) {
    final cell = row[key];
    return cell is Map<String, Object?> ? stringAt(cell, 'value') : null;
  }

  static String? _item(Map<String, Object?> row, String key) =>
      _value(row, key)?.split('/').last;

  /// Whether a Wikidata author name is the entry's creator: a word of
  /// three letters or more in common (a surname), case aside.
  static bool sameAuthor(String? creator, Iterable<String> authors) {
    if (creator == null || creator.trim().isEmpty) return true;
    final wanted = {
      for (final w in creator.toLowerCase().split(
        RegExp(r'[^\p{L}]+', unicode: true),
      ))
        if (w.length >= 3) w,
    };
    for (final author in authors) {
      for (final w in author.toLowerCase().split(
        RegExp(r'[^\p{L}]+', unicode: true),
      )) {
        if (w.length >= 3 && wanted.contains(w)) return true;
      }
    }
    return false;
  }

  /// The series the book [title] by [creator] is in, with its parts in
  /// ordinal order (a part without an ordinal by date, after the rest),
  /// and the book's own number; null when Wikidata knows no series for it.
  /// A title that names nothing is asked again without what an edition
  /// tacks on after it ([coreTitle]): Open Library has "Tai-Pan (Asian
  /// Saga" and Apple Books "Shōgun, Part One (The Asian Saga)".
  Future<({SeriesParts parts, int? number})?> seriesOf(
    String title,
    String? creator,
  ) async {
    final found = await _seriesOf(title, creator);
    if (found != null) return found;
    final core = coreTitle(title);
    return core == title ? null : _seriesOf(core, creator);
  }

  /// A title cut before a parenthesis, a colon, or ", Part", ", Book" or
  /// ", Vol": "Tai-Pan (Asian Saga" and "Shōgun, Part One" give "Tai-Pan"
  /// and "Shōgun". A title that would lose everything stays as it is.
  static String coreTitle(String title) {
    final core = title.split(_tackedOn).first.trim();
    return core.isEmpty ? title : core;
  }

  static final _tackedOn = RegExp(
    r'\s*(?:[(\[:]|,\s*(?:part|book|vol)\b)',
    caseSensitive: false,
  );

  Future<({SeriesParts parts, int? number})?> _seriesOf(
    String title,
    String? creator,
  ) async {
    final ids = await _search(title);
    if (ids.isEmpty) return null;
    final rows = await _sparql(query(ids));
    // Rows per candidate book: its authors and its series.
    final authorsOf = <String, Set<String>>{};
    final seriesOf = <String, String>{};
    final ordinalOf = <String, String?>{};
    final seriesName = <String, String>{};
    final partsOf = <String, Map<String, WikidataPart>>{};
    for (final row in rows) {
      final book = _item(row, 'book');
      final series = _item(row, 'series');
      if (book == null || series == null) continue;
      if (_value(row, 'authorLabel') case final author?) {
        authorsOf.putIfAbsent(book, () => {}).add(author);
      }
      seriesOf[book] = series;
      ordinalOf[book] = _value(row, 'ordinal');
      seriesName[series] = _value(row, 'seriesLabel') ?? series;
      final part = _item(row, 'part');
      final partTitle = _value(row, 'partLabel');
      if (part == null || partTitle == null) continue;
      final parts = partsOf.putIfAbsent(series, () => {});
      final date = _value(row, 'date') ?? '';
      final year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
      final known = parts[part];
      final partOf = _item(row, 'partOf');
      final author = _value(row, 'partAuthorLabel');
      parts[part] = (
        id: part,
        title: partTitle,
        number: _ordinal(_value(row, 'partOrdinal')) ?? known?.number,
        year: _earliest(year, known?.year),
        partOf: {...?known?.partOf, ?partOf},
        authors: [
          ...?known?.authors,
          if (author != null && !(known?.authors.contains(author) ?? false))
            author,
        ],
      );
    }
    // The first candidate, in search order, that is a book by the author.
    for (final id in ids) {
      final series = seriesOf[id];
      if (series == null) continue;
      if (!sameAuthor(creator, authorsOf[id] ?? const {})) continue;
      final parts = cleanParts((partsOf[series] ?? const {}).values)
        ..sort((a, b) {
          final x = a.number, y = b.number;
          if (x != null && y != null) return x.compareTo(y);
          if (x != null || y != null) return x == null ? 1 : -1;
          final p = a.year, q = b.year;
          if (p != null && q != null) return p.compareTo(q);
          return p == null ? (q == null ? 0 : 1) : -1;
        });
      return (
        parts: (
          name: seriesName[series] ?? series,
          parts: [
            for (final p in parts)
              (
                number: p.number,
                title: p.title,
                year: p.year,
                source: 'wikidata:${p.id}',
                creator: p.authors.isEmpty ? null : p.authors.join(', '),
              ),
          ],
        ),
        number: _ordinal(ordinalOf[id]),
      );
    }
    return null;
  }

  /// Wikidata's parts of a series without what the series page should not
  /// list (Library › Book series after the automatic rules): a part that is
  /// itself part of another part (The Lord of the Rings' six-book edition,
  /// "The First Journey" and so on), a part with neither a number nor a
  /// date (the prologue "Concerning Hobbits"), and, when most of what is
  /// left is numbered, the unnumbered rest (the Appendices). A series that
  /// numbers few of its parts keeps them all: Wikidata numbers only
  /// Whirlwind in the Asian Saga. The type (P31) is no help: the Appendices
  /// are a "literary work" like the novels, and half the Asian Saga is a
  /// "written work".
  static List<WikidataPart> cleanParts(Iterable<WikidataPart> parts) {
    final ids = {for (final p in parts) p.id};
    final kept = [
      for (final p in parts)
        if (!p.partOf.any(ids.contains))
          if (p.number != null || p.year != null) p,
    ];
    final numbered = kept.where((p) => p.number != null).length;
    if (numbered * 2 <= kept.length) return kept;
    return [
      for (final p in kept)
        if (p.number != null) p,
    ];
  }

  static int? _earliest(int? a, int? b) =>
      a == null || b == null ? a ?? b : (a < b ? a : b);

  /// "3" as 3; "3.5" or "III" as nothing.
  static int? _ordinal(String? text) =>
      text == null ? null : int.tryParse(text.trim());
}

/// One part of a series as Wikidata has it, before [WikidataSeries.cleanParts]:
/// its item id, its label, its series ordinal, its earliest year, the items
/// it is part of (P361) and its authors' names.
typedef WikidataPart = ({
  String id,
  String title,
  int? number,
  int? year,
  Set<String> partOf,
  List<String> authors,
});
