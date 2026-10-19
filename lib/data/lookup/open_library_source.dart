import '../models/media_type.dart';
import '../models/released.dart';
import 'google_books.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'text_clean.dart';

/// Books, from Open Library and Google Books together. Open Library is
/// asked first for ids, "openlibrary:OL45804W" (the work, never an
/// edition), its year being the first publication year and its page count
/// the median of its editions'. Google Books ([google]) is asked in parallel
/// for the books Open Library does not have yet, which keep Google's id,
/// "googlebooks:eOTEEQAAQBAJ"; a book both have is one row with Open
/// Library's id. Whichever a pick came from, the other fills in what it
/// leaves out (a description, a cover, a year, an author, a page count).
/// Google's failures never fail a lookup Open Library answered, nor the
/// other way round.
class OpenLibrarySource extends HttpLookupSource {
  OpenLibrarySource(
    super.client, {
    this.google,
    Uri? baseUrl,
    Uri? coversUrl,
    super.timeout,
  }) : _baseUrl = baseUrl ?? Uri.https('openlibrary.org'),
       _coversUrl = coversUrl ?? Uri.https('covers.openlibrary.org'),
       super(minGap: const Duration(milliseconds: 500));

  final GoogleBooks? google;
  final Uri _baseUrl;
  final Uri _coversUrl;

  static const _fields =
      'key,title,author_name,first_publish_year,cover_i,subject,'
      'number_of_pages_median';

  @override
  String get id => 'openlibrary';

  @override
  Set<MediaType> get types => const {MediaType.books};

  @override
  bool issued(String source) =>
      super.issued(source) || LookupMatch.providerOf(source) == GoogleBooks.id;

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
    final year = doc['first_publish_year'];
    final coverId = doc['cover_i'];
    final pages = doc['number_of_pages_median'];
    return LookupMatch(
      type: MediaType.books,
      title: title,
      source: 'openlibrary:$workId',
      released: year is num ? Released(year.toInt()) : null,
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
      google?.search(query, limit: limit),
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
      google?.searchTitle(title, author: author, limit: 5),
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
  /// Library's failure; without Google, whenever Open Library fails).
  Future<({List<LookupMatch> hits, LookupException? failure})> _both(
    Future<List<LookupMatch>> openLibrary,
    Future<List<LookupMatch>>? google,
    int limit,
  ) async {
    final [ol, gb] = await Future.wait([
      _settle(openLibrary),
      google == null
          ? Future<Object>.value(const <LookupMatch>[])
          : _settle(google),
    ]);
    switch ((ol, gb)) {
      case (List<LookupMatch> ol, List<LookupMatch> gb):
        return (hits: mergeBookHits(ol, gb, limit: limit), failure: null);
      case (List<LookupMatch> ol, LookupException gb):
        return (hits: mergeBookHits(ol, const [], limit: limit), failure: gb);
      case (LookupException ol, List<LookupMatch> gb) when google != null:
        return (hits: mergeBookHits(const [], gb, limit: limit), failure: ol);
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
  /// and takes what it lacks (a cover, a year, a page count) from Google's
  /// hit for the same book ([sameBook]); Google's other hits take turns
  /// with Open Library's, so a long Open Library list cannot push out the
  /// book only Google has. At most [limit].
  static List<LookupMatch> mergeBookHits(
    List<LookupMatch> openLibrary,
    List<LookupMatch> google, {
    int? limit,
  }) {
    final ol = [...openLibrary];
    final onlyGoogle = <LookupMatch>[];
    for (final hit in google) {
      final i = ol.indexWhere((o) => sameBook(o, hit));
      if (i >= 0) {
        ol[i] = _fillGaps(ol[i], hit);
      } else if (!onlyGoogle.any((o) => sameBook(o, hit))) {
        onlyGoogle.add(hit);
      }
    }
    final out = <LookupMatch>[];
    for (var i = 0; i < ol.length || i < onlyGoogle.length; i++) {
      if (i < ol.length) out.add(ol[i]);
      if (i < onlyGoogle.length) out.add(onlyGoogle[i]);
    }
    return limit == null ? out : out.take(limit).toList();
  }

  /// [match] with the fields it lacks taken from [other]; nothing it has is
  /// replaced.
  static LookupMatch _fillGaps(LookupMatch match, LookupMatch? other) {
    if (other == null) return match;
    return match.copyWith(
      released: match.released == null ? other.released : null,
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

  bool _isGoogle(String source) =>
      LookupMatch.providerOf(source) == GoogleBooks.id;

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

  /// Google Books' fill-in for an Open Library pick, when there is one; its
  /// failures leave the gaps open.
  Future<GoogleBooksFill> _googleFill(String title, String? author) async {
    const none = (
      description: null,
      coverUrl: null,
      pages: null,
      released: null,
      creator: null,
    );
    final books = google;
    if (books == null) return none;
    try {
      return await books.lookUp(title, author: author);
    } on LookupException {
      return none;
    }
  }

  /// Open Library's record of a Google pick: the same title (by the same
  /// author, when known) with its work's description; null when it has no
  /// such book or does not answer.
  Future<LookupMatch?> _openLibraryFill(String title, String? author) async {
    try {
      final hits = await _search({'title': title, 'author': ?author}, 5);
      final probe = LookupMatch(
        type: MediaType.books,
        title: title,
        source: '',
        creator: author,
      );
      final hit = hits
          .where(
            (h) =>
                author == null ? sameTitle(h.title, title) : sameBook(h, probe),
          )
          .firstOrNull;
      if (hit == null) return null;
      final work = await _work(hit.source);
      return hit.copyWith(
        description: work.description,
        coverUrl: hit.coverUrl == null && work.coverId != null
            ? _cover(work.coverId!, '-M')
            : null,
        largeCoverUrl: hit.largeCoverUrl == null && work.coverId != null
            ? _cover(work.coverId!, '-L')
            : null,
      );
    } on LookupException {
      return null;
    }
  }

  bool _complete(LookupMatch match) =>
      match.description.isNotEmpty &&
      match.coverUrl != null &&
      match.released != null &&
      match.creator != null &&
      match.pages != null;

  @override
  Future<LookupMatch> details(LookupMatch match) async {
    if (_isGoogle(match.source)) {
      final full = _fillGaps(match, await _google.volume(match.source));
      if (_complete(full)) return full;
      return _fillGaps(full, await _openLibraryFill(full.title, full.creator));
    }
    final work = await _work(match.source);
    final full = match.copyWith(
      description: work.description,
      coverUrl: match.coverUrl == null && work.coverId != null
          ? _cover(work.coverId!, '-M')
          : null,
    );
    if (_complete(full)) return full;
    final filled = await _googleFill(match.title, match.creator);
    return _fillGaps(
      full,
      LookupMatch(
        type: MediaType.books,
        title: match.title,
        source: '',
        released: filled.released,
        creator: filled.creator,
        description: filled.description ?? '',
        pages: filled.pages,
        coverUrl: filled.coverUrl,
      ),
    );
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    if (_isGoogle(source)) {
      final volume = await _google.volume(source);
      if (volume == null) return null;
      if (volume.cacheCoverUrl case final url?) return url;
      return (await _openLibraryFill(
        volume.title,
        volume.creator,
      ))?.cacheCoverUrl;
    }
    final work = await _work(source);
    if (work.coverId != null) return _cover(work.coverId!, '-L');
    if (work.title == null) return null;
    return (await _googleFill(work.title!, null)).coverUrl;
  }
}
