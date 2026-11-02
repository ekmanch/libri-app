import 'dart:convert';

import '../models/entry_kind.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../models/season.dart';
import '../models/season_span.dart';
import 'anime_link_store.dart';
import 'episode_info.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'languages.dart';
import 'lookup_match.dart';
import 'lookup_source.dart';
import 'text_clean.dart';
import 'tmdb_source.dart';

/// Anime from AniList's GraphQL API. No key. Ids are "anilist:21". The
/// search carries everything the form needs for an anime movie; an anime
/// series (AniList's TV, TV short, ONA and OVA formats, see [kindOf]) also
/// gets its seasons with [details], the same way a show does (Show & seasons
/// › Anime with seasons (Frieren)). The seasons come from AniList's chain:
/// the series' entries are walked back along the prequel relations to the
/// first one, then forward along the sequels, and every TV, TV short or ONA
/// entry in it is a season (a "Part 2" is its own season) with its own
/// episode count and dates; movies, OVAs, specials and recaps are left out.
/// A sequel not out yet is a season dated by its start, as precise as
/// AniList has it. The episodes are "Episode N" with their air dates from
/// AniList's airing schedule.
///
/// TMDB ([tmdb]) gives the episodes their titles: the series' first entry
/// is matched to a TMDB show, kept in [links], and each season's episodes
/// are found there by air date ([seasonEpisodes]). The daily check also
/// reads an old link's split once, for an anime whose seasons came from
/// TMDB before ([resplit]).
///
/// AniList allows about 30 requests a minute, hence the gap.
class AniListSource extends HttpLookupSource {
  AniListSource(
    super.client, {
    this.tmdb,
    AnimeLinkStore? links,
    Uri? baseUrl,
    super.timeout,
  }) : links = links ?? MemoryAnimeLinkStore(),
       _baseUrl = baseUrl ?? Uri.https('graphql.anilist.co'),
       super(minGap: const Duration(seconds: 2));

  /// Where the old split of an anime's seasons is read for [resplit]; null
  /// in a build without TMDB.
  final TmdbSource? tmdb;

  /// The kind per anime, and the TMDB show its seasons came from before,
  /// kept on the phone.
  final AnimeLinkStore links;

  final Uri _baseUrl;

  /// How long an anime whose format AniList does not say yet waits before
  /// it is asked again.
  static const retryAfter = Duration(days: 1);

  /// How far a prequel or sequel chain is followed, each way.
  static const maxHops = 60;

  /// Episodes per airing-schedule page, and how many pages are read at
  /// most (AniList lists one entry's episodes; 500 covers any season).
  static const _schedulePage = 50;
  static const _schedulePages = 10;

  /// The chains walked this session, by any entry in them.
  final _chains = <int, List<AniNode>>{};

  static const _fields = '''
      id
      format
      title { romaji english }
      startDate { year month day }
      description(asHtml: false)
      coverImage { large extraLarge }
      studios(isMain: true) { nodes { name } }
      countryOfOrigin
      genres''';

  /// The search, each hit with its prequels two deep (ids and formats
  /// only), so later seasons fold into the first ([_search]).
  static const _searchQuery =
      '''
query (\$search: String, \$perPage: Int) {
  Page(perPage: \$perPage) {
    media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
$_fields
      relations { edges { relationType node { id format
        relations { edges { relationType node { id format } } }
      } } }
    }
  }
}''';

  /// The first entries of series whose later seasons a search found
  /// without them.
  static const _byIdsQuery =
      '''
query (\$ids: [Int], \$perPage: Int) {
  Page(perPage: \$perPage) {
    media(id_in: \$ids, type: ANIME) {
$_fields
    }
  }
}''';

  static const _byIdQuery =
      '''
query (\$id: Int) {
  Media(id: \$id, type: ANIME) {
$_fields
  }
}''';

  /// What a chain needs of an entry.
  static const _node = '''
      id
      format
      status
      title { romaji english }
      startDate { year month day }
      endDate { year month day }
      episodes
      duration''';

  /// An entry with its relations two deep, so a short chain costs one
  /// request and a long one a request every two hops.
  static const _chainQuery =
      '''
query (\$id: Int) {
  Media(id: \$id, type: ANIME) {
$_node
    relations { edges { relationType node {
$_node
      relations { edges { relationType node {
$_node
      } } }
    } } }
  }
}''';

  static const _scheduleQuery = '''
query (\$id: Int, \$page: Int, \$perPage: Int) {
  Media(id: \$id, type: ANIME) {
    airingSchedule(page: \$page, perPage: \$perPage) {
      pageInfo { hasNextPage }
      nodes { episode airingAt }
    }
  }
}''';

  @override
  String get id => 'anilist';

  @override
  String get name => 'AniList';

  @override
  Set<MediaType> get types => const {MediaType.anime};

  /// An AniList format as a kind: TV, TV short, ONA and OVA are a series
  /// (seasons, like a show); a movie, a special or a music video is a
  /// movie (one date). Null for no format, or one that is neither.
  static EntryKind? kindOf(String? format) => switch (format) {
    'TV' || 'TV_SHORT' || 'ONA' || 'OVA' => EntryKind.series,
    'MOVIE' || 'SPECIAL' || 'MUSIC' => EntryKind.movie,
    _ => null,
  };

  Future<Map<String, Object?>> _query(
    String query,
    Map<String, Object?> variables,
  ) async {
    final response = await send(
      () => client.post(
        _baseUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': userAgent,
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    // AniList answers 404 for an unknown id with an errors array; anything
    // else that is not 200 is a real failure.
    check(response, ok: const {200, 404});
    final json = decodeObject(response);
    final errors = json['errors'];
    final data = json['data'] as Map<String, Object?>?;
    if (data == null) {
      throw LookupException(
        LookupFailure.other,
        status: response.statusCode,
        message: errors is List && errors.isNotEmpty
            ? '${(errors.first as Map)['message']}'
            : 'no data',
      );
    }
    return data;
  }

  static Released? _date(Object? date) {
    if (date is! Map<String, Object?>) return null;
    final year = date['year'];
    if (year is! num) return null;
    return Released(
      year.toInt(),
      (date['month'] as num?)?.toInt(),
      (date['day'] as num?)?.toInt(),
    );
  }

  LookupMatch? _match(Map<String, Object?> media) {
    final id = media['id'];
    final titles = media['title'] as Map<String, Object?>? ?? const {};
    final title = stringAt(titles, 'english') ?? stringAt(titles, 'romaji');
    if (id is! num || title == null) return null;
    final studios =
        (media['studios'] as Map<String, Object?>?)?['nodes'] as List? ??
        const [];
    final creators = [
      for (final s in studios)
        if (s is Map<String, Object?>) ?stringAt(s, 'name'),
    ];
    final cover = media['coverImage'] as Map<String, Object?>? ?? const {};
    return LookupMatch(
      type: MediaType.anime,
      title: title,
      source: 'anilist:${id.toInt()}',
      released: _date(media['startDate']),
      creator: creators.isEmpty ? null : creators.join(', '),
      companies: creators,
      description: stripHtml(stringAt(media, 'description') ?? ''),
      tags: [for (final g in media['genres'] as List? ?? const []) '$g'],
      kind: kindOf(stringAt(media, 'format')),
      language: languageOfCountry(stringAt(media, 'countryOfOrigin')),
      coverUrl: stringAt(cover, 'large'),
      largeCoverUrl: stringAt(cover, 'extraLarge'),
    );
  }

  /// The series prequel of an entry as the search lists it (a season
  /// before it, not a movie it follows), or null.
  static Map<String, Object?>? _prequel(Map<String, Object?> media) {
    final relations = media['relations'];
    if (relations is! Map<String, Object?>) return null;
    for (final edge in objectsAt(relations, 'edges')) {
      final node = edge['node'];
      if (edge['relationType'] == 'PREQUEL' &&
          node is Map<String, Object?> &&
          node['id'] is num &&
          _rank(stringAt(node, 'format')) < 3) {
        return node;
      }
    }
    return null;
  }

  /// The id of the first season of the series a hit is a later season of
  /// (as far back as the search's two levels of prequels reach), or null
  /// for a hit that is no later season.
  static int? _firstSeasonOf(Map<String, Object?> media) {
    if (kindOf(stringAt(media, 'format')) != EntryKind.series) return null;
    int? first;
    Map<String, Object?>? current = media;
    for (var depth = 0; depth < 2 && current != null; depth++) {
      current = _prequel(current);
      if (current != null) first = (current['id'] as num).toInt();
    }
    return first;
  }

  /// A series is one entry with seasons, so a hit that is a later season
  /// (Frieren's "2nd Season", "3rd Season") is folded into the first one:
  /// listed once, where the first of them stood. A first season the search
  /// did not find is fetched by id.
  Future<List<LookupMatch>> _search(String query, {int limit = 10}) async {
    final data = await _query(_searchQuery, {
      'search': query,
      'perPage': limit,
    });
    final page = data['Page'] as Map<String, Object?>? ?? const {};
    final hits = <int, Map<String, Object?>>{};
    final order = <int>[];
    for (final media in objectsAt(page, 'media')) {
      final id = media['id'];
      if (id is! num) continue;
      hits[id.toInt()] = media;
      final shown = _firstSeasonOf(media) ?? id.toInt();
      if (!order.contains(shown)) order.add(shown);
    }
    final missing = [
      for (final id in order)
        if (!hits.containsKey(id)) id,
    ];
    if (missing.isNotEmpty) {
      final found = await _query(_byIdsQuery, {
        'ids': missing,
        'perPage': missing.length,
      });
      final more = found['Page'] as Map<String, Object?>? ?? const {};
      for (final media in objectsAt(more, 'media')) {
        if (media['id'] case final num id) hits[id.toInt()] = media;
      }
    }
    return [
      for (final id in order)
        if (hits[id] case final media?) ?_match(media),
    ];
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) => _search(query, limit: limit);

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    return pickByTitleAndYear(
      await _search(title, limit: 5),
      title,
      year: year,
      titleOf: (m) => m.title,
      yearOf: (m) => m.released?.year,
    );
  }

  /// A series gets its seasons, as a show does from TMDB; a movie is
  /// complete from the search.
  @override
  Future<LookupMatch> details(LookupMatch match) async {
    if (match.kind != EntryKind.series) return match;
    final found = await seasons(match.source);
    return match.copyWith(
      seasons: found?.seasons ?? const [],
      tmdb: await tmdbShow(match.source),
    );
  }

  static int _parse(String source) {
    final parts = source.split(':');
    final id = parts.length == 2 && parts[0] == 'anilist'
        ? int.tryParse(parts[1])
        : null;
    if (id == null) {
      throw LookupException(
        LookupFailure.other,
        message: 'not an AniList id: $source',
      );
    }
    return id;
  }

  // ---- Seasons ----

  /// Parses an entry and, when its relations came with it, the entries
  /// they point at, into [nodes]. An entry seen with its relations is kept
  /// over the same one seen without.
  static AniNode _parseNode(
    Map<String, Object?> media,
    Map<int, AniNode> nodes,
  ) {
    final id = (media['id'] as num).toInt();
    final titles = media['title'] as Map<String, Object?>? ?? const {};
    List<int>? prequels, sequels;
    if (media['relations'] case final Map<String, Object?> relations) {
      prequels = [];
      sequels = [];
      for (final edge in objectsAt(relations, 'edges')) {
        final node = edge['node'];
        if (node is! Map<String, Object?> || node['id'] is! num) continue;
        final related = _parseNode(node, nodes);
        switch (edge['relationType']) {
          case 'PREQUEL':
            prequels.add(related.id);
          case 'SEQUEL':
            sequels.add(related.id);
        }
      }
    }
    final parsed = AniNode(
      id: id,
      format: stringAt(media, 'format'),
      status: stringAt(media, 'status'),
      english: stringAt(titles, 'english'),
      romaji: stringAt(titles, 'romaji'),
      start: _date(media['startDate']),
      end: _date(media['endDate']),
      episodes: (media['episodes'] as num?)?.toInt(),
      duration: (media['duration'] as num?)?.toInt(),
      prequels: prequels,
      sequels: sequels,
    );
    final known = nodes[id];
    if (known == null || !known.loaded || parsed.loaded) nodes[id] = parsed;
    return nodes[id]!;
  }

  /// How much a related entry is wanted as the next in a chain: a TV
  /// season over a TV short or an ONA, those over an OVA, and any series
  /// over a movie or a special.
  static int _rank(String? format) => switch (format) {
    'TV' => 0,
    'TV_SHORT' || 'ONA' => 1,
    'OVA' => 2,
    _ => 3,
  };

  /// Among related entries, the one [_rank] wants most (a TV sequel over a
  /// recap movie), the first of equals.
  static int? _pick(List<int> ids, Map<int, AniNode> nodes) {
    int? best;
    var bestRank = 4;
    for (final id in ids) {
      final rank = _rank(nodes[id]?.format);
      if (rank < bestRank) {
        best = id;
        bestRank = rank;
      }
    }
    return best;
  }

  /// The chain of entries the anime [id] is part of, first to last, walked
  /// back along the prequels and forward along the sequels. A movie, a
  /// special or anything else that is not a series is its own chain.
  Future<List<AniNode>> _chain(int id) async {
    if (_chains[id] case final chain?) return chain;
    final nodes = <int, AniNode>{};
    Future<AniNode> load(int id) async {
      final known = nodes[id];
      if (known != null && known.loaded) return known;
      final media = (await _query(_chainQuery, {'id': id}))['Media'];
      if (media is! Map<String, Object?> || media['id'] is! num) {
        throw LookupException(LookupFailure.other, message: 'no anime $id');
      }
      return _parseNode(media, nodes);
    }

    var current = await load(id);
    if (!current.isSeries) return _chains[id] = [current];
    final behind = {id};
    for (var hops = 0; hops < maxHops; hops++) {
      final previous = _pick(current.prequels!, nodes);
      if (previous == null || behind.contains(previous)) break;
      behind.add(previous);
      current = await load(previous);
    }
    final chain = [current];
    final ahead = {current.id};
    for (var hops = 0; hops < maxHops; hops++) {
      final next = _pick(current.sequels!, nodes);
      if (next == null || ahead.contains(next)) break;
      ahead.add(next);
      current = await load(next);
      chain.add(current);
    }
    for (final node in chain) {
      _chains[node.id] = chain;
    }
    return chain;
  }

  /// The entries of a chain that are seasons: TV, TV short and ONA, recaps
  /// left out. A chain with none of those (a series made only of OVAs) has
  /// its OVAs as seasons.
  static List<AniNode> seasonEntries(List<AniNode> chain) {
    final seasons = [
      for (final node in chain)
        if (_rank(node.format) < 2 && !node.isRecap) node,
    ];
    if (seasons.isNotEmpty) return seasons;
    return [
      for (final node in chain)
        if (node.format == 'OVA' && !node.isRecap) node,
    ];
  }

  /// One season per entry, dated by the entry's start.
  static List<Season> chainSeasons(List<AniNode> chain) => [
    for (final (i, node) in seasonEntries(chain).indexed)
      Season(season: i + 1, released: node.start),
  ];

  bool get _tmdbReady => tmdb?.isConfigured ?? false;

  /// The anime's kind, from the store when it was answered before, else
  /// from AniList now. A kind AniList cannot say yet is asked again after
  /// [retryAfter].
  Future<AnimeLink> _link(int id) async {
    final now = DateTime.now();
    final stored = await links.read(id);
    if (stored != null &&
        (stored.kind != null || now.difference(stored.checked) < retryAfter)) {
      return stored;
    }
    final chain = await _chain(id);
    final entry = chain.firstWhere(
      (n) => n.id == id,
      orElse: () => chain.first,
    );
    final AnimeLink link = (
      kind: kindOf(entry.format),
      checked: now,
      tmdb: stored?.tmdb,
      tmdbChecked: stored?.tmdbChecked,
      resplit: stored?.resplit ?? false,
    );
    await links.write(id, link);
    return link;
  }

  /// How long a "no TMDB match" is believed before TMDB is asked again.
  static const tmdbRetryAfter = Duration(days: 14);

  /// The TMDB show the anime's episode titles come from: the series' first
  /// entry looked for by its English, then romaji title and its year. A
  /// match is kept for good and a miss for [tmdbRetryAfter]; nothing is
  /// kept when TMDB did not answer. Null without TMDB in the build.
  Future<String?> _tmdbMatch(int id) async {
    if (!_tmdbReady) return null;
    final now = DateTime.now();
    final stored = await links.read(id);
    if (stored?.tmdb case final linked?) return linked;
    if (stored?.tmdbChecked case final asked?
        when now.difference(asked) < tmdbRetryAfter) {
      return null;
    }
    final chain = await _chain(id);
    final root = chain.first;
    LookupMatch? hit;
    for (final title in {?root.english, ?root.romaji}) {
      hit = await tmdb!.match(
        title,
        type: MediaType.shows,
        year: root.start?.year,
      );
      if (hit != null) break;
    }
    final entry = chain.firstWhere(
      (n) => n.id == id,
      orElse: () => chain.first,
    );
    await links.write(id, (
      kind: stored?.kind ?? kindOf(entry.format),
      checked: stored?.checked ?? now,
      tmdb: hit?.source,
      tmdbChecked: now,
      resplit: stored?.resplit ?? false,
    ));
    return hit?.source;
  }

  /// A series' seasons, one per season entry of its AniList chain
  /// ([seasonEntries]). A movie has none. [kind] tells the daily check
  /// which an anime stored without one is.
  @override
  Future<ShowSeasons?> seasons(String source, {bool anime = false}) async {
    final id = _parse(source);
    final link = await _link(id);
    if (link.kind == EntryKind.movie) {
      return (seasons: const <Season>[], canceled: false, kind: link.kind);
    }
    final chain = await _chain(id);
    return (
      seasons: chainSeasons(chain),
      canceled: chain.last.status == 'CANCELLED',
      kind: link.kind,
    );
  }

  /// For an anime whose seasons came from a TMDB show before: that show's
  /// split, with each season's episode count, and the chain's. Null when
  /// it has nothing waiting to be re-split, or TMDB cannot be asked in this
  /// build.
  @override
  Future<SeasonResplit?> resplit(String source) async {
    final id = _parse(source);
    final stored = await links.read(id);
    final old = stored?.tmdb;
    if (old == null || stored?.resplit != true || !_tmdbReady) return null;
    final before = await tmdb!.seasonSpans(old);
    if (before == null) return null;
    final chain = await _chain(id);
    return (
      before: before,
      after: [
        for (final (i, node) in seasonEntries(chain).indexed)
          SeasonSpan(
            season: i + 1,
            episodes: node.episodes,
            released: node.start,
          ),
      ],
    );
  }

  /// Marks the re-split done: the seasons are AniList's from now on. The
  /// TMDB link stays, for the episode titles.
  @override
  Future<void> resplitSettled(String source) async {
    final id = _parse(source);
    final stored = await links.read(id);
    if (stored == null || !stored.resplit) return;
    await links.write(id, (
      kind: stored.kind,
      checked: stored.checked,
      tmdb: stored.tmdb,
      tmdbChecked: stored.tmdbChecked,
      resplit: false,
    ));
  }

  /// The TMDB show the anime's episode titles come from ([_tmdbMatch]); null
  /// when TMDB has none or cannot answer now.
  @override
  Future<String?> tmdbShow(String source) async {
    try {
      return await _tmdbMatch(_parse(source));
    } on LookupException {
      return null;
    }
  }

  /// Who the episodes of each anime came from, by source, as last read.
  final _episodesCredit = <String, String>{};

  /// "TMDB and AniList" when the last episodes read for [source] had titles
  /// from TMDB, else "AniList".
  @override
  String episodesProvider(String source) => _episodesCredit[source] ?? name;

  /// The episodes of the [season]th entry of the chain, as many as AniList
  /// counts, dated by AniList's airing schedule. Their titles (and lengths,
  /// and dates the schedule lacks) come from the TMDB show the series
  /// matched ([_tmdbMatch]): its episode that aired on the entry's start
  /// day, give or take one, and those after it, across TMDB's seasons
  /// ([TmdbSource.episodesFrom]), so TMDB's one season of 38 gives
  /// Frieren's season 2 its episodes 29 to 38. Without a match, or with
  /// no TMDB episode on that day, they are "Episode N" with the entry's
  /// episode length. A finished entry's episodes without any date are
  /// dated the entry's start, so they count as out; an unfinished one's
  /// are undated until scheduled.
  @override
  Future<List<EpisodeInfo>?> seasonEpisodes(
    String source,
    int season, {
    bool anime = false,
    String? tmdb,
  }) async {
    final id = _parse(source);
    final chain = await _chain(id);
    final entries = seasonEntries(chain);
    if (season < 1 || season > entries.length) return const [];
    final node = entries[season - 1];
    final schedule = <int, Released>{};
    for (var page = 1; page <= _schedulePages; page++) {
      final data = await _query(_scheduleQuery, {
        'id': node.id,
        'page': page,
        'perPage': _schedulePage,
      });
      final media = data['Media'] as Map<String, Object?>? ?? const {};
      final airing =
          media['airingSchedule'] as Map<String, Object?>? ?? const {};
      for (final item in objectsAt(airing, 'nodes')) {
        if (item case {
          'episode': final num episode,
          'airingAt': final num at,
        }) {
          final day = DateTime.fromMillisecondsSinceEpoch(
            at.toInt() * 1000,
            isUtc: true,
          );
          schedule[episode.toInt()] = Released(day.year, day.month, day.day);
        }
      }
      final info = airing['pageInfo'] as Map<String, Object?>? ?? const {};
      if (info['hasNextPage'] != true) break;
    }
    final count =
        node.episodes ??
        (schedule.isEmpty ? 0 : schedule.keys.reduce((a, b) => a > b ? a : b));
    final titled = await _tmdbEpisodes(id, node, count, linked: tmdb);
    _episodesCredit[source] = titled.any((e) => e.title != null)
        ? '${this.tmdb!.name} and $name'
        : name;
    final finished = node.status == 'FINISHED' ? node.start : null;
    return [
      for (var n = 1; n <= count; n++)
        (
          number: n,
          title: titled.elementAtOrNull(n - 1)?.title,
          aired:
              schedule[n] ?? titled.elementAtOrNull(n - 1)?.aired ?? finished,
          runtime: titled.elementAtOrNull(n - 1)?.runtime ?? node.duration,
        ),
    ];
  }

  /// TMDB's episodes for the chain entry [node], [count] of them from the
  /// one that aired on its start day, on the entry's TMDB show ([linked],
  /// `Entry.tmdb`) or else the one the series matches ([_tmdbMatch]); empty when there is no match or no
  /// such episode, or TMDB cannot answer now (the titles are a bonus: the
  /// episodes still come from AniList).
  Future<List<EpisodeInfo>> _tmdbEpisodes(
    int id,
    AniNode node,
    int count, {
    String? linked,
  }) async {
    final start = node.start;
    if (count == 0 || start == null || start.day == null) return const [];
    if (!_tmdbReady) return const [];
    try {
      final show = linked ?? await _tmdbMatch(id);
      if (show == null) return const [];
      return await tmdb!.episodesFrom(show, start, count) ?? const [];
    } on LookupException {
      return const [];
    }
  }

  /// The entry's start date as AniList has it now, for the daily check of
  /// anime not out yet (an anime movie, or one whose kind is not known
  /// yet; a series goes by its seasons).
  @override
  Future<Released?> releaseDate(String source) async {
    final data = await _query(_byIdQuery, {'id': _parse(source)});
    final media = data['Media'] as Map<String, Object?>?;
    return media == null ? null : _date(media['startDate']);
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    final data = await _query(_byIdQuery, {'id': _parse(source)});
    final media = data['Media'] as Map<String, Object?>?;
    if (media == null) return null;
    final cover = media['coverImage'] as Map<String, Object?>? ?? const {};
    return stringAt(cover, 'extraLarge') ?? stringAt(cover, 'large');
  }
}

/// One AniList entry in a prequel and sequel chain. [prequels] and
/// [sequels] are null until the entry was fetched with its relations.
class AniNode {
  const AniNode({
    required this.id,
    this.format,
    this.status,
    this.english,
    this.romaji,
    this.start,
    this.end,
    this.episodes,
    this.duration,
    this.prequels,
    this.sequels,
  });

  final int id;
  final String? format;
  final String? status;
  final String? english;
  final String? romaji;
  final Released? start;
  final Released? end;
  final int? episodes;
  final int? duration;
  final List<int>? prequels;
  final List<int>? sequels;

  bool get loaded => prequels != null;

  String get title => english ?? romaji ?? 'Anime $id';

  bool get isSeries => AniListSource.kindOf(format) == EntryKind.series;

  /// A recap entry, by its title; left out of the seasons.
  bool get isRecap => RegExp(
    r'\brecap\b',
    caseSensitive: false,
  ).hasMatch('${english ?? ''} ${romaji ?? ''}');
}
