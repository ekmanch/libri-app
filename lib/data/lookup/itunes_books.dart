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

/// Apple Books through the iTunes Search API (`entity=ebook`, no key), the
/// second half of the book lookup (see `OpenLibrarySource`): it finds the
/// books Open Library does not have yet, with ids "itunes:6756269989", and
/// gives every book a description and a clean cover. Its date is the
/// ebook's release, not the first publication's, and it has no page count.
/// Apple allows about twenty requests a minute per address, so requests
/// keep [minGap] apart and a 403 counts as rate limited. Every method
/// throws [LookupException] on failure.
class ITunesBooks with LookupHttp {
  ITunesBooks(
    this.client, {
    Uri? baseUrl,
    this.timeout = defaultHttpTimeout,
    this.userAgent = 'Libri',
    Duration minGap = const Duration(seconds: 3),
  }) : _baseUrl = baseUrl ?? Uri.https('itunes.apple.com'),
       limiter = RateLimiter(minGap);

  @override
  final http.Client client;
  @override
  final Duration timeout;
  @override
  final String userAgent;
  @override
  final RateLimiter limiter;

  final Uri _baseUrl;

  /// The provider part of the ids it issues.
  static const id = 'itunes';

  /// The artwork sizes asked for: a row's, and the cache's.
  static const rowArtwork = 200;
  static const largeArtwork = 600;

  /// Apple lists one book per edition and language; only the first of the
  /// same title by the same author is kept.
  Future<List<LookupMatch>> search(String query, {int limit = 10}) async {
    final out = <LookupMatch>[];
    final hits = await _results('/search', {
      'term': query,
      'entity': 'ebook',
      'media': 'ebook',
      'limit': '${limit.clamp(1, 200)}',
    });
    for (final hit in hits) {
      if (!out.any((o) => sameBook(o, hit))) out.add(hit);
    }
    return out;
  }

  /// [search] for [title] (by [author] when known), for the cover matcher
  /// and the fill-ins.
  Future<List<LookupMatch>> searchTitle(
    String title, {
    String? author,
    int limit = 10,
  }) => search(
    [title, if (author != null && author.isNotEmpty) author].join(' '),
    limit: limit,
  );

  /// Every ebook for [title] (by [author] when known), editions and
  /// languages each on their own, for Add / edit entry › Pick a cover.
  Future<List<LookupMatch>> editions(
    String title, {
    String? author,
    int limit = 25,
  }) => _results('/search', {
    'term': [title, if (author != null && author.isNotEmpty) author].join(' '),
    'entity': 'ebook',
    'media': 'ebook',
    'limit': '${limit.clamp(1, 200)}',
  });

  /// The book's own record, or null when Apple has no book with that id.
  Future<LookupMatch?> book(String source) async {
    final hits = await _results('/lookup', {
      'id': trackId(source),
      'entity': 'ebook',
    });
    return hits.firstOrNull;
  }

  /// The track id of "itunes:6756269989".
  static String trackId(String source) {
    final parts = source.split(':');
    if (parts.length != 2 || parts[0] != id || parts[1].isEmpty) {
      throw LookupException(
        LookupFailure.other,
        message: 'not an Apple Books id: $source',
      );
    }
    return parts[1];
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  Future<List<LookupMatch>> _results(
    String path,
    Map<String, String> query,
  ) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(path: path, queryParameters: query),
        headers: _headers,
      ),
    );
    if (response.statusCode == 403) {
      throw LookupException(
        LookupFailure.rateLimited,
        status: 403,
        message: 'Apple refused the request (its rate limit)',
      );
    }
    check(response);
    return [
      for (final item in objectsAt(decodeObject(response), 'results'))
        ?_match(item),
    ];
  }

  /// One result as a match. The genres list "Books" among them, which no
  /// book needs as a tag.
  static LookupMatch? _match(Map<String, Object?> item) {
    final trackId = item['trackId'];
    final title = stringAt(item, 'trackName');
    if (trackId is! num || title == null) return null;
    final text = stringAt(item, 'description');
    final artwork = stringAt(item, 'artworkUrl100');
    final date = stringAt(item, 'releaseDate')?.split('T').first;
    final genres = [
      for (final g in item['genres'] as List? ?? const [])
        if (g is String && g != 'Books' && isTagLike(g)) g,
    ];
    final released = date == null ? null : Released.tryParse(date);
    return LookupMatch(
      type: MediaType.books,
      title: title,
      source: '$id:${trackId.toInt()}',
      released: released,
      releasedFromEbook: released != null,
      creator: stringAt(item, 'artistName'),
      description: text == null ? '' : stripHtml(text),
      tags: genres.take(maxBookTags).toList(),
      coverUrl: artwork == null ? null : artworkAt(artwork, rowArtwork),
      largeCoverUrl: artwork == null ? null : artworkAt(artwork, largeArtwork),
    );
  }

  /// [url] ("…/100x100bb.jpg") at [px] pixels square: Apple's image server
  /// renders any size on request. A URL of another shape is left as it is.
  static String artworkAt(String url, int px) =>
      url.replaceFirst(RegExp(r'/\d+x\d+(?=[a-z-]*\.\w+$)'), '/${px}x$px');
}
