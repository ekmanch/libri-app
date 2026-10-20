import 'package:http/http.dart' as http;

import '../models/media_type.dart';
import '../models/released.dart';
import '../net/http_transport.dart';
import 'book_match.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'rate_limiter.dart';
import 'text_clean.dart';

/// Google Books, read by id only: one volume, "googlebooks:eOTEEQAAQBAJ",
/// for the books found while its search was a source (2026-10-19 to
/// 2026-10-20, see `OpenLibrarySource`). Its text search answered 503 to
/// most requests that month while reading a volume by id kept working, so
/// Apple Books took its place in the search and nothing issues its ids any
/// more. Works without a key, with a smaller quota. Every method throws
/// [LookupException] on failure.
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

  /// The provider part of the ids it issued.
  static const id = 'googlebooks';

  /// The volume's own record, with its description and the larger covers;
  /// null when it has no title.
  Future<LookupMatch?> volume(String source) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(
          path: '${_baseUrl.path}/${volumeId(source)}',
          queryParameters: {if (key.isNotEmpty) 'key': key},
        ),
        headers: {'Accept': 'application/json', 'User-Agent': userAgent},
      ),
    );
    check(response);
    return _match(decodeObject(response));
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

  /// One volume as a match: the thumbnail for a row, and the cache's from
  /// "medium" down.
  static LookupMatch? _match(Map<String, Object?> item) {
    final volumeId = stringAt(item, 'id');
    final info = item['volumeInfo'] as Map<String, Object?>? ?? const {};
    final title = stringAt(info, 'title');
    if (volumeId == null || title == null) return null;
    final text = stringAt(info, 'description');
    final links = info['imageLinks'] as Map<String, Object?>? ?? const {};
    final thumb = stringAt(links, 'thumbnail');
    final big =
        stringAt(links, 'medium') ??
        stringAt(links, 'small') ??
        stringAt(links, 'large');
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
