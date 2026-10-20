import '../models/media_type.dart';
import '../models/released.dart';
import '../models/series.dart';
import 'book_match.dart';
import 'google_books.dart';
import 'http_lookup_source.dart';
import 'itunes_books.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'lookup_source.dart';
import 'text_clean.dart';
import 'wikidata_series.dart';

/// Books, from Open Library and Apple Books together. Open Library issues
/// the ids, "openlibrary:OL45804W" (the work, never an edition), and gives
/// the year (the first publication's, see [firstPublishYear]), the author,
/// the subjects and the page count (the median of the editions'). Apple
/// ([apple]) is asked in parallel: it finds the books Open Library does not
/// have yet, which keep its id, "itunes:6756269989", and gives every book
/// its description and cover, preferred to Open Library's. A book both
/// have is one row with Open Library's id. Each field falls back to the
/// other source ([withApple], [withOpenLibrary]). Google Books ([google])
/// is read by id only, for the "googlebooks:" ids stored while it was a
/// search source. One source failing never fails a lookup the other
/// answered. A book's series (Library › Book in a long series) comes from
/// Wikidata ([wikidata]) by title and author, else from a volume number in
/// the title ("Berserk, Vol. 43"); the volumes of such a series are then
/// Open Library's works of that name by that author.
class OpenLibrarySource extends HttpLookupSource {
  OpenLibrarySource(
    super.client, {
    this.apple,
    this.google,
    this.wikidata,
    Uri? baseUrl,
    Uri? coversUrl,
    super.timeout,
  }) : _baseUrl = baseUrl ?? Uri.https('openlibrary.org'),
       _coversUrl = coversUrl ?? Uri.https('covers.openlibrary.org'),
       super(minGap: const Duration(milliseconds: 500));

  final ITunesBooks? apple;
  final GoogleBooks? google;
  final WikidataSeries? wikidata;

  /// How many works are read when listing a series' volumes by name.
  static const volumesLimit = 100;
  final Uri _baseUrl;
  final Uri _coversUrl;

  /// `editions.cover_i` is the cover of the edition that best matches the
  /// query, an English one when there is one (`lang=en` below); the work's
  /// own `cover_i` can be any edition's, a Spanish "Rey de las ratas" for
  /// "King Rat".
  static const _fields =
      'key,title,author_name,first_publish_year,publish_year,cover_i,subject,'
      'number_of_pages_median,editions,editions.cover_i';

  @override
  String get id => 'openlibrary';

  @override
  String get name => 'Open Library';

  @override
  Set<MediaType> get types => const {MediaType.books};

  @override
  bool issued(String source) =>
      super.issued(source) || _isApple(source) || _isGoogle(source);

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String>? q,
  ]) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(path: path, queryParameters: q),
        headers: _headers,
      ),
    );
    check(response);
    return decodeObject(response);
  }

  /// "-M" for a row (180 px wide), "-L" for the cache (500 px wide).
  String _cover(int coverId, String size) =>
      _coversUrl.replace(path: '/b/id/$coverId$size.jpg').toString();

  LookupMatch? _match(Map<String, Object?> doc) {
    final key = stringAt(doc, 'key');
    final title = stringAt(doc, 'title');
    if (key == null || title == null) return null;
    final workId = key.split('/').last;
    final authors = [
      for (final a in doc['author_name'] as List? ?? const []) '$a',
    ];
    final first = doc['first_publish_year'];
    final year =
        firstPublishYear([
          for (final y in doc['publish_year'] as List? ?? const [])
            if (y is num) y.toInt(),
        ]) ??
        (first is num ? first.toInt() : null);
    final editions = doc['editions'] as Map<String, Object?>? ?? const {};
    final edition = objectsAt(editions, 'docs').firstOrNull?['cover_i'];
    final coverId = edition is num && edition > 0 ? edition : doc['cover_i'];
    final pages = doc['number_of_pages_median'];
    return LookupMatch(
      type: MediaType.books,
      title: title,
      source: 'openlibrary:$workId',
      released: year == null ? null : Released(year),
      creator: authors.isEmpty ? null : authors.join(', '),
      tags: [
        for (final s
            in (doc['subject'] as List? ?? const [])
                .map((s) => '$s')
                .where(isTagLike)
                .take(maxBookTags))
          s,
      ],
      pages: pages is num && pages > 0 ? pages.toInt() : null,
      coverUrl: coverId is num && coverId > 0
          ? _cover(coverId.toInt(), '-M')
          : null,
      largeCoverUrl: coverId is num && coverId > 0
          ? _cover(coverId.toInt(), '-L')
          : null,
    );
  }

  Future<List<LookupMatch>> _search(
    Map<String, String> query,
    int limit,
  ) async {
    final json = await _get('/search.json', {
      ...query,
      'fields': _fields,
      'lang': 'en',
      'limit': '$limit',
    });
    return [for (final doc in objectsAt(json, 'docs')) ?_match(doc)];
  }

  /// Throws [PartialLookupException] with the hits of the source that
  /// answered when the other did not, so the screen can say some were not
  /// reached rather than that there are no matches.
  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async {
    final (:hits, :failure) = await _both(
      _search({'q': query}, limit),
      apple?.search(query, limit: limit),
      limit,
    );
    if (failure != null) {
      throw PartialLookupException(
        hits,
        failure.failure,
        status: failure.status,
        message: failure.message,
      );
    }
    return hits;
  }

  /// No match while one source failed is not a miss: the failure is
  /// thrown, so the cover is asked for again rather than given up on.
  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    final author = creator != null && creator.isNotEmpty ? creator : null;
    final (:hits, :failure) = await _both(
      _search({'title': title, 'author': ?author}, 5),
      apple?.searchTitle(title, author: author, limit: 5),
      10,
    );
    final hit = _pick(hits, title, year: year, author: author);
    if (hit == null && failure != null) throw failure;
    return hit;
  }

  static LookupMatch? _pick(
    List<LookupMatch> hits,
    String title, {
    required int? year,
    required String? author,
  }) {
    final same = hits.where((h) => sameTitle(h.title, title)).toList();
    if (year != null) {
      for (final hit in same) {
        if (hit.released?.year == year) return hit;
      }
    }
    // The same title by the same author is the same book whatever year the
    // library recorded; without an author, only an exact year is sure.
    if (author != null && same.isNotEmpty) return same.first;
    return year == null && same.isNotEmpty ? same.first : null;
  }

  /// Both searches at once, merged by [mergeBookHits], with the failure of
  /// the one that did not answer. Throws when neither answered (Open
  /// Library's failure; without Apple, whenever Open Library fails).
  Future<({List<LookupMatch> hits, LookupException? failure})> _both(
    Future<List<LookupMatch>> openLibrary,
    Future<List<LookupMatch>>? apple,
    int limit,
  ) async {
    final [ol, ab] = await Future.wait([
      _settle(openLibrary),
      apple == null
          ? Future<Object>.value(const <LookupMatch>[])
          : _settle(apple),
    ]);
    switch ((ol, ab)) {
      case (List<LookupMatch> ol, List<LookupMatch> ab):
        return (hits: mergeBookHits(ol, ab, limit: limit), failure: null);
      case (List<LookupMatch> ol, LookupException ab):
        return (hits: mergeBookHits(ol, const [], limit: limit), failure: ab);
      case (LookupException ol, List<LookupMatch> ab) when apple != null:
        return (hits: mergeBookHits(const [], ab, limit: limit), failure: ol);
      case (LookupException ol, _):
        throw ol;
    }
    throw StateError('unreachable');
  }

  /// The hits, or the failure as a [LookupException]; so neither search's
  /// failure goes unhandled while the other is awaited.
  static Future<Object> _settle(Future<List<LookupMatch>> hits) =>
      hits.then<Object>(
        (h) => h,
        onError: (Object e) => e is LookupException
            ? e
            : LookupException(LookupFailure.other, message: '$e'),
      );

  /// One list from both sources' hits: each Open Library hit keeps its place
  /// and takes Apple's record of the same book ([sameBook], [withApple]);
  /// Apple's other hits take turns with Open Library's, so a long Open
  /// Library list cannot push out the book only Apple has. At most [limit].
  static List<LookupMatch> mergeBookHits(
    List<LookupMatch> openLibrary,
    List<LookupMatch> apple, {
    int? limit,
  }) {
    final ol = [...openLibrary];
    final onlyApple = <LookupMatch>[];
    for (final hit in apple) {
      final i = ol.indexWhere((o) => sameBook(o, hit));
      if (i >= 0) {
        ol[i] = withApple(ol[i], hit);
      } else if (!onlyApple.any((o) => sameBook(o, hit))) {
        onlyApple.add(hit);
      }
    }
    final out = <LookupMatch>[];
    for (var i = 0; i < ol.length || i < onlyApple.length; i++) {
      if (i < ol.length) out.add(ol[i]);
      if (i < onlyApple.length) out.add(onlyApple[i]);
    }
    return limit == null ? out : out.take(limit).toList();
  }

  /// [match] with Apple's record of the same book: Apple's description and
  /// cover, when it has them, replace what [match] has; its year, author
  /// and genres fill gaps only.
  static LookupMatch withApple(LookupMatch match, LookupMatch? apple) {
    if (apple == null) return match;
    return match.copyWith(
      released: match.released ?? apple.released,
      releasedFromEbook: match.released == null
          ? apple.releasedFromEbook
          : match.releasedFromEbook,
      creator: match.creator ?? apple.creator,
      description: apple.description.isNotEmpty ? apple.description : null,
      tags: match.tags.isEmpty && apple.tags.isNotEmpty ? apple.tags : null,
      pages: match.pages ?? apple.pages,
      coverUrl: apple.coverUrl,
      largeCoverUrl: apple.coverUrl == null
          ? null
          : apple.largeCoverUrl ?? apple.coverUrl,
    );
  }

  /// [match] (an Apple or Google hit) with Open Library's record of the
  /// same book: Open Library's year, author and page count, when it has
  /// them, replace what [match] has; its description, cover and subjects
  /// fill gaps only.
  static LookupMatch withOpenLibrary(LookupMatch match, LookupMatch? ol) {
    if (ol == null) return match;
    return match.copyWith(
      released: ol.released,
      releasedFromEbook: ol.released == null ? null : false,
      creator: ol.creator,
      pages: ol.pages,
      description: match.description.isEmpty && ol.description.isNotEmpty
          ? ol.description
          : null,
      tags: match.tags.isEmpty && ol.tags.isNotEmpty ? ol.tags : null,
      coverUrl: match.coverUrl == null ? ol.coverUrl : null,
      largeCoverUrl: match.coverUrl == null && match.largeCoverUrl == null
          ? ol.largeCoverUrl
          : null,
    );
  }

  /// [match] with the fields it lacks taken from [other]; nothing it has is
  /// replaced.
  static LookupMatch _fillGaps(LookupMatch match, LookupMatch? other) {
    if (other == null) return match;
    return match.copyWith(
      released: match.released == null ? other.released : null,
      releasedFromEbook: match.released == null
          ? other.releasedFromEbook
          : null,
      creator: match.creator == null ? other.creator : null,
      description: match.description.isEmpty ? other.description : null,
      tags: match.tags.isEmpty ? other.tags : null,
      pages: match.pages == null ? other.pages : null,
      coverUrl: match.coverUrl == null ? other.coverUrl : null,
      largeCoverUrl: match.coverUrl == null && match.largeCoverUrl == null
          ? other.largeCoverUrl
          : null,
    );
  }

  static String _workId(String source) {
    final parts = source.split(':');
    if (parts.length != 2 || parts[0] != 'openlibrary' || parts[1].isEmpty) {
      throw LookupException(
        LookupFailure.other,
        message: 'not an Open Library id: $source',
      );
    }
    return parts[1];
  }

  static bool _isApple(String source) =>
      LookupMatch.providerOf(source) == ITunesBooks.id;

  static bool _isGoogle(String source) =>
      LookupMatch.providerOf(source) == GoogleBooks.id;

  ITunesBooks get _apple =>
      apple ??
      (throw const LookupException(
        LookupFailure.notConfigured,
        message: 'no Apple Books',
      ));

  GoogleBooks get _google =>
      google ??
      (throw const LookupException(
        LookupFailure.notConfigured,
        message: 'no Google Books',
      ));

  /// The work record: its description (text or `{"value": text}`) and its
  /// first cover id.
  Future<({String? description, int? coverId, String? title})> _work(
    String source,
  ) async {
    final json = await _get('/works/${_workId(source)}.json');
    final raw = json['description'];
    final description = switch (raw) {
      String text => text,
      Map<String, Object?> value => stringAt(value, 'value'),
      _ => null,
    };
    final covers = [
      for (final c in json['covers'] as List? ?? const [])
        if (c is num && c > 0) c.toInt(),
    ];
    return (
      description: description == null ? null : stripHtml(description),
      coverId: covers.isEmpty ? null : covers.first,
      title: stringAt(json, 'title'),
    );
  }

  /// [hit] with its work's description and cover where it lacks them.
  Future<LookupMatch> _withWork(LookupMatch hit) async {
    final work = await _work(hit.source);
    final coverId = work.coverId;
    return hit.copyWith(
      description: hit.description.isEmpty ? work.description : null,
      coverUrl: hit.coverUrl == null && coverId != null
          ? _cover(coverId, '-M')
          : null,
      largeCoverUrl: hit.largeCoverUrl == null && coverId != null
          ? _cover(coverId, '-L')
          : null,
    );
  }

  /// The first of [hits] that is the book [title] by [author] (the same
  /// title alone when no author is known).
  static LookupMatch? _theBook(
    List<LookupMatch> hits,
    String title,
    String? author,
  ) {
    final probe = LookupMatch(
      type: MediaType.books,
      title: title,
      source: '',
      creator: author,
    );
    return hits
        .where(
          (h) =>
              author == null ? sameTitle(h.title, title) : sameBook(h, probe),
        )
        .firstOrNull;
  }

  /// Apple's record of the book [title] (by [author], when known); null
  /// when Apple has none, is not set up, or does not answer.
  Future<LookupMatch?> _appleFill(String title, String? author) async {
    final books = apple;
    if (books == null) return null;
    try {
      final hits = await books.searchTitle(title, author: author, limit: 5);
      return _theBook(hits, title, author);
    } on LookupException {
      return null;
    }
  }

  /// Open Library's record of the book [title] (by [author], when known),
  /// with its work's description and cover when [withWork]; null when it
  /// has none or does not answer.
  Future<LookupMatch?> _openLibraryFill(
    String title,
    String? author, {
    bool withWork = false,
  }) async {
    try {
      final hits = await _search({'title': title, 'author': ?author}, 5);
      final hit = _theBook(hits, title, author);
      if (hit == null || !withWork) return hit;
      return await _withWork(hit);
    } on LookupException {
      return null;
    }
  }

  /// The search index's own record of the work [source]: its title, author
  /// and cover in one request; null when the index lacks it.
  Future<LookupMatch?> _byKey(String source) async {
    final hits = await _search({'q': 'key:/works/${_workId(source)}'}, 1);
    return hits.where((h) => h.source == source).firstOrNull;
  }

  /// An Open Library pick takes Apple's description and cover (the work's
  /// where Apple has none); an Apple pick takes Open Library's year, author
  /// and page count; a Google pick reads its volume, then both. Every pick
  /// then gets its series ([_seriesOf]).
  @override
  Future<LookupMatch> details(LookupMatch match) async {
    final full = await _details(match);
    return full.copyWith(series: await _seriesOf(full.title, full.creator));
  }

  Future<LookupMatch> _details(LookupMatch match) async {
    if (_isApple(match.source)) {
      return withOpenLibrary(
        match,
        await _openLibraryFill(
          match.title,
          match.creator,
          withWork: match.description.isEmpty,
        ),
      );
    }
    if (_isGoogle(match.source)) {
      final full = _fillGaps(match, await _google.volume(match.source));
      final withBoth = withApple(
        full,
        await _appleFill(full.title, full.creator),
      );
      return withOpenLibrary(
        withBoth,
        await _openLibraryFill(
          withBoth.title,
          withBoth.creator,
          withWork: withBoth.description.isEmpty,
        ),
      );
    }
    var full = match;
    if (full.description.isEmpty ||
        full.coverUrl == null ||
        full.released == null ||
        full.creator == null) {
      full = withApple(full, await _appleFill(full.title, full.creator));
    }
    if (full.description.isEmpty || full.coverUrl == null) {
      full = await _withWork(full);
    }
    return full;
  }

  /// The series of the book [title] by [author]: Wikidata's, else the one a
  /// volume number in the title names. Wikidata not answering is not a
  /// failure of the pick: the series is then left to the title.
  Future<Series?> _seriesOf(String title, String? author) async {
    if (wikidata case final wikidata?) {
      try {
        final found = await wikidata.seriesOf(title, author);
        if (found != null) {
          return Series(name: found.parts.name, number: found.number);
        }
      } on LookupException {
        // Left to the title.
      }
    }
    final volume = volumeOf(title);
    return volume == null
        ? null
        : Series(name: volume.name, number: volume.number);
  }

  /// A book's series with its parts: Wikidata's for the book's title and
  /// author, else the volumes of the manga the title (or [name], the
  /// series the entry carries) names, read from Open Library by that name
  /// and the author. Null when neither knows a series.
  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    final LookupMatch? book;
    if (_isApple(source)) {
      book = await _apple.book(source);
    } else if (_isGoogle(source)) {
      book = await _google.volume(source);
    } else {
      book = await _byKey(source);
    }
    if (book == null) return null;
    if (wikidata case final wikidata?) {
      final found = await wikidata.seriesOf(book.title, book.creator);
      if (found != null) return found.parts;
    }
    final volume = volumeOf(book.title);
    final seriesName = name ?? volume?.name;
    if (seriesName == null) return null;
    return _volumes(seriesName, book.creator);
  }

  /// The works titled `<name>, Vol. N` (or "Volume N", "#N") by [author] in
  /// Open Library's index, one per number, in number order.
  Future<SeriesParts?> _volumes(String name, String? author) async {
    final hits = await _search({
      'title': name,
      'author': ?author,
    }, volumesLimit);
    final byNumber = <int, SeriesPart>{};
    for (final hit in hits) {
      final volume = volumeOf(hit.title);
      if (volume == null || !sameTitle(volume.name, name)) continue;
      final known = byNumber[volume.number];
      final year = hit.released?.year;
      if (known == null) {
        byNumber[volume.number] = (
          number: volume.number,
          title: hit.title,
          year: year,
          source: hit.source,
        );
      } else if (year != null && (known.year == null || year < known.year!)) {
        byNumber[volume.number] = (
          number: volume.number,
          title: known.title,
          year: year,
          source: known.source,
        );
      }
    }
    if (byNumber.isEmpty) return null;
    final numbers = byNumber.keys.toList()..sort();
    return (name: name, parts: [for (final n in numbers) byNumber[n]!]);
  }

  /// An Open Library id: Apple's artwork for the work, found by its title
  /// and author, else Open Library's own cover. An Apple id: its record's
  /// artwork, else Open Library's cover by title. A Google id: its volume's
  /// cover, else the others' by title.
  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    if (_isApple(source)) {
      final book = await _apple.book(source);
      if (book == null) return null;
      if (book.cacheCoverUrl case final url?) return url;
      final ol = await _openLibraryFill(
        book.title,
        book.creator,
        withWork: true,
      );
      return ol?.cacheCoverUrl;
    }
    if (_isGoogle(source)) {
      final volume = await _google.volume(source);
      if (volume == null) return null;
      if (volume.cacheCoverUrl case final url?) return url;
      final fromApple = await _appleFill(volume.title, volume.creator);
      if (fromApple?.cacheCoverUrl case final url?) return url;
      final ol = await _openLibraryFill(
        volume.title,
        volume.creator,
        withWork: true,
      );
      return ol?.cacheCoverUrl;
    }
    final doc = await _byKey(source);
    if (doc != null) {
      final fromApple = await _appleFill(doc.title, doc.creator);
      if (fromApple?.cacheCoverUrl case final url?) return url;
      if (doc.cacheCoverUrl case final url?) return url;
    }
    final work = await _work(source);
    if (work.coverId != null) return _cover(work.coverId!, '-L');
    if (doc == null && work.title != null) {
      return (await _appleFill(work.title!, null))?.cacheCoverUrl;
    }
    return null;
  }
}
