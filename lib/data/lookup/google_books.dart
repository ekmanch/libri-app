import 'package:http/http.dart' as http;

import '../models/media_type.dart';
import '../models/released.dart';
import '../net/http_transport.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'rate_limiter.dart';
import 'text_clean.dart';

/// What [GoogleBooks.lookUp] found; null where Google Books has nothing.
typedef GoogleBooksFill = ({
  String? description,
  String? coverUrl,
  int? pages,
  Released? released,
  String? creator,
});

/// Google Books, the second half of the book lookup (see
/// `OpenLibrarySource`): it finds the books Open Library does not have yet,
/// with ids "googlebooks:eOTEEQAAQBAJ", and fills in what Open Library's
/// records leave out (a description, a cover, a page count). Its year is the
/// edition's, not the first publication's. Works without a key, with a
/// smaller quota. Every method throws [LookupException] on failure.
class GoogleBooks with LookupHttp {
  GoogleBooks(
    this.client, {
    this.key = '',
    Uri? baseUrl,
    this.timeout = defaultHttpTimeout,
    this.userAgent = 'Libri',
    Duration minGap = const Duration(milliseconds: 500),
  }) : _baseUrl =
           baseUrl ?? Uri.https('www.googleapis.com', '/books/v1/volumes'),
       limiter = RateLimiter(minGap);

  @override
  final http.Client client;
  @override
  final Duration timeout;
  @override
  final String userAgent;
  @override
  final RateLimiter limiter;

  final String key;
  final Uri _baseUrl;

  /// How many times a search is sent before a server error (5xx) is
  /// taken as the answer. In October 2026 Google's text search answered
  /// 503 "backendFailed" to most requests, whatever the key, the country or
  /// the parameters, and now and then an empty list for a search that has
  /// hits, while reading one volume by id kept working. Each new try has
  /// the same chance, so trying again is what helps.
  static const searchTries = 9;

  /// How many empty lists a search takes before it believes Google has
  /// nothing, since a struggling Google answers some searches that way.
  static const emptyTries = 3;

  /// The provider part of the ids it issues.
  static const id = 'googlebooks';

  /// Google lists one volume per edition; only the first of the same title
  /// by the same author is kept.
  Future<List<LookupMatch>> search(String query, {int limit = 10}) async {
    final out = <LookupMatch>[];
    for (final hit in await _volumes(query, limit)) {
      if (!out.any((o) => sameBook(o, hit))) out.add(hit);
    }
    return out;
  }

  /// [search] for [title] (by [author] when known), for the cover matcher.
  Future<List<LookupMatch>> searchTitle(
    String title, {
    String? author,
    int limit = 10,
  }) => search(_titleQuery(title, author), limit: limit);

  /// The volume's own record, which carries a description and larger
  /// covers that the search often leaves out; null when it has no title.
  Future<LookupMatch?> volume(String source) async {
    final record = await _record(volumeId(source));
    return _match(record, large: true);
  }

  /// A description, a cover, a page count, a year and an author for [title]
  /// (by [author] when known), each null when Google Books has none, for
  /// filling in an Open Library pick. Each is the first among up to ten
  /// volumes; their list often leaves the description out, so when none has
  /// one the first volume's own record is read too.
  Future<GoogleBooksFill> lookUp(String title, {String? author}) async {
    String? description;
    String? cover;
    int? pages;
    Released? released;
    String? creator;
    String? firstId;
    for (final hit in await _volumes(_titleQuery(title, author), 10)) {
      firstId ??= hit.source;
      if (hit.description.isNotEmpty) description ??= hit.description;
      cover ??= hit.coverUrl;
      pages ??= hit.pages;
      released ??= hit.released;
      creator ??= hit.creator;
      if (description != null && cover != null && pages != null) break;
    }
    if (description == null && firstId != null) {
      final found = await volume(firstId);
      if (found != null && found.description.isNotEmpty) {
        description = found.description;
      }
      cover ??= found?.coverUrl;
      pages ??= found?.pages;
    }
    return (
      description: description,
      coverUrl: cover,
      pages: pages,
      released: released,
      creator: creator,
    );
  }

  /// The volume id of "googlebooks:eOTEEQAAQBAJ".
  static String volumeId(String source) {
    final parts = source.split(':');
    if (parts.length != 2 || parts[0] != id || parts[1].isEmpty) {
      throw LookupException(
        LookupFailure.other,
        message: 'not a Google Books id: $source',
      );
    }
    return parts[1];
  }

  static String _titleQuery(String title, String? author) => [
    'intitle:"$title"',
    if (author != null && author.isNotEmpty) 'inauthor:"$author"',
  ].join(' ');

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  /// Sent again on a server error or an empty list, up to [searchTries]
  /// times in all. An empty list is believed once it came [emptyTries]
  /// times, or when it came and every other try failed; a server error is
  /// thrown when every try failed so. Any other failure (offline, rate
  /// limited, a bad request) is thrown at once.
  Future<List<LookupMatch>> _volumes(String q, int limit) async {
    var empty = 0;
    for (var tries = 1; ; tries++) {
      try {
        final hits = await _volumesIn(q, limit);
        if (hits.isNotEmpty || ++empty == emptyTries) return hits;
        if (tries == searchTries) return hits;
      } on LookupException catch (e) {
        if ((e.status ?? 0) < 500) rethrow;
        if (tries == searchTries) {
          if (empty > 0) return const [];
          rethrow;
        }
      }
    }
  }

  Future<List<LookupMatch>> _volumesIn(String q, int limit) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(
          queryParameters: {
            'q': q,
            'printType': 'books',
            'projection': 'full',
            'maxResults': '${limit.clamp(1, 40)}',
            if (key.isNotEmpty) 'key': key,
          },
        ),
        headers: _headers,
      ),
    );
    check(response);
    return [
      for (final item in objectsAt(decodeObject(response), 'items'))
        ?_match(item),
    ];
  }

  Future<Map<String, Object?>> _record(String volumeId) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(
          path: '${_baseUrl.path}/$volumeId',
          queryParameters: {if (key.isNotEmpty) 'key': key},
        ),
        headers: _headers,
      ),
    );
    check(response);
    return decodeObject(response);
  }

  /// One volume as a match. A search item has only the thumbnail; the
  /// record ([large]) has bigger sizes too, the cache's from "medium".
  static LookupMatch? _match(Map<String, Object?> item, {bool large = false}) {
    final volumeId = stringAt(item, 'id');
    final info = item['volumeInfo'] as Map<String, Object?>? ?? const {};
    final title = stringAt(info, 'title');
    if (volumeId == null || title == null) return null;
    final text = stringAt(info, 'description');
    final links = info['imageLinks'] as Map<String, Object?>? ?? const {};
    final thumb = stringAt(links, 'thumbnail');
    final big = large
        ? stringAt(links, 'medium') ??
              stringAt(links, 'small') ??
              stringAt(links, 'large')
        : null;
    final pages = info['pageCount'];
    final authors = [
      for (final a in info['authors'] as List? ?? const [])
        if (a is String && a.isNotEmpty) a,
    ];
    final date = stringAt(info, 'publishedDate')?.split('T').first;
    // Categories read "Fiction / Literary"; each part is a candidate tag.
    final tags = <String>[];
    for (final c in info['categories'] as List? ?? const []) {
      for (final part in '$c'.split('/').map((p) => p.trim())) {
        if (part.toLowerCase() != 'general' &&
            isTagLike(part) &&
            !tags.contains(part)) {
          tags.add(part);
        }
      }
    }
    return LookupMatch(
      type: MediaType.books,
      title: title,
      source: '$id:$volumeId',
      released: date == null ? null : Released.tryParse(date),
      creator: authors.isEmpty ? null : authors.join(', '),
      description: text == null ? '' : stripHtml(text),
      tags: tags.take(maxBookTags).toList(),
      pages: pages is num && pages > 0 ? pages.toInt() : null,
      coverUrl: thumb == null ? null : cleanCoverUrl(thumb),
      largeCoverUrl: big == null ? null : cleanCoverUrl(big),
    );
  }

  /// Google's thumbnails come over http with a page-curl effect baked in.
  static String cleanCoverUrl(String url) => url
      .replaceFirst(RegExp(r'^http://'), 'https://')
      .replaceAll('&edge=curl', '');
}

/// How many subjects or categories become tag suggestions; the form keeps
/// six at most.
const maxBookTags = 6;

/// Whether two book hits are the same book: the same title (as
/// [sameTitle]) and an author in common, case and punctuation aside; two
/// hits without an author need only the title.
bool sameBook(LookupMatch a, LookupMatch b) {
  if (!sameTitle(a.title, b.title)) return false;
  final left = _authorKeys(a.creator);
  final right = _authorKeys(b.creator);
  if (left.isEmpty || right.isEmpty) return left.isEmpty && right.isEmpty;
  return left.any(right.contains);
}

Set<String> _authorKeys(String? creator) => {
  for (final name in (creator ?? '').split(','))
    if (name.trim().isNotEmpty)
      name.toLowerCase().replaceAll(
        RegExp(r'[^\p{L}\p{N}]+', unicode: true),
        '',
      ),
};
