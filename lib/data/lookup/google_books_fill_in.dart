import 'package:http/http.dart' as http;

import '../net/http_transport.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'rate_limiter.dart';
import 'text_clean.dart';

/// What [GoogleBooksFillIn.lookUp] found; null where Google Books has
/// nothing.
typedef GoogleBooksFill = ({String? description, String? coverUrl, int? pages});

/// What Google Books knows about a book that Open Library may not: a
/// description, a cover and a page count. Asked only to fill a gap after a match was made
/// elsewhere; it never produces a match or an id of its own. Works without
/// a key, with a smaller quota.
class GoogleBooksFillIn with LookupHttp {
  GoogleBooksFillIn(
    this.client, {
    this.key = '',
    Uri? baseUrl,
    this.timeout = defaultHttpTimeout,
    this.userAgent = 'Libri',
  }) : _baseUrl =
           baseUrl ?? Uri.https('www.googleapis.com', '/books/v1/volumes'),
       limiter = RateLimiter(const Duration(milliseconds: 500));

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

  /// A description, a cover and a page count for [title] (by [author] when
  /// known), each null when Google Books has none. The search lists up to ten volumes;
  /// their records often leave the description out, so when none has one
  /// the first volume's own record is read too. Throws [LookupException]
  /// on failure.
  Future<GoogleBooksFill> lookUp(String title, {String? author}) async {
    final q = [
      'intitle:"$title"',
      if (author != null && author.isNotEmpty) 'inauthor:"$author"',
    ].join(' ');
    final response = await send(
      () => client.get(
        _baseUrl.replace(
          queryParameters: {
            'q': q,
            'printType': 'books',
            'projection': 'full',
            'maxResults': '10',
            if (key.isNotEmpty) 'key': key,
          },
        ),
        headers: _headers,
      ),
    );
    check(response);
    String? description;
    String? cover;
    int? pages;
    String? firstId;
    for (final item in objectsAt(decodeObject(response), 'items')) {
      firstId ??= stringAt(item, 'id');
      final found = _read(item);
      description ??= found.description;
      cover ??= found.coverUrl;
      pages ??= found.pages;
      if (description != null && cover != null && pages != null) break;
    }
    if (description == null && firstId != null) {
      final record = await send(
        () => client.get(
          _baseUrl.replace(
            path: '${_baseUrl.path}/$firstId',
            queryParameters: {if (key.isNotEmpty) 'key': key},
          ),
          headers: _headers,
        ),
      );
      check(record);
      final found = _read(decodeObject(record));
      description = found.description;
      cover ??= found.coverUrl;
      pages ??= found.pages;
    }
    return (description: description, coverUrl: cover, pages: pages);
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  /// What one volume record carries.
  static GoogleBooksFill _read(Map<String, Object?> item) {
    final info = item['volumeInfo'] as Map<String, Object?>? ?? const {};
    final text = stringAt(info, 'description');
    final links = info['imageLinks'] as Map<String, Object?>? ?? const {};
    final thumb = stringAt(links, 'thumbnail');
    final pages = info['pageCount'];
    return (
      description: text == null ? null : stripHtml(text),
      coverUrl: thumb == null ? null : cleanCoverUrl(thumb),
      pages: pages is num && pages > 0 ? pages.toInt() : null,
    );
  }

  /// Google's thumbnails come over http with a page-curl effect baked in.
  static String cleanCoverUrl(String url) => url
      .replaceFirst(RegExp(r'^http://'), 'https://')
      .replaceAll('&edge=curl', '');
}
