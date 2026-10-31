import 'dart:math' as math;

import '../models/follow_kind.dart';
import '../models/media_type.dart';
import '../upcoming/creator_lookup.dart';
import '../models/platform_names.dart';
import '../models/released.dart';
import '../models/series.dart';
import '../storage/json_file.dart';
import 'http_lookup_source.dart';
import 'igdb_token_store.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'lookup_source.dart';
import 'text_clean.dart';

/// Games from IGDB, which sits behind Twitch: a client id and secret turn
/// into an app access token (cached in [tokens]), sent with every query.
/// Ids are "igdb:1009". One search carries everything the form needs:
/// name, release date, summary, developers, platforms, genres and cover;
/// the game's collection (its series, Library › Movie in a series) comes
/// with [details].
class IgdbSource extends HttpLookupSource implements CreatorLookup {
  IgdbSource(
    super.client, {
    required this.clientId,
    required this.clientSecret,
    required this.tokens,
    this.platformsFile,
    Uri? baseUrl,
    Uri? tokenUrl,
    DateTime Function()? now,
    super.timeout,
  }) : _baseUrl = baseUrl ?? Uri.https('api.igdb.com', '/v4/'),
       _tokenUrl = tokenUrl ?? Uri.https('id.twitch.tv', '/oauth2/token'),
       _now = now ?? DateTime.now,
       super(minGap: const Duration(milliseconds: 300));

  final String clientId;
  final String clientSecret;
  final IgdbTokenStore tokens;

  /// Where IGDB's platform list is kept between runs (Add / edit entry ›
  /// Platform picker), or null to ask once a session.
  final JsonFile? platformsFile;
  final DateTime Function() _now;
  final Uri _baseUrl;
  final Uri _tokenUrl;

  static const _images = 'https://images.igdb.com/igdb/image/upload/';

  /// 264 × 374, enough for a row and the details header on a 3x screen.
  static const coverSize = 't_cover_big';

  static const _fields =
      'name,first_release_date,summary,cover.image_id,platforms.name,'
      'involved_companies.company.name,involved_companies.developer,'
      'genres.name,language_supports.language.locale,'
      'language_supports.language_support_type';

  /// [_fields] and what ranks a search hit: its platforms' types, how many
  /// ratings it has and the game it is a port of.
  static const _searchFields =
      '$_fields,platforms.platform_type,total_rating_count,parent_game';

  /// IGDB's platform types: 2 is an arcade cabinet, 6 a home computer.
  static const _arcade = 2, _computer = 6;

  /// Platforms nobody adds a game for: handheld electronic LCD games and
  /// pre-smartphone mobiles.
  static const _minorPlatforms = {411, 55};

  /// IGDB's `language_support_type` id for spoken audio (2 is subtitles, 3
  /// the interface).
  static const _audioSupport = 1;

  /// The language a game was made in, as far as IGDB tells: its one audio
  /// language. A game dubbed into several says nothing.
  static String? _language(Map<String, Object?> game) {
    final audio = {
      for (final l in objectsAt(game, 'language_supports'))
        if (l['language_support_type'] == _audioSupport)
          ?stringAt(
            l['language'] as Map<String, Object?>? ?? const {},
            'locale',
          ),
    };
    return audio.length == 1 ? audio.single : null;
  }

  @override
  String get id => 'igdb';

  @override
  String get name => 'IGDB';

  /// The collections a game is in, with their games: the series and its
  /// parts. IGDB retired the single `collection` field and leaves it
  /// empty; `collections` holds them now. `game_type` tells main games and
  /// remakes from bundles, DLC, remasters and ports, which are left out
  /// of the parts.
  static const _collectionFields =
      'name,parent_game,collections.name,collections.games.name,'
      'collections.games.first_release_date,collections.games.game_type,'
      'collections.games.version_parent,collections.games.cover.image_id';

  /// IGDB's game types that count as a part of a series: 0 is a main game,
  /// 8 a remake.
  static const _partTypes = {0, 8};

  /// Collections whose game types mislead, by IGDB's collection id. IGDB
  /// files Street Fighter II's revisions (Champion Edition, Turbo, Super)
  /// as expanded games (10) and HD Remix as a remaster (9), and its puzzle,
  /// card and pachislot spin-offs as main games, so these take the extra
  /// [types] and leave out the games in [skip].
  static const _collectionRules = <int, ({Set<int> types, Set<int> skip})>{
    // Street Fighter II: the movie game, a pachislot, Uno, pinball.
    2879: (types: {9, 10}, skip: {45192, 55060, 55063, 55062}),
    // Street Fighter: Final Fight, 2010, the Puzzle and Gem Fighters,
    // Mouse Generation, Puzzle Spirits, Battle Combination, the
    // pachislot, X Mega Man, the cancelled Tekken X and the Switch 2
    // Street Fighter 6.
    219: (
      types: {9, 10},
      skip: {
        1655, 45196, 20803, 23072, 39314, 55061, 60889, 55065, 69377, //
        45184, 1239, 343673,
      },
    ),
  };

  @override
  Set<MediaType> get types => const {MediaType.games};

  @override
  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  String? _token;

  Future<String> _accessToken() async {
    _token ??= await tokens.valid();
    if (_token case final token?) return token;
    final response = await send(
      () => client.post(
        _tokenUrl.replace(
          queryParameters: {
            'client_id': clientId,
            'client_secret': clientSecret,
            'grant_type': 'client_credentials',
          },
        ),
        headers: {'Accept': 'application/json', 'User-Agent': userAgent},
      ),
    );
    check(response);
    final json = decodeObject(response);
    final token = stringAt(json, 'access_token');
    final expiresIn = json['expires_in'];
    if (token == null) {
      throw const LookupException(
        LookupFailure.other,
        message: 'no access token from Twitch',
      );
    }
    await tokens.save(
      token,
      expiresIn: Duration(seconds: expiresIn is num ? expiresIn.toInt() : 3600),
    );
    return _token = token;
  }

  /// Runs an Apicalypse [body] against `games`, or another [endpoint]. A
  /// refused token is dropped and fetched again once.
  Future<List<Map<String, Object?>>> _games(
    String body, {
    String endpoint = 'games',
  }) async {
    requireConfigured();
    for (var attempt = 0; ; attempt++) {
      final token = await _accessToken();
      final response = await send(
        () => client.post(
          _baseUrl.resolve(endpoint),
          headers: {
            'Client-ID': clientId,
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'User-Agent': userAgent,
          },
          body: body,
        ),
      );
      if (response.statusCode == 401 && attempt == 0) {
        _token = null;
        await tokens.clear();
        continue;
      }
      check(response);
      final json = decode(response);
      if (json is! List) {
        throw LookupException(
          LookupFailure.other,
          status: response.statusCode,
          message: 'not a JSON list',
        );
      }
      return [
        for (final item in json)
          if (item is Map<String, Object?>) item,
      ];
    }
  }

  static String _quote(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// IGDB says "PC (Microsoft Windows)" and "Nintendo Switch"; the form's
  /// normalizer takes it from there.
  static String _platform(String name) =>
      name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

  LookupMatch? _match(Map<String, Object?> game) {
    final id = game['id'];
    final name = stringAt(game, 'name');
    if (id is! num || name == null) return null;
    final epoch = game['first_release_date'];
    final date = epoch is num
        ? DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000, isUtc: true)
        : null;
    final developers = [
      for (final c in objectsAt(game, 'involved_companies'))
        if (c['developer'] == true)
          ?stringAt(c['company'] as Map<String, Object?>? ?? const {}, 'name'),
    ];
    final cover = game['cover'] as Map<String, Object?>?;
    final imageId = cover == null ? null : stringAt(cover, 'image_id');
    return LookupMatch(
      type: MediaType.games,
      title: name,
      source: 'igdb:${id.toInt()}',
      released: date == null ? null : Released(date.year, date.month, date.day),
      creator: developers.isEmpty ? null : developers.join(', '),
      companies: developers,
      description: stringAt(game, 'summary') ?? '',
      platforms: [
        for (final p in objectsAt(game, 'platforms'))
          if (stringAt(p, 'name') case final n?) _platform(n),
      ],
      tags: [for (final g in objectsAt(game, 'genres')) ?stringAt(g, 'name')],
      language: _language(game),
      coverUrl: imageId == null ? null : coverUrlFor(imageId),
    );
  }

  static String coverUrlFor(String imageId) =>
      '$_images$coverSize/$imageId.jpg';

  /// IGDB's search ranks ports poorly and often leaves them out (the
  /// Super Nintendo "Street Fighter II" is not among its hits), so the games
  /// named exactly [query] are asked too, the most rated first, and fill up
  /// to half of the list ahead of the search's own hits ([_rankNamed]).
  /// Packs and updates (`game_type` 13 and 14) are never offered.
  Future<List<LookupMatch>> _search(String query, int limit) async {
    const where = 'version_parent = null & game_type != (13, 14)';
    final named = _rankNamed(
      await _games(
        'fields $_searchFields; where $where & name ~ ${_quote(query)}; '
        'sort total_rating_count desc; limit $limit;',
      ),
    );
    final searched = await _games(
      'search ${_quote(query)}; fields $_searchFields; where $where; '
      'limit $limit;',
    );
    final half = (limit + 1) ~/ 2;
    final seen = <Object?>{};
    return [
      for (final game in [
        ...named.take(half),
        ...searched,
        ...named.skip(half),
      ])
        if (seen.add(game['id'])) ?_match(game),
    ].take(limit).toList();
  }

  /// How likely a game is the one wanted, from its platforms, lower first:
  /// a console, handheld or PC 0, a home computer 1, only arcades or minor
  /// platforms 2.
  static int _platformRank(Map<String, Object?> game) {
    var rank = 2;
    for (final p in objectsAt(game, 'platforms')) {
      final type = p['platform_type'];
      if (_minorPlatforms.contains(p['id']) || type == _arcade) continue;
      rank = math.min(rank, type == _computer ? 1 : 0);
    }
    return rank;
  }

  /// The exact-name hits, the most rated first as IGDB sorted them, the
  /// unrated ones by [_platformRank]; a game that came out in arcades goes
  /// right after its first port, since that is what people played (the
  /// Super Nintendo "Street Fighter II" before the 1991 cabinet).
  static List<Map<String, Object?>> _rankNamed(
    List<Map<String, Object?>> games,
  ) {
    int? rating(Map<String, Object?> g) => switch (g['total_rating_count']) {
      final num n => n.toInt(),
      _ => null,
    };
    final rated = [
      for (final g in games)
        if (rating(g) != null) g,
    ];
    // A stable sort, so IGDB's order holds within a rank.
    final unrated = [
      for (final (i, g) in games.where((g) => rating(g) == null).indexed)
        (i: i, rank: _platformRank(g), game: g),
    ]..sort((a, b) => a.rank != b.rank ? a.rank - b.rank : a.i - b.i);
    final ranked = [...rated, for (final u in unrated) u.game];
    for (final game in [...ranked]) {
      final inArcades = objectsAt(
        game,
        'platforms',
      ).any((p) => p['platform_type'] == _arcade);
      if (!inArcades) continue;
      final at = ranked.indexOf(game);
      final port = ranked.indexWhere((g) => g['parent_game'] == game['id']);
      if (port > at) ranked.insert(port, ranked.removeAt(at));
    }
    return ranked;
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) => _search(query, limit);

  /// One search narrowed to [platform], with no exact-name query beside it:
  /// on one platform the search finds the ports it otherwise misses.
  @override
  Future<List<LookupMatch>> searchOnPlatform(
    String query,
    GamePlatform platform, {
    int limit = 10,
  }) async {
    final games = await _games(
      'search ${_quote(query)}; fields $_fields,release_dates.platform,'
      'release_dates.date,release_dates.date_format; '
      'where version_parent = null & game_type != (13, 14) & '
      'platforms = (${platform.id}); limit $limit;',
    );
    return [
      for (final game in games)
        if (_match(game) case final match?)
          match.copyWith(released: _releasedOn(game, platform.id)),
    ];
  }

  /// The game's first release on the platform [platformId], as precise as
  /// IGDB has it (a year-only date sits on December 31, so its format
  /// says what is known); null when it lists none there. With no platform
  /// given, its first release anywhere.
  static Released? _releasedOn(Map<String, Object?> game, int? platformId) {
    Map<String, Object?>? first;
    for (final r in objectsAt(game, 'release_dates')) {
      if ((platformId != null && r['platform'] != platformId) ||
          r['date'] is! num) {
        continue;
      }
      if (first == null || (r['date']! as num) < (first['date']! as num)) {
        first = r;
      }
    }
    if (first == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(
      (first['date']! as num).toInt() * 1000,
      isUtc: true,
    );
    return switch (first['date_format']) {
      0 => Released(date.year, date.month, date.day),
      1 => Released(date.year, date.month),
      _ => Released(date.year),
    };
  }

  /// A unix time as the full date it falls on, in UTC.
  static Released _dayOf(int epoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
    return Released(date.year, date.month, date.day);
  }

  /// The game's first release as IGDB has it now, for the daily check of
  /// games not out yet: its earliest dated release with that release's
  /// precision (a game "coming in 2027" stays a year), else its
  /// `first_release_date` as a full date; null when IGDB has no date.
  @override
  Future<Released?> releaseDate(String source) async {
    final games = await _games(
      'fields first_release_date,release_dates.date,'
      'release_dates.date_format; where id = ${_parse(source)}; limit 1;',
    );
    final game = games.firstOrNull;
    if (game == null) return null;
    if (_releasedOn(game, null) case final released?) return released;
    return switch (game['first_release_date']) {
      final num epoch => _dayOf(epoch.toInt()),
      _ => null,
    };
  }

  /// How long a stored platform list is trusted: IGDB adds a platform a
  /// few times a year.
  static const platformsMaxAge = Duration(days: 30);

  List<GamePlatform>? _platforms;

  /// IGDB's platforms, kept in [platformsFile] and asked again once the
  /// list is [platformsMaxAge] old; a stored list of any age stands in
  /// when IGDB does not answer.
  @override
  Future<List<GamePlatform>> platforms() async {
    if (_platforms case final platforms?) return platforms;
    final stored = await platformsFile?.read();
    final fetched = DateTime.tryParse(stored?['fetched'] as String? ?? '');
    final rows = switch (stored?['platforms']) {
      final List<Object?> list => [
        for (final row in list)
          if (row is Map<String, Object?>) row,
      ],
      _ => null,
    };
    if (rows != null &&
        fetched != null &&
        _now().difference(fetched) < platformsMaxAge) {
      return _platforms = platformsFrom(rows);
    }
    try {
      final fresh = await _games(
        'fields name,abbreviation,alternative_name; limit 500;',
        endpoint: 'platforms',
      );
      await platformsFile?.write({
        'fetched': _now().toUtc().toIso8601String(),
        'platforms': fresh,
      });
      return _platforms = platformsFrom(fresh);
    } on LookupException {
      if (rows == null) rethrow;
      return _platforms = platformsFrom(rows);
    }
  }

  /// IGDB's platform records as [GamePlatform]s, A to Z: the name spelled
  /// as the app spells it ("Super Nintendo Entertainment System" is "Super
  /// Nintendo", "PC (Microsoft Windows)" is "PC"), the abbreviation, the
  /// alternative names and IGDB's own name as the other names.
  static List<GamePlatform> platformsFrom(List<Map<String, Object?>> rows) {
    final platforms = <GamePlatform>[];
    for (final row in rows) {
      final id = row['id'];
      final full = stringAt(row, 'name');
      if (id is! num || full == null || full.trim().isEmpty) continue;
      final name = normalizePlatform(_platform(full));
      final seen = {name.toLowerCase()};
      final aka = [
        for (final other in [
          ?stringAt(row, 'abbreviation'),
          ...?stringAt(row, 'alternative_name')?.split(','),
          full,
        ])
          if (other.trim() case final o when o.isNotEmpty)
            if (seen.add(o.toLowerCase())) o,
      ];
      platforms.add((id: id.toInt(), name: name, aka: aka));
    }
    return platforms
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    // The same name again is usually a remake or a port; the year tells
    // them apart, and without one the first (IGDB's best) is taken.
    return pickByTitleAndYear(
      await _search(title, 10),
      title,
      year: year,
      titleOf: (m) => m.title,
      yearOf: (m) => m.released?.year,
    );
  }

  /// The collection in a game record (`collections`, expanded with their
  /// games), as a series: the games that are main games or remakes and no
  /// edition of another, in date order, numbered from 1. A game in several
  /// collections takes the one named [name] (the entry's series), else the
  /// one its title starts with ("Donkey Kong Country" is in "Donkey Kong
  /// Country" and in "Donkey Kong"), else the one its title names ("Rise of
  /// the Tomb Raider" is in "Tomb Raider: Survivor" and in "Tomb Raider"),
  /// the longest such name first, else the first listed. Null when the game
  /// is in no collection.
  static SeriesParts? _collectionOf(Map<String, Object?> game, {String? name}) {
    final collection = _seriesCollection(
      objectsAt(game, 'collections'),
      stringAt(game, 'name') ?? '',
      name: name,
    );
    if (collection == null) return null;
    final seriesName = stringAt(collection, 'name')!;
    final rule = switch (collection['id']) {
      final num id => _collectionRules[id.toInt()],
      _ => null,
    };
    final parts =
        [
          for (final g in objectsAt(collection, 'games'))
            if (g['id'] case final num id)
              if (stringAt(g, 'name') case final title?)
                if (g['version_parent'] == null &&
                    _isPart(g['game_type'], extra: rule?.types ?? const {}) &&
                    !(rule?.skip.contains(id.toInt()) ?? false))
                  (
                    id: id.toInt(),
                    title: title,
                    date: switch (g['first_release_date']) {
                      final num epoch => epoch.toInt(),
                      _ => null,
                    },
                    imageId: switch (g['cover']) {
                      final Map<String, Object?> cover => stringAt(
                        cover,
                        'image_id',
                      ),
                      _ => null,
                    },
                  ),
        ]..sort((a, b) {
          final x = a.date, y = b.date;
          if (x == null || y == null) {
            return x == null ? (y == null ? 0 : 1) : -1;
          }
          return x.compareTo(y);
        });
    return (
      name: seriesName,
      parts: [
        for (final (i, p) in parts.indexed)
          (
            number: i + 1,
            title: p.title,
            year: p.date == null ? null : _dayOf(p.date!).year,
            released: p.date == null ? null : _dayOf(p.date!),
            source: 'igdb:${p.id}',
            creator: null,
            cover: p.imageId == null ? null : coverUrlFor(p.imageId!),
            extra: false,
          ),
      ],
    );
  }

  /// The named collection among [collections] named [name]; else the one
  /// whose name [title] starts with, else contains (case aside), the
  /// longest first; else the first named one.
  static Map<String, Object?>? _seriesCollection(
    List<Map<String, Object?>> collections,
    String title, {
    String? name,
  }) {
    final named = [
      for (final c in collections)
        if (stringAt(c, 'name') case final name? when name.trim().isNotEmpty)
          (collection: c, name: name.trim().toLowerCase()),
    ];
    if (named.isEmpty) return null;
    if (name != null) {
      final wanted = name.trim().toLowerCase();
      for (final c in named) {
        if (c.name == wanted) return c.collection;
      }
    }
    final lower = title.trim().toLowerCase();
    List<({Map<String, Object?> collection, String name})> longestFirst(
      bool Function(String) test,
    ) =>
        named.where((c) => test(c.name)).toList()
          ..sort((a, b) => b.name.length.compareTo(a.name.length));
    return (longestFirst(lower.startsWith).firstOrNull ??
            longestFirst(lower.contains).firstOrNull ??
            named.first)
        .collection;
  }

  /// A game type IGDB gives as a number or an expanded object, counted as
  /// a part when it is one of [_partTypes] or [extra]; a record without one
  /// counts as a main game.
  static bool _isPart(Object? type, {Set<int> extra = const {}}) {
    bool counts(int id) => _partTypes.contains(id) || extra.contains(id);
    return switch (type) {
      null => true,
      final num id => counts(id.toInt()),
      final Map<String, Object?> expanded => switch (expanded['id']) {
        final num id => counts(id.toInt()),
        _ => true,
      },
      _ => true,
    };
  }

  /// Reads the game's collection, so the form gets its series and number.
  /// A port is no part of its own, so it takes the number of the game it is
  /// a port of.
  @override
  Future<LookupMatch> details(LookupMatch match) async {
    final game = await _collectionGame(match.source);
    final parts = game == null ? null : _collectionOf(game);
    if (parts == null) return match;
    final parent = switch (game!['parent_game']) {
      final num id => 'igdb:${id.toInt()}',
      _ => null,
    };
    final number =
        parts.parts.where((p) => p.source == match.source).firstOrNull ??
        parts.parts.where((p) => p.source == parent).firstOrNull;
    return match.copyWith(
      series: Series(name: parts.name, number: number?.number),
    );
  }

  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    final game = await _collectionGame(source);
    return game == null ? null : _collectionOf(game, name: name);
  }

  Future<Map<String, Object?>?> _collectionGame(String source) async {
    final games = await _games(
      'fields $_collectionFields; where id = ${_parse(source)}; limit 1;',
    );
    return games.firstOrNull;
  }

  static int _parse(String source) {
    final parts = source.split(':');
    final id = parts.length == 2 && parts[0] == 'igdb'
        ? int.tryParse(parts[1])
        : null;
    if (id == null) {
      throw LookupException(
        LookupFailure.other,
        message: 'not an IGDB id: $source',
      );
    }
    return id;
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    final games = await _games(
      'fields cover.image_id; where id = ${_parse(source)}; limit 1;',
    );
    if (games.isEmpty) return null;
    final cover = games.first['cover'] as Map<String, Object?>?;
    final imageId = cover == null ? null : stringAt(cover, 'image_id');
    return imageId == null ? null : coverUrlFor(imageId);
  }

  // Followed studios (Settings › Upcoming releases; DESIGN.md 10c).

  @override
  Set<FollowKind> get creatorKinds => const {FollowKind.studios};

  /// The company named exactly [name] among IGDB's hits, else the first.
  /// Wikidata says whether a studio was dissolved.
  @override
  Future<CreatorMatch?> findCreator(FollowKind kind, String name) async {
    final hits = await _games(
      'search ${_quote(name)}; fields id,name; limit 5;',
      endpoint: 'companies',
    );
    final exact = hits.where(
      (c) => (stringAt(c, 'name') ?? '').toLowerCase() == name.toLowerCase(),
    );
    final id = (exact.firstOrNull ?? hits.firstOrNull)?['id'];
    if (id is! num) return null;
    return (providerId: 'igdb:company:${id.toInt()}', inactive: null);
  }

  /// The games the company is involved in that came out from thirty days
  /// ago on, soonest first; packs and updates left out.
  @override
  Future<List<LookupMatch>> creatorReleases(
    String providerId,
    FollowKind kind, {
    required DateTime today,
  }) async {
    final parts = providerId.split(':');
    if (parts.length != 3 || parts[0] != 'igdb' || parts[1] != 'company') {
      throw LookupException(
        LookupFailure.other,
        message: 'not an IGDB company id: $providerId',
      );
    }
    final from =
        today.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final games = await _games(
      'fields $_searchFields; '
      'where involved_companies.company = ${parts[2]} & '
      'first_release_date >= $from & version_parent = null & '
      'game_type != (13, 14); '
      'sort first_release_date asc; limit 50;',
    );
    return [for (final game in games) ?_match(game)];
  }
}
