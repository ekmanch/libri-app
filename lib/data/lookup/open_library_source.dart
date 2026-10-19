import '../models/media_type.dart';
import '../models/released.dart';
import 'google_books_fill_in.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'text_clean.dart';

/// Books from Open Library. No key. Ids are the work ids,
/// "openlibrary:OL45804W", never an edition, and the year is the first
/// publication year and the page count the median of its editions'. Open
/// Library has no description for many works and no cover or page count for
/// some; then [fillIn] (Google Books) is asked for just that.
class OpenLibrarySource extends HttpLookupSource {
  OpenLibrarySource(
    super.client, {
    this.fillIn,
    Uri? baseUrl,
    Uri? coversUrl,
    super.timeout,
  }) : _baseUrl = baseUrl ?? Uri.https('openlibrary.org'),
       _coversUrl = coversUrl ?? Uri.https('covers.openlibrary.org'),
       super(minGap: const Duration(milliseconds: 500));

  final GoogleBooksFillIn? fillIn;
  final Uri _baseUrl;
  final Uri _coversUrl;

  static const _fields =
      'key,title,author_name,first_publish_year,cover_i,subject,'
      'number_of_pages_median';

  /// How many subjects become tag suggestions; the form keeps six at most.
  static const maxSubjects = 6;

  /// Open Library's subjects mix genres with catalog notes ("Fiction, science
  /// fiction, general"), pseudo-tags ("award:hugo_award=1960") and long
  /// headings; only short plain ones make sense as tags.
  static bool _isTagLike(String subject) =>
      subject.length <= 24 &&
      !subject.contains(RegExp(r'[:=,(){}\[\]/]')) &&
      subject.trim().split(RegExp(r'\s+')).length <= 3;

  @override
  String get id => 'openlibrary';

  @override
  Set<MediaType> get types => const {MediaType.books};

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
                .where(_isTagLike)
                .take(maxSubjects))
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

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) => _search({'q': query}, limit);

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    final hits = await _search({
      'title': title,
      if (creator != null && creator.isNotEmpty) 'author': creator,
    }, 5);
    final same = hits.where((h) => sameTitle(h.title, title)).toList();
    if (year != null) {
      for (final hit in same) {
        if (hit.released?.year == year) return hit;
      }
    }
    // The same title by the same author is the same book whatever year the
    // library recorded; without an author, only an exact year is sure.
    if (creator != null && creator.isNotEmpty && same.isNotEmpty) {
      return same.first;
    }
    return year == null && same.isNotEmpty ? same.first : null;
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

  /// Google Books, when there is one; its failures leave the gap open.
  Future<GoogleBooksFill> _fill(String title, String? author) async {
    const none = (description: null, coverUrl: null, pages: null);
    final fill = fillIn;
    if (fill == null) return none;
    try {
      return await fill.lookUp(title, author: author);
    } on LookupException {
      return none;
    }
  }

  @override
  Future<LookupMatch> details(LookupMatch match) async {
    final work = await _work(match.source);
    var description = work.description;
    var cover = match.coverUrl;
    if (cover == null && work.coverId != null) {
      cover = _cover(work.coverId!, '-M');
    }
    var pages = match.pages;
    if (description == null || cover == null || pages == null) {
      final filled = await _fill(match.title, match.creator);
      description ??= filled.description;
      cover ??= filled.coverUrl;
      pages ??= filled.pages;
    }
    return match.copyWith(
      description: description,
      coverUrl: cover,
      pages: pages,
    );
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    final work = await _work(source);
    if (work.coverId != null) return _cover(work.coverId!, '-L');
    if (work.title == null) return null;
    return (await _fill(work.title!, null)).coverUrl;
  }
}
