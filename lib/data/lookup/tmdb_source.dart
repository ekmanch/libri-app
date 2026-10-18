import '../models/media_type.dart';
import '../models/released.dart';
import '../models/season.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'text_clean.dart';

/// Movies and shows from TMDB. Ids are "tmdb:movie:603" and "tmdb:tv:1399".
/// The search gives title, date, overview and poster; the director or the
/// show's creators and the genres come with [details], fetched when a
/// match is picked.
class TmdbSource extends HttpLookupSource {
  TmdbSource(super.client, {required this.token, Uri? baseUrl, super.timeout})
    : _baseUrl = baseUrl ?? Uri.https('api.themoviedb.org', '/3/'),
      super(minGap: const Duration(milliseconds: 50));

  /// The API read access token (a Bearer), empty when not set up.
  final String token;
  final Uri _baseUrl;

  /// How many of the billed cast a match carries (A8 suggests that many).
  static const topBilled = 3;

  static const _images = 'https://image.tmdb.org/t/p/';

  /// Poster widths: rows show a 44 dp thumbnail, the cache keeps the list
  /// and details size.
  static const rowPosterWidth = 'w185';
  static const coverPosterWidth = 'w342';

  @override
  String get id => 'tmdb';

  @override
  Set<MediaType> get types => const {MediaType.movies, MediaType.shows};

  @override
  bool get isConfigured => token.isNotEmpty;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      _baseUrl.resolve(path).replace(queryParameters: query);

  static String _kind(MediaType type) =>
      type == MediaType.shows ? 'tv' : 'movie';

  Future<Map<String, Object?>> _get(
    String path, [
    Map<String, String>? q,
  ]) async {
    requireConfigured();
    final response = await send(
      () => client.get(_uri(path, q), headers: _headers),
    );
    check(response);
    return decodeObject(response);
  }

  Future<List<LookupMatch>> _search(String query, MediaType type) async {
    final kind = _kind(type);
    final json = await _get('search/$kind', {
      'query': query,
      'include_adult': 'false',
    });
    return [for (final item in objectsAt(json, 'results')) ?_match(item, type)];
  }

  LookupMatch? _match(Map<String, Object?> item, MediaType type) {
    final tv = type == MediaType.shows;
    final title = stringAt(item, tv ? 'name' : 'title');
    final id = item['id'];
    if (title == null || id is! num) return null;
    final date = stringAt(item, tv ? 'first_air_date' : 'release_date');
    final poster = stringAt(item, 'poster_path');
    return LookupMatch(
      type: type,
      title: title,
      source: 'tmdb:${_kind(type)}:${id.toInt()}',
      released: date == null ? null : Released.tryParse(date),
      description: stringAt(item, 'overview') ?? '',
      coverUrl: poster == null ? null : '$_images$rowPosterWidth$poster',
      largeCoverUrl: poster == null ? null : '$_images$coverPosterWidth$poster',
    );
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async => (await _search(query, type)).take(limit).toList();

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    return pickByTitleAndYear(
      await _search(title, type),
      title,
      year: year,
      titleOf: (m) => m.title,
      yearOf: (m) => m.released?.year,
    );
  }

  /// "tmdb:movie:603" -> ("movie", "603"); anything else is "other".
  static (String kind, String id) _parse(String source) {
    final parts = source.split(':');
    if (parts.length != 3 ||
        parts[0] != 'tmdb' ||
        (parts[1] != 'movie' && parts[1] != 'tv')) {
      throw LookupException(
        LookupFailure.other,
        message: 'not a TMDB id: $source',
      );
    }
    return (parts[1], parts[2]);
  }

  @override
  Future<LookupMatch> details(LookupMatch match) async {
    final (kind, id) = _parse(match.source);
    // The credits carry the director (movies) and the billed cast (both).
    final json = await _get('$kind/$id', const {
      'append_to_response': 'credits',
    });
    final credits = json['credits'] as Map<String, Object?>? ?? const {};
    final tv = kind == 'tv';
    final creators = tv
        ? [for (final c in objectsAt(json, 'created_by')) ?stringAt(c, 'name')]
        : [
            for (final c in objectsAt(credits, 'crew'))
              if (c['job'] == 'Director') ?stringAt(c, 'name'),
          ];
    // TMDB lists the cast in billing order; the form takes the top three.
    final cast = [
      for (final c in objectsAt(credits, 'cast').take(topBilled))
        ?stringAt(c, 'name'),
    ];
    final date = stringAt(json, tv ? 'first_air_date' : 'release_date');
    final poster = stringAt(json, 'poster_path');
    return match.copyWith(
      creator: creators.isEmpty ? null : creators.join(', '),
      released: date == null ? null : Released.tryParse(date),
      description: stringAt(json, 'overview'),
      // The studio's tag comes from these (#pixar), see creator_tags.dart.
      companies: [
        for (final c in objectsAt(json, 'production_companies'))
          ?stringAt(c, 'name'),
      ],
      cast: cast,
      tags: [for (final g in objectsAt(json, 'genres')) ?stringAt(g, 'name')],
      seasons: tv ? _seasons(json) : const [],
      coverUrl: poster == null ? null : '$_images$rowPosterWidth$poster',
    );
  }

  /// A show's seasons with their air dates. Season 0 holds the specials,
  /// and a season without an air date is not announced yet; both are left
  /// out.
  static List<Season> _seasons(Map<String, Object?> json) => [
    for (final s in objectsAt(json, 'seasons'))
      if (s['season_number'] case final num number when number > 0)
        if (Released.tryParse(stringAt(s, 'air_date') ?? '') case final date?)
          Season(season: number.toInt(), released: date),
  ];

  @override
  Future<List<Season>?> seasons(String source) async {
    final (kind, id) = _parse(source);
    if (kind != 'tv') return null;
    return _seasons(await _get('tv/$id'));
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    final (kind, id) = _parse(source);
    final poster = stringAt(await _get('$kind/$id'), 'poster_path');
    return poster == null ? null : '$_images$coverPosterWidth$poster';
  }
}
