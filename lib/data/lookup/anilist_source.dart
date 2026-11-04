import 'dart:convert';

import '../models/entry_kind.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../models/season.dart';
import '../models/season_span.dart';
import '../models/season_split.dart';
import 'anime_chain_store.dart';
import 'arm_ids.dart';
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
/// entry in it is a season (a "Part 2" folds into its season, see below)
/// with its own episode count and dates; movies, OVAs, specials and recaps are left out.
/// A sequel not out yet is a season dated by its start, as precise as
/// AniList has it. The episodes are "Episode N" with their air dates from
/// AniList's airing schedule.
///
/// ARM ([arm]) maps each entry of the chain to its TMDB show and TVDB
/// season, kept in [links]: consecutive entries of one TVDB season (a
/// "Part 2") fold into one season ([seasonGroups]), and the TMDB show
/// gives the episodes their titles, found there by air date
/// ([seasonEpisodes]); a title match stands in when ARM has no row.
///
/// AniList allows about 30 requests a minute, hence the gap.
class AniListSource extends HttpLookupSource {
  AniListSource(
    super.client, {
    this.tmdb,
    this.arm,
    AnimeLinkStore? links,
    AnimeChainStore? chains,
    Uri? baseUrl,
    super.timeout,
  }) : links = links ?? MemoryAnimeLinkStore(),
       chainStore = chains ?? MemoryAnimeChainStore(),
       _baseUrl = baseUrl ?? Uri.https('graphql.anilist.co'),
       super(minGap: const Duration(seconds: 2));

  /// Where an anime's episode titles and the other splits of its seasons
  /// come from (section 10c); null in a build without TMDB.
  final TmdbSource? tmdb;

  /// The map from AniList entries to TMDB shows and TVDB seasons (section
  /// 10c); null in a build without it (the tests of the chain alone).
  final ArmIds? arm;

  /// The kind per anime, and the TMDB show it matched, kept on the phone.
  final AnimeLinkStore links;

  /// The chains as last fetched, kept on the phone for the season screen.
  final AnimeChainStore chainStore;

  /// How old a kept chain the season screen takes; the daily check
  /// refreshes the chains of the anime it asks every day.
  static const chainKeep = Duration(days: 7);

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

  /// The chains read from [chainStore] this session, by any entry in them.
  final _keptChains = <int, List<AniNode>>{};

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
  /// over a movie or a special. A sequel announced before AniList gives
  /// it a format (Jujutsu Kaisen's Season 3 Part 2, owner's report of
  /// 2026-11-04) counts as a TV short: it is a season, not a special.
  static int _rank(String? format, {String? status}) => switch (format) {
    'TV' => 0,
    'TV_SHORT' || 'ONA' => 1,
    'OVA' => 2,
    null when status == 'NOT_YET_RELEASED' => 1,
    _ => 3,
  };

  static int _rankOf(AniNode node) => _rank(node.format, status: node.status);

  /// Among related entries, the one [_rank] wants most (a TV sequel over a
  /// recap movie), the first of equals; among them only those that come
  /// [before] or after the entry they relate to, when both are dated: a
  /// prequel starts before it and a sequel after it. AniList lists One
  /// Piece's 2024 MONSTERS short as its prequel (it is set in the past),
  /// and a chain that followed it would make MONSTERS season 1 (owner's
  /// report, 2026-11-04).
  static int? _pick(
    List<int> ids,
    Map<int, AniNode> nodes, {
    required AniNode of,
    required bool before,
  }) {
    int? best;
    var bestRank = 4;
    for (final id in ids) {
      final node = nodes[id];
      if (node == null) continue;
      if (!_inOrder(node, of, before: before)) continue;
      final rank = _rankOf(node);
      if (rank < bestRank) {
        best = id;
        bestRank = rank;
      }
    }
    return best;
  }

  /// Whether [node] starts before (or, with [before] false, after) [of],
  /// as far as both dates go; undated entries pass.
  static bool _inOrder(AniNode node, AniNode of, {required bool before}) {
    final a = node.start, b = of.start;
    if (a == null || b == null) return true;
    final x = a.availableFrom, y = b.availableFrom;
    return before ? !x.isAfter(y) : !x.isBefore(y);
  }

  /// The chain of entries the anime [id] is part of, first to last, walked
  /// back along the prequels and forward along the sequels. A movie, a
  /// special or anything else that is not a series is its own chain. Each
  /// entry carries ARM's map of it ([_arm]): the TMDB show and the TVDB
  /// season, which fold a "Part 2" into its season ([seasonGroups]).
  ///
  /// With [kept] (the season screen), a chain kept on the phone younger
  /// than [chainKeep] serves instead; a chain walked is always kept.
  Future<List<AniNode>> _chain(int id, {bool kept = false}) async {
    if (_chains[id] case final chain?) return chain;
    if (kept) {
      if (_keptChains[id] case final chain?) return chain;
      final stored = await chainStore.read(id);
      if (stored != null &&
          DateTime.now().difference(stored.fetched) < chainKeep) {
        final chain = [for (final n in stored.nodes) AniNode.fromJson(n)];
        for (final node in chain) {
          _keptChains[node.id] = chain;
        }
        return chain;
      }
    }
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
      final previous = _pick(
        current.prequels!,
        nodes,
        of: current,
        before: true,
      );
      if (previous == null || behind.contains(previous)) break;
      behind.add(previous);
      current = await load(previous);
    }
    var chain = [current];
    final ahead = {current.id};
    for (var hops = 0; hops < maxHops; hops++) {
      final next = _pick(current.sequels!, nodes, of: current, before: false);
      if (next == null || ahead.contains(next)) break;
      ahead.add(next);
      current = await load(next);
      chain.add(current);
    }
    chain = await _mapped(chain);
    for (final node in chain) {
      _chains[node.id] = chain;
    }
    await chainStore.write((
      fetched: DateTime.now(),
      nodes: [for (final node in chain) node.toJson()],
    ));
    return chain;
  }

  /// [chain] with ARM's map on each season entry ([_arm]); an entry ARM
  /// cannot be asked about now (offline, rate limited) stays unmapped,
  /// and the next walk asks again.
  Future<List<AniNode>> _mapped(List<AniNode> chain) async {
    if (arm == null) return chain;
    final mapped = <AniNode>[];
    var reachable = true;
    for (final node in chain) {
      if (!node.isSeasonEntry || !reachable) {
        mapped.add(node);
        continue;
      }
      try {
        final link = await _arm(node.id);
        mapped.add(
          node.copyWith(
            tmdb: link.tmdb,
            tvdb: link.tvdb,
            tvdbSeason: link.tvdbSeason,
          ),
        );
      } on LookupException {
        reachable = false;
        mapped.add(node);
      }
    }
    return mapped;
  }

  /// The entries of a chain that are seasons, each a group of the parts
  /// that make one season: TV, TV short and ONA entries, recaps left out,
  /// and consecutive entries ARM maps to the same TVDB season folded into
  /// one (Attack on Titan's Season 3 and Season 3 Part 2; every streaming
  /// service shows them as one season). A chain with none of those (a
  /// series made only of OVAs) has its OVAs as seasons, one each.
  static List<List<AniNode>> seasonGroups(List<AniNode> chain) {
    final entries = [
      for (final node in chain)
        if (_rankOf(node) < 2 && !node.isRecap) node,
    ];
    if (entries.isEmpty) {
      return [
        for (final node in chain)
          if (node.format == 'OVA' && !node.isRecap) [node],
      ];
    }
    final groups = <List<AniNode>>[];
    for (final node in entries) {
      final last = groups.lastOrNull;
      if (last != null &&
          node.tvdb != null &&
          node.tvdbSeason != null &&
          last.first.tvdb == node.tvdb &&
          last.first.tvdbSeason == node.tvdbSeason) {
        last.add(node);
      } else {
        groups.add([node]);
      }
    }
    return groups;
  }

  /// The season entries one by one, parts not folded ([seasonGroups]).
  static List<AniNode> seasonEntries(List<AniNode> chain) => [
    for (final group in seasonGroups(chain)) ...group,
  ];

  /// One season per group, dated by its first part's start.
  static List<Season> chainSeasons(List<AniNode> chain) => [
    for (final (i, group) in seasonGroups(chain).indexed)
      Season(season: i + 1, released: group.first.start),
  ];

  /// The episodes of a group: the parts' counts added up as far as they
  /// are known; null when the first part's is not.
  static int? _groupEpisodes(List<AniNode> group) {
    if (group.first.episodes == null) return null;
    var sum = 0;
    for (final node in group) {
      sum += node.episodes ?? 0;
    }
    return sum;
  }

  /// A long run: one season (one entry, or the parts of one) of more than
  /// 100 episodes, or still airing with no count after two years (One
  /// Piece). Streaming services show such an anime by story arc, so its
  /// automatic split is TMDB's arcs (section 10c; owner's decision,
  /// 2026-11-04).
  static bool isLongRun(List<List<AniNode>> groups, DateTime today) {
    if (groups.length != 1) return false;
    final group = groups.single;
    final episodes = _groupEpisodes(group);
    if (episodes != null) return episodes > 100;
    final start = group.first.start?.availableFrom;
    return group.last.status == 'RELEASING' &&
        start != null &&
        today.difference(start) > const Duration(days: 730);
  }

  /// The chain's seasons with their episode counts: the "anilist" split,
  /// parts folded.
  static List<SeasonSpan> chainSpans(List<AniNode> chain) => [
    for (final (i, group) in seasonGroups(chain).indexed)
      SeasonSpan(
        season: i + 1,
        episodes: _groupEpisodes(group),
        released: group.first.start,
      ),
  ];

  /// Every season entry its own season: the "anilist:parts" split.
  static List<SeasonSpan> partSpans(List<AniNode> chain) => [
    for (final (i, node) in seasonEntries(chain).indexed)
      SeasonSpan(season: i + 1, episodes: node.episodes, released: node.start),
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
      tvdb: stored?.tvdb,
      tvdbSeason: stored?.tvdbSeason,
      armChecked: stored?.armChecked,
    );
    await links.write(id, link);
    return link;
  }

  /// How long a "no TMDB match" is believed before TMDB is asked again,
  /// and a "no row" before ARM is.
  static const tmdbRetryAfter = Duration(days: 14);

  /// ARM's map of the entry [id], from the store once asked (a row is kept
  /// for good; no row is asked again after [tmdbRetryAfter]), else from
  /// ARM now, stored with the link. The TMDB show ARM names is the link's
  /// [AnimeLink.tmdb] unless one was matched before.
  Future<AnimeLink> _arm(int id) async {
    final now = DateTime.now();
    final stored = await links.read(id);
    if (stored?.armChecked case final asked?
        when stored!.tvdb != null || now.difference(asked) < tmdbRetryAfter) {
      return stored;
    }
    final row = await arm!.lookup(id);
    final AnimeLink link = (
      kind: stored?.kind,
      checked: stored?.checked ?? now,
      tmdb: row?.tmdb ?? stored?.tmdb,
      tmdbChecked: row?.tmdb != null ? now : stored?.tmdbChecked,
      tvdb: row?.tvdb,
      tvdbSeason: row?.tvdbSeason,
      armChecked: now,
    );
    await links.write(id, link);
    return link;
  }

  /// A title without a year a database tacks on to tell remakes apart:
  /// "Hunter x Hunter (2011)" is "Hunter x Hunter" (the TMDB search finds
  /// it with the year, but the match compares titles; owner's report,
  /// 2026-11-04).
  static String withoutYear(String title) =>
      title.replaceFirst(RegExp(r'\s*\(\d{4}\)\s*$'), '');

  /// The TMDB show the anime's episode titles come from: ARM's for the
  /// series' first entry, else that entry looked for by its English, then
  /// romaji title (without a year) and its year. A match is kept for good
  /// and a miss for [tmdbRetryAfter]; nothing is kept when TMDB did not
  /// answer. Null without TMDB in the build.
  Future<String?> _tmdbMatch(int id) async {
    if (!_tmdbReady) return null;
    final now = DateTime.now();
    final stored = await links.read(id);
    if (stored?.tmdb case final linked?) return linked;
    if (stored?.tmdbChecked case final asked?
        when now.difference(asked) < tmdbRetryAfter) {
      return null;
    }
    final chain = await _chain(id, kept: true);
    final root = chain.first;
    String? found = root.tmdb;
    if (found == null && arm != null && root.tvdb == null) {
      // The kept chain was walked without ARM's answer: ask once more.
      try {
        found = (await _arm(root.id)).tmdb;
      } on LookupException {
        // Offline or busy: the title match below may still do.
      }
    }
    if (found == null) {
      for (final title in {?root.english, ?root.romaji}) {
        final hit = await tmdb!.match(
          withoutYear(title),
          type: MediaType.shows,
          year: root.start?.year,
        );
        if (hit != null) {
          found = hit.source;
          break;
        }
      }
    }
    final entry = chain.firstWhere(
      (n) => n.id == id,
      orElse: () => chain.first,
    );
    final latest = await links.read(id);
    await links.write(id, (
      kind: latest?.kind ?? kindOf(entry.format),
      checked: latest?.checked ?? now,
      tmdb: found,
      tmdbChecked: now,
      tvdb: latest?.tvdb,
      tvdbSeason: latest?.tvdbSeason,
      armChecked: latest?.armChecked,
    ));
    return found;
  }

  /// A series' seasons, one per season group of its AniList chain
  /// ([seasonGroups]). A movie has none. [kind] tells the daily check
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

  /// The parts of a series' seasons still to come, for Coming soon
  /// (owner's decision, 2026-11-04: new episodes of something watched
  /// belong there, as their own row "Season 3, Part 2"): in each season
  /// group with a part out, every later part not out yet that AniList
  /// dates, numbered within the season. A season with no part out is an
  /// announced season already, not a part.
  @override
  Future<List<ComingSeasonPart>> seasonParts(String source) async {
    final chain = await _chain(_parse(source), kept: true);
    final today = DateTime.now();
    return [
      for (final (i, group) in seasonGroups(chain).indexed)
        if (group.first.start?.isReleasedOn(today) ?? false)
          for (final (j, node) in group.indexed)
            if (j > 0 &&
                node.status == 'NOT_YET_RELEASED' &&
                node.start != null &&
                !node.start!.isReleasedOn(today))
              (season: i + 1, part: j + 1, released: node.start!),
    ];
  }

  /// The TMDB show the series' other splits and episode titles are read
  /// from: the entry's own ([linked], `Entry.tmdb`), else the one the
  /// series matches ([_tmdbMatch]); null without one, or without TMDB in
  /// the build.
  Future<String?> _tmdbShow(int id, String? linked) async {
    if (!_tmdbReady) return null;
    return linked ?? await _tmdbMatch(id);
  }

  /// The chain's split first (parts folded; marked long for a long run),
  /// then its parts one by one when that differs ("anilist:parts"), then
  /// the TMDB show's season list and its episode groups (section 10c);
  /// TMDB not answering leaves AniList's alone. A kept chain serves, as
  /// for the season screen. A movie has no splits.
  @override
  Future<List<SeasonSplit>?> seasonSplits(String source, {String? tmdb}) async {
    final id = _parse(source);
    final chain = await _chain(id, kept: true);
    final groups = seasonGroups(chain);
    if (groups.isEmpty) return const [];
    final splits = [
      SeasonSplit(
        ids: const [SeasonSplit.anilistId],
        long: isLongRun(groups, DateTime.now()),
        seasons: chainSpans(chain),
      ),
      if (groups.any((g) => g.length > 1))
        SeasonSplit(
          ids: const [SeasonSplit.anilistPartsId],
          seasons: partSpans(chain),
        ),
    ];
    try {
      final show = await _tmdbShow(id, tmdb);
      if (show != null) {
        splits.addAll(await this.tmdb!.seasonSplits(show) ?? const []);
      }
    } on LookupException {
      // The other splits are a bonus: the chain's stands.
    }
    return splits;
  }

  /// "anilist": the chain's seasons; "anilist:parts": its entries one by
  /// one; a TMDB split: that show's, through TMDB, with the kind series.
  /// Null when there is no TMDB show.
  @override
  Future<ShowSeasons?> splitSeasons(
    String source,
    String from, {
    bool anime = false,
    String? tmdb,
  }) async {
    if (from == SeasonSplit.anilistId) return seasons(source, anime: anime);
    if (from == SeasonSplit.anilistPartsId) {
      final chain = await _chain(_parse(source));
      return (
        seasons: [
          for (final (i, node) in seasonEntries(chain).indexed)
            Season(season: i + 1, released: node.start),
        ],
        canceled: chain.last.status == 'CANCELLED',
        kind: EntryKind.series,
      );
    }
    final show = await _tmdbShow(_parse(source), tmdb);
    if (show == null) return null;
    final split = await this.tmdb!.splitSeasons(show, from, anime: true);
    if (split == null) return null;
    return (
      seasons: split.seasons,
      canceled: split.canceled,
      kind: EntryKind.series,
    );
  }

  @override
  bool isOwnSplit(String? from) =>
      from == null || from == SeasonSplit.anilistId;

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

  /// The episodes of the [season]th season of the chain: its parts' one
  /// after the other, numbered on ([seasonGroups]; in the "anilist:parts"
  /// split, the [season]th entry's alone), as many as AniList counts,
  /// dated by AniList's airing schedule. Their titles (and lengths, and
  /// dates the schedule lacks) come from the TMDB show the series matched
  /// ([_tmdbMatch]): its episode that aired on the entry's start day, give
  /// or take one, and those after it, across TMDB's seasons
  /// ([TmdbSource.episodesFrom]), so TMDB's one season of 38 gives
  /// Frieren's season 2 its episodes 29 to 38. Without a match, or with
  /// no TMDB episode on that day, they are "Episode N" with the entry's
  /// episode length. A finished entry's episodes without any date are
  /// dated the entry's start, so they count as out; an unfinished one's
  /// are undated until scheduled. In one of the TMDB show's splits
  /// ([from] "tmdb:seasons" or a group), the episodes are TMDB's for that
  /// split's season, credited to TMDB alone.
  @override
  Future<List<EpisodeInfo>?> seasonEpisodes(
    String source,
    int season, {
    bool anime = false,
    String? tmdb,
    String? from,
  }) async {
    final id = _parse(source);
    if (from != null && !from.startsWith(SeasonSplit.anilistId)) {
      final show = await _tmdbShow(id, tmdb);
      if (show == null) return const [];
      _episodesCredit[source] = this.tmdb!.name;
      return this.tmdb!.seasonEpisodes(show, season, anime: true, from: from);
    }
    final chain = await _chain(id, kept: true);
    final group = from == SeasonSplit.anilistPartsId
        ? [
            for (final node in seasonEntries(chain)) [node],
          ]
        : seasonGroups(chain);
    if (season < 1 || season > group.length) return const [];
    final episodes = <EpisodeInfo>[];
    var titled = false;
    for (final node in group[season - 1]) {
      final part = await _nodeEpisodes(id, node, linked: tmdb);
      titled = titled || part.any((e) => e.title != null);
      for (final e in part) {
        episodes.add((
          number: episodes.length + 1,
          title: e.title,
          aired: e.aired,
          runtime: e.runtime,
        ));
      }
    }
    _episodesCredit[source] = titled ? '${this.tmdb!.name} and $name' : name;
    return episodes;
  }

  /// One entry's episodes, numbered from 1 ([seasonEpisodes]).
  Future<List<EpisodeInfo>> _nodeEpisodes(
    int id,
    AniNode node, {
    String? linked,
  }) async {
    final known = node.episodes;
    var titled = known == null
        ? const <EpisodeInfo>[]
        : await _tmdbEpisodes(id, node, known, linked: linked);
    // A finished season TMDB dates every episode of needs no schedule.
    final dated =
        node.status == 'FINISHED' &&
        known != null &&
        titled.length >= known &&
        titled.every((e) => e.aired != null);
    final schedule = dated ? const <int, Released>{} : await _schedule(node);
    final count =
        known ??
        (schedule.isEmpty ? 0 : schedule.keys.reduce((a, b) => a > b ? a : b));
    if (known == null) {
      titled = await _tmdbEpisodes(id, node, count, linked: linked);
    }
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

  /// The air dates AniList's airing schedule has for the entry [node], by
  /// episode number.
  Future<Map<int, Released>> _schedule(AniNode node) async {
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
    return schedule;
  }

  /// TMDB's episodes for the chain entry [node], [count] of them from the
  /// one that aired on its start day, on the entry's own TMDB show when
  /// ARM maps it to another show than the series' first entry (Naruto's
  /// seasons on Naruto Shippuden), else the entry's TMDB show ([linked],
  /// `Entry.tmdb`), else the one the series matches ([_tmdbMatch]); empty
  /// when there is no match or no such episode, or TMDB cannot answer now
  /// (the titles are a bonus: the episodes still come from AniList).
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
      final chain = await _chain(id, kept: true);
      final own = node.tmdb;
      final show = own != null && own != chain.first.tmdb
          ? own
          : linked ?? await _tmdbMatch(id);
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
/// [tmdb], [tvdb] and [tvdbSeason] are ARM's map of the entry (section
/// 10c), null until asked, or when ARM has none.
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
    this.tmdb,
    this.tvdb,
    this.tvdbSeason,
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
  final String? tmdb;
  final int? tvdb;
  final int? tvdbSeason;

  bool get loaded => prequels != null;

  AniNode copyWith({String? tmdb, int? tvdb, int? tvdbSeason}) => AniNode(
    id: id,
    format: format,
    status: status,
    english: english,
    romaji: romaji,
    start: start,
    end: end,
    episodes: episodes,
    duration: duration,
    prequels: prequels,
    sequels: sequels,
    tmdb: tmdb ?? this.tmdb,
    tvdb: tvdb ?? this.tvdb,
    tvdbSeason: tvdbSeason ?? this.tvdbSeason,
  );

  /// As [AnimeChainStore] keeps it: without the relations.
  Map<String, Object?> toJson() => {
    'id': id,
    'format': format,
    'status': status,
    'english': english,
    'romaji': romaji,
    'start': start?.toString(),
    'end': end?.toString(),
    'episodes': episodes,
    'duration': duration,
    'tmdb': tmdb,
    'tvdb': tvdb,
    'tvdb_season': tvdbSeason,
  };

  factory AniNode.fromJson(Map<String, Object?> json) => AniNode(
    id: json['id'] as int,
    format: json['format'] as String?,
    status: json['status'] as String?,
    english: json['english'] as String?,
    romaji: json['romaji'] as String?,
    start: Released.tryParse(json['start'] as String? ?? ''),
    end: Released.tryParse(json['end'] as String? ?? ''),
    episodes: json['episodes'] as int?,
    duration: json['duration'] as int?,
    tmdb: json['tmdb'] as String?,
    tvdb: json['tvdb'] as int?,
    tvdbSeason: json['tvdb_season'] as int?,
  );

  String get title => english ?? romaji ?? 'Anime $id';

  bool get isSeries => AniListSource.kindOf(format) == EntryKind.series;

  /// A TV, TV short or ONA entry, or a sequel announced without a format
  /// yet: what [AniListSource.seasonGroups] makes seasons of.
  bool get isSeasonEntry => AniListSource._rankOf(this) < 2 && !isRecap;

  /// A recap entry, by its title; left out of the seasons.
  bool get isRecap => RegExp(
    r'\brecap\b',
    caseSensitive: false,
  ).hasMatch('${english ?? ''} ${romaji ?? ''}');
}
