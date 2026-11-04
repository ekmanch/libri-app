import '../models/entry_kind.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../models/follow_kind.dart';
import '../models/season.dart';
import '../models/season_span.dart';
import '../models/season_split.dart';
import '../models/series.dart';
import '../upcoming/creator_lookup.dart';
import '../upcoming/creator_status.dart';
import 'episode_info.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'lookup_source.dart';
import 'movie_dates.dart';
import 'text_clean.dart';

/// Movies and shows from TMDB. Ids are "tmdb:movie:603" and "tmdb:tv:1399".
/// The search gives title, date, overview and poster; the director or the
/// show's creators, the genres, a show's seasons and a movie's collection
/// (its series, Library › Movie in a series) come with [details], fetched
/// when a match is picked.
class TmdbSource extends HttpLookupSource implements CreatorLookup {
  TmdbSource(super.client, {required this.token, Uri? baseUrl, super.timeout})
    : _baseUrl = baseUrl ?? Uri.https('api.themoviedb.org', '/3/'),
      super(minGap: const Duration(milliseconds: 50));

  /// The API read access token (a Bearer), empty when not set up.
  final String token;
  final Uri _baseUrl;

  /// How many of the billed cast a match carries (Add / edit entry suggests
  /// that many).
  static const topBilled = 3;

  static const _images = 'https://image.tmdb.org/t/p/';

  /// Poster widths: rows show a 44 dp thumbnail, the cache keeps the list
  /// and details size.
  static const rowPosterWidth = 'w185';
  static const coverPosterWidth = 'w342';

  @override
  String get id => 'tmdb';

  @override
  String get name => 'TMDB';

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
      language: stringAt(item, 'original_language'),
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
    // A movie in a collection: the collection is its series, and its number
    // is its place among the parts by date.
    final series = tv ? null : await _seriesOf(json, match.source);
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
      series: series,
      language: stringAt(json, 'original_language'),
      // A show's first network is its Streaming tag (#netflix), when the
      // library has one; see creator_tags.dart.
      network: tv
          ? [for (final n in objectsAt(json, 'networks')) ?stringAt(n, 'name')]
                .firstOrNull
          : null,
      coverUrl: poster == null ? null : '$_images$rowPosterWidth$poster',
    );
  }

  /// The collection a movie record says it belongs to, as a series with the
  /// movie's number in it; null when it is in none.
  Future<Series?> _seriesOf(Map<String, Object?> movie, String source) async {
    final parts = await _collectionOf(movie);
    if (parts == null) return null;
    final number = parts.parts.where((p) => p.source == source).firstOrNull;
    return Series(name: parts.name, number: number?.number);
  }

  /// `/collection/{id}` for the collection in [movie]'s
  /// `belongs_to_collection`: the parts in date order, numbered from 1, a
  /// part without a date last. TMDB names collections "X Collection"; the
  /// series is "X".
  Future<SeriesParts?> _collectionOf(Map<String, Object?> movie) async {
    final collection = movie['belongs_to_collection'];
    if (collection is! Map<String, Object?>) return null;
    final id = collection['id'];
    if (id is! num) return null;
    final json = await _get('collection/${id.toInt()}');
    final name = collectionName(
      stringAt(json, 'name') ?? stringAt(collection, 'name') ?? '',
    );
    if (name.isEmpty) return null;
    final parts =
        [
          for (final p in objectsAt(json, 'parts'))
            if (p['id'] case final num partId)
              if (stringAt(p, 'title') case final title?)
                (
                  id: partId.toInt(),
                  title: title,
                  released: Released.tryParse(
                    stringAt(p, 'release_date') ?? '',
                  ),
                  poster: stringAt(p, 'poster_path'),
                ),
        ]..sort((a, b) {
          final x = a.released, y = b.released;
          if (x == null || y == null) {
            return x == null ? (y == null ? 0 : 1) : -1;
          }
          return x.availableFrom.compareTo(y.availableFrom);
        });
    return (
      name: name,
      parts: [
        for (final (i, p) in parts.indexed)
          (
            number: i + 1,
            title: p.title,
            year: p.released?.year,
            released: p.released,
            source: 'tmdb:movie:${p.id}',
            creator: null,
            cover: p.poster == null
                ? null
                : '$_images$coverPosterWidth${p.poster}',
            extra: false,
          ),
      ],
    );
  }

  /// "The Lord of the Rings" from TMDB's "The Lord of the Rings Collection".
  static String collectionName(String name) => name
      .replaceAll(RegExp(r'\s+collection$', caseSensitive: false), '')
      .trim();

  /// A movie's collection, for the Series section; null for a show or a
  /// movie in no collection.
  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    final (kind, id) = _parse(source);
    if (kind != 'movie') return null;
    return _collectionOf(await _get('movie/$id'));
  }

  /// A movie's release date as TMDB has it now (`/movie/{id}`), for the
  /// daily check of movies not out yet; null for a show, whose seasons
  /// carry the dates, and for a movie TMDB has no date for.
  @override
  Future<Released?> releaseDate(String source) async {
    final (kind, id) = _parse(source);
    if (kind != 'movie') return null;
    final json = await _get('movie/$id');
    return Released.tryParse(stringAt(json, 'release_date') ?? '');
  }

  /// A movie's dates by kind from `/movie/{id}/release_dates`, over every
  /// country (DESIGN.md 10c; there is no region setting): in cinemas the
  /// earliest theatrical date (type 3, else type 2, a limited release),
  /// digital the earliest digital date (type 4; a streaming premiere is
  /// recorded so). Null for a show; empty dates for a movie TMDB lists no
  /// such dates for.
  @override
  Future<MovieDates?> movieDates(String source) async {
    final (kind, id) = _parse(source);
    if (kind != 'movie') return null;
    return movieDatesFrom(await _get('movie/$id/release_dates'));
  }

  /// [movieDates] from the response's `results`.
  static MovieDates movieDatesFrom(Map<String, Object?> json) {
    Released? theatrical, limited, digital;
    Released? earlier(Released? a, Released? b) {
      if (a == null || b == null) return a ?? b;
      return b.availableFrom.isBefore(a.availableFrom) ? b : a;
    }

    for (final country in objectsAt(json, 'results')) {
      for (final release in objectsAt(country, 'release_dates')) {
        final date = Released.tryParse(
          (stringAt(release, 'release_date') ?? '').split('T').first,
        );
        if (date == null) continue;
        switch (release['type']) {
          case 3:
            theatrical = earlier(theatrical, date);
          case 2:
            limited = earlier(limited, date);
          case 4:
            digital = earlier(digital, date);
        }
      }
    }
    return MovieDates(cinema: theatrical ?? limited, digital: digital);
  }

  /// A show's seasons with their air dates, and with none for a season not
  /// dated yet. Season 0 holds the specials and is left out.
  static List<Season> _seasons(Map<String, Object?> json) => [
    for (final s in objectsAt(json, 'seasons'))
      if (s['season_number'] case final num number when number > 0)
        Season(
          season: number.toInt(),
          released: Released.tryParse(stringAt(s, 'air_date') ?? ''),
        ),
  ];

  /// The episode group types in the order their splits are offered after
  /// the show's own season list: Production, TV, Digital (a streaming
  /// service's seasons, named after it), then Story arc (one season per
  /// arc, the one Libri picks for a long run). Original air date, DVD and
  /// Absolute groups are left out (owner's decision, 2026-11-04: discs and
  /// air-date orders are not how anyone watches).
  static const _groupTypes = [6, 7, 4, 5];

  /// The story-arc type, and the digital (streaming) type.
  static const _arcsType = 5;
  static const _digitalType = 4;

  /// The streaming services a digital group can be named after, as the
  /// group's network or a word of its name ("Crunchyroll on Prime Video"
  /// is Crunchyroll's). The first found stands.
  static const _services = [
    'Netflix',
    'Crunchyroll',
    'Hulu',
    'Funimation',
    'Disney+',
    'Prime Video',
    'Apple TV',
    'Max',
    'HBO',
    'BBC iPlayer',
  ];

  /// How many episodes one season may hold before the show's own list is
  /// one long run ([SeasonSplit.long]).
  static const longRun = 100;

  /// The groups' details read this session, by group id: the group's type,
  /// the service it follows, and its seasons, each its name and its
  /// episodes in order (specials left out), so the form, the check and
  /// the season screen read each group once.
  final _groups = <String, _EpisodeGroup?>{};

  /// A show's episode groups as listed by `/tv/{id}/episode_groups`, read
  /// this session: their ids in [_groupTypes] order.
  final _groupLists = <String, List<String>>{};

  static String _groupId(String source) =>
      source.substring(SeasonSplit.tmdbGroupPrefix.length);

  /// The ids of the show's episode groups, in the order their splits are
  /// offered; empty when it has none (a 404 too).
  Future<List<String>> _groupIds(String id) async {
    if (_groupLists[id] case final ids?) return ids;
    final Map<String, Object?> list;
    try {
      list = await _get('tv/$id/episode_groups');
    } on LookupException catch (e) {
      if (e.status != 404) rethrow;
      return _groupLists[id] = const [];
    }
    final groups = [
      for (final g in objectsAt(list, 'results'))
        if (g['type'] case final num type
            when _groupTypes.contains(type.toInt()) &&
                stringAt(g, 'id') != null)
          (id: stringAt(g, 'id')!, type: type.toInt()),
    ];
    groups.sort(
      (a, b) =>
          _groupTypes.indexOf(a.type).compareTo(_groupTypes.indexOf(b.type)),
    );
    return _groupLists[id] = [for (final g in groups) g.id];
  }

  /// One episode group's seasons: `/tv/episode_group/{id}`, its groups in
  /// order with their episodes in order, those named as specials or extras
  /// and those without episodes left out. Null when TMDB no longer has it.
  Future<_EpisodeGroup?> _group(String groupId) async {
    if (_groups.containsKey(groupId)) return _groups[groupId];
    final Map<String, Object?> json;
    try {
      json = await _get('tv/episode_group/$groupId');
    } on LookupException catch (e) {
      if (e.status != 404) rethrow;
      return _groups[groupId] = null;
    }
    final special = RegExp(r'special|extra|ova', caseSensitive: false);
    final groups =
        [
          for (final g in objectsAt(json, 'groups'))
            if (!special.hasMatch(stringAt(g, 'name') ?? '')) g,
        ]..sort(
          (a, b) =>
              (a['order'] as num? ?? 0).compareTo(b['order'] as num? ?? 0),
        );
    final seasons = [
      for (final g in groups)
        if (objectsAt(g, 'episodes').toList() case final episodes
            when episodes.isNotEmpty)
          (
            name: stringAt(g, 'name'),
            episodes: episodes
              ..sort(
                (a, b) => (a['order'] as num? ?? 0).compareTo(
                  b['order'] as num? ?? 0,
                ),
              ),
          ),
    ];
    final type = (json['type'] as num?)?.toInt() ?? 0;
    final network = json['network'];
    return _groups[groupId] = (
      type: type,
      service: type == _digitalType
          ? _serviceOf(
              network is Map<String, Object?>
                  ? stringAt(network, 'name')
                  : null,
              stringAt(json, 'name'),
            )
          : null,
      seasons: seasons,
    );
  }

  /// The service a digital group follows: its network, else the first of
  /// [_services] in its name; null for neither.
  static String? _serviceOf(String? network, String? name) {
    for (final service in _services) {
      for (final text in [network, name]) {
        if (text != null &&
            text.toLowerCase().contains(service.toLowerCase())) {
          return service;
        }
      }
    }
    return null;
  }

  /// A season's name as the group names it, worth showing: an arc's
  /// without a trailing "Arc" ("Hunter Exam Arc" reads "Hunter Exam"), a
  /// service's without an episode range ("East Blue (1-61)" reads "East
  /// Blue"); null for a bare "Season 3", "Temporada 3" or "S03", which the
  /// rows say themselves.
  static String? _seasonName(String? name) {
    var short = name?.trim() ?? '';
    short = short
        .replaceFirst(RegExp(r'\s*\([^)]*\d[^)]*\)\s*$'), '')
        .replaceFirst(RegExp(r'\s+arc$', caseSensitive: false), '')
        .trim();
    if (short.isEmpty) return null;
    final bare = RegExp(
      r'^(season|temporada|staffel|saison|stagione|cour|part|s)\s*\d+$',
      caseSensitive: false,
    );
    return bare.hasMatch(short) || RegExp(r'^\d+$').hasMatch(short)
        ? null
        : short;
  }

  /// A season of an episode group: dated by its first episode.
  static Released? _groupStart(List<Map<String, Object?>> episodes) {
    Released? first;
    for (final e in episodes) {
      final aired = Released.tryParse(stringAt(e, 'air_date') ?? '');
      if (aired == null) continue;
      if (first == null || aired.availableFrom.isBefore(first.availableFrom)) {
        first = aired;
      }
    }
    return first;
  }

  /// The split an episode group gives: one season per group, numbered
  /// from 1, with its episode count and the date of its first episode; a
  /// story-arc group's seasons carry the arc names, a service's its season
  /// names ([_seasonName]), and the service.
  static SeasonSplit _groupSplit(String groupId, _EpisodeGroup group) {
    final arcs = group.type == _arcsType;
    final named = arcs || group.service != null;
    return SeasonSplit(
      ids: ['${SeasonSplit.tmdbGroupPrefix}$groupId'],
      arcs: arcs,
      service: group.service,
      seasons: [
        for (final (i, season) in group.seasons.indexed)
          SeasonSpan(
            season: i + 1,
            name: named ? _seasonName(season.name) : null,
            episodes: season.episodes.length,
            released: _groupStart(season.episodes),
          ),
      ],
    );
  }

  /// A show's seasons: its own list. The kind of an anime from TMDB is
  /// always series.
  @override
  Future<ShowSeasons?> seasons(String source, {bool anime = false}) async {
    final (kind, id) = _parse(source);
    if (kind != 'tv') return null;
    final json = await _get('tv/$id');
    return (
      seasons: _seasons(json),
      canceled: json['status'] == 'Canceled',
      kind: anime ? EntryKind.series : null,
    );
  }

  /// A show's own seasons with their episode counts, specials left out:
  /// the "tmdb:seasons" split. Null for a movie.
  Future<List<SeasonSpan>?> seasonSpans(String source) async {
    final (kind, id) = _parse(source);
    if (kind != 'tv') return null;
    return [
      for (final s in objectsAt(await _get('tv/$id'), 'seasons'))
        if (s['season_number'] case final num number when number > 0)
          SeasonSpan(
            season: number.toInt(),
            episodes: (s['episode_count'] as num?)?.toInt(),
            released: Released.tryParse(stringAt(s, 'air_date') ?? ''),
          ),
    ];
  }

  /// The show's own season list, then every episode group of the
  /// [_groupTypes] in that order (section 10c): the list is one request
  /// and each group one more, read once a session. An anime's [tmdb] show
  /// stands in for a source that is not a show.
  /// The show [source] is, or an anime's [tmdb] show; null for neither.
  static String? _showOf(String source, String? tmdb) {
    if (source.startsWith('tmdb:tv:')) return source;
    return tmdb != null && tmdb.startsWith('tmdb:tv:') ? tmdb : null;
  }

  @override
  Future<List<SeasonSplit>?> seasonSplits(String source, {String? tmdb}) async {
    final show = _showOf(source, tmdb);
    if (show == null) return null;
    final spans = await seasonSpans(show);
    if (spans == null) return null;
    final splits = [
      SeasonSplit(
        ids: const [SeasonSplit.tmdbSeasonsId],
        long: spans.length == 1 && (spans.single.episodes ?? 0) > longRun,
        seasons: spans,
      ),
    ];
    for (final groupId in await _groupIds(_parse(show).$2)) {
      final group = await _group(groupId);
      if (group == null || group.seasons.isEmpty) continue;
      splits.add(_groupSplit(groupId, group));
    }
    return splits;
  }

  /// "tmdb:seasons": the show's own list; `tmdb:group:<id>`: that group's
  /// seasons, dated by their first episodes.
  @override
  Future<ShowSeasons?> splitSeasons(
    String source,
    String from, {
    bool anime = false,
    String? tmdb,
  }) async {
    final show = _showOf(source, tmdb);
    if (show == null) return null;
    if (from == SeasonSplit.tmdbSeasonsId) return seasons(show, anime: anime);
    if (!from.startsWith(SeasonSplit.tmdbGroupPrefix)) return null;
    final group = await _group(_groupId(from));
    if (group == null) return null;
    return (
      seasons: _groupSplit(_groupId(from), group).toSeasons(),
      canceled: false,
      kind: anime ? EntryKind.series : null,
    );
  }

  @override
  bool isOwnSplit(String? from) =>
      from == null || from == SeasonSplit.tmdbSeasonsId;

  /// Seasons' episodes read this session, by show id and season number,
  /// for [episodesFrom].
  final _seasonEpisodeCache = <(String, int), List<EpisodeInfo>>{};

  /// [count] episodes of the show with [source] in air order, from the one
  /// that aired on [start] (give or take a day, for time zones) on,
  /// across its seasons: how an anime season from AniList finds its
  /// episodes on a TMDB show that splits it otherwise (Frieren's season 2
  /// is TMDB's season 1, episodes 29 to 38). The search starts at the
  /// last season out by [start] and reads at most three seasons. Null when
  /// no episode aired on that day; fewer than [count] when TMDB has fewer.
  Future<List<EpisodeInfo>?> episodesFrom(
    String source,
    Released start,
    int count,
  ) async {
    final (kind, id) = _parse(source);
    if (kind != 'tv') return null;
    final day = start.availableFrom;
    final seasons = _seasons(await _get('tv/$id'))
      ..sort((a, b) => a.season.compareTo(b.season));
    var first = 0;
    for (final (i, s) in seasons.indexed) {
      final from = s.released?.availableFrom;
      if (from != null && !from.isAfter(day.add(const Duration(days: 1)))) {
        first = i;
      }
    }
    final read = <EpisodeInfo>[];
    int? at;
    for (final s in seasons.skip(first).take(3)) {
      final key = (id, s.season);
      read.addAll(
        _seasonEpisodeCache[key] ??=
            await seasonEpisodes(source, s.season) ?? const [],
      );
      at ??= read.indexWhere((e) {
        final aired = e.aired;
        if (aired == null || aired.day == null) return false;
        return aired.availableFrom.difference(day).inDays.abs() <= 1;
      });
      if (at == -1) at = null;
      if (at != null && read.length - at >= count) break;
    }
    if (at == null) return null;
    return read.sublist(at, (at + count).clamp(at, read.length));
  }

  /// One episode as TMDB lists it, numbered [number]. TMDB names an
  /// episode without a title "Episode 5"; that counts as no title.
  static EpisodeInfo _episode(Map<String, Object?> e, int number) => (
    number: number,
    title: switch (stringAt(e, 'name')?.trim()) {
      final name? when name.isNotEmpty && name != 'Episode $number' => name,
      _ => null,
    },
    aired: Released.tryParse(stringAt(e, 'air_date') ?? ''),
    runtime: switch (e['runtime']) {
      final num minutes when minutes > 0 => minutes.toInt(),
      _ => null,
    },
  );

  /// `/tv/{id}/season/{n}`. A season TMDB does not know (404) has no
  /// episodes. In an episode group's split ([from] `tmdb:group:<id>`), the
  /// group's [season]th season instead, its episodes numbered from 1.
  @override
  Future<List<EpisodeInfo>?> seasonEpisodes(
    String source,
    int season, {
    bool anime = false,
    String? tmdb,
    String? from,
  }) async {
    final (kind, id) = _parse(source);
    if (kind != 'tv') return null;
    if (from != null && from.startsWith(SeasonSplit.tmdbGroupPrefix)) {
      final group = await _group(_groupId(from));
      if (group == null) return const [];
      if (season < 1 || season > group.seasons.length) return const [];
      return [
        for (final (i, e) in group.seasons[season - 1].episodes.indexed)
          _episode(e, i + 1),
      ];
    }
    final Map<String, Object?> json;
    try {
      json = await _get('tv/$id/season/$season');
    } on LookupException catch (e) {
      if (e.status == 404) return const [];
      rethrow;
    }
    final episodes = [
      for (final e in objectsAt(json, 'episodes'))
        if (e['episode_number'] case final num number)
          _episode(e, number.toInt()),
    ]..sort((a, b) => a.number.compareTo(b.number));
    return episodes;
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    final (kind, id) = _parse(source);
    final poster = stringAt(await _get('$kind/$id'), 'poster_path');
    return poster == null ? null : '$_images$coverPosterWidth$poster';
  }

  // Followed creators (Settings › Upcoming releases; DESIGN.md 10c).

  @override
  Set<FollowKind> get creatorKinds => const {
    FollowKind.directors,
    FollowKind.actors,
    FollowKind.studios,
  };

  /// Directors and actors are people: the most popular person of that name
  /// (TMDB's own order), with `deathday` saying whether they have died.
  /// Studios are companies, named exactly where one is, else the first;
  /// Wikidata says whether a company was dissolved.
  @override
  Future<CreatorMatch?> findCreator(FollowKind kind, String name) async {
    if (kind == FollowKind.studios) {
      final json = await _get('search/company', {'query': name});
      final hits = objectsAt(json, 'results');
      final exact = hits.where(
        (c) => (stringAt(c, 'name') ?? '').toLowerCase() == name.toLowerCase(),
      );
      final company = exact.firstOrNull ?? hits.firstOrNull;
      final id = company?['id'];
      if (id is! num) return null;
      return (providerId: 'tmdb:company:${id.toInt()}', inactive: null);
    }
    final json = await _get('search/person', {
      'query': name,
      'include_adult': 'false',
    });
    final id = objectsAt(json, 'results').firstOrNull?['id'];
    if (id is! num) return null;
    final person = await _get('person/${id.toInt()}');
    final deathday = stringAt(person, 'deathday');
    return (
      providerId: 'tmdb:person:${id.toInt()}',
      inactive: deathday == null
          ? null
          : Inactive(
              InactiveReason.died,
              year: Released.tryParse(deathday)?.year,
            ),
    );
  }

  /// How long after its first release a movie is still listed by a credit,
  /// so that its digital date, usually a few months after the cinemas, can
  /// be learned and shown (Settings › Movies › Release dates: Digital); the
  /// creator check applies the precise rule once it has the dates by kind.
  static const digitalWindow = 120;

  /// A person's credits: the movies and shows they directed (or created, for
  /// a show) or acted in; a company's movies by discover, from thirty days
  /// ago on, soonest first.
  @override
  Future<List<LookupMatch>> creatorReleases(
    String providerId,
    FollowKind kind, {
    required DateTime today,
  }) async {
    final parts = providerId.split(':');
    if (parts.length != 3 || parts[0] != 'tmdb') {
      throw LookupException(
        LookupFailure.other,
        message: 'not a TMDB creator id: $providerId',
      );
    }
    final id = parts[2];
    if (parts[1] == 'company') {
      final from = today.subtract(const Duration(days: 30));
      final json = await _get('discover/movie', {
        'with_companies': id,
        'sort_by': 'primary_release_date.asc',
        'primary_release_date.gte':
            '${from.year}-${from.month.toString().padLeft(2, '0')}-'
            '${from.day.toString().padLeft(2, '0')}',
        'include_adult': 'false',
      });
      return [
        for (final item in objectsAt(json, 'results'))
          ?_match(item, MediaType.movies),
      ];
    }
    if (parts[1] != 'person') {
      throw LookupException(
        LookupFailure.other,
        message: 'not a TMDB creator id: $providerId',
      );
    }
    final json = await _get('person/$id/combined_credits');
    final credits = kind == FollowKind.actors
        ? objectsAt(json, 'cast')
        : [
            for (final c in objectsAt(json, 'crew'))
              if (const {
                'Director',
                'Creator',
                'Showrunner',
              }.contains(c['job']))
                c,
          ];
    final seen = <Object?>{};
    return [
      for (final credit in credits)
        if (seen.add('${credit['media_type']}:${credit['id']}'))
          if (credit['media_type'] case final String media
              when media == 'movie' || media == 'tv')
            if (_match(
                  credit,
                  media == 'tv' ? MediaType.shows : MediaType.movies,
                )
                case final match?
                when isRecentOrAhead(match.released, today) ||
                    (match.type == MediaType.movies &&
                        isRecentOrAhead(
                          match.released,
                          today,
                          days: digitalWindow,
                        )))
              match,
    ]..sort(
      (a, b) => a.released!.availableFrom.compareTo(b.released!.availableFrom),
    );
  }
}

/// An episode group as TMDB has it: its type and its seasons, each with
/// its name and its episodes in order.
typedef _EpisodeGroup = ({
  int type,
  String? service,
  List<({String? name, List<Map<String, Object?>> episodes})> seasons,
});
