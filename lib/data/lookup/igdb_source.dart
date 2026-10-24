import '../models/media_type.dart';
import '../models/released.dart';
import '../models/series.dart';
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
class IgdbSource extends HttpLookupSource {
  IgdbSource(
    super.client, {
    required this.clientId,
    required this.clientSecret,
    required this.tokens,
    Uri? baseUrl,
    Uri? tokenUrl,
    super.timeout,
  }) : _baseUrl = baseUrl ?? Uri.https('api.igdb.com', '/v4/'),
       _tokenUrl = tokenUrl ?? Uri.https('id.twitch.tv', '/oauth2/token'),
       super(minGap: const Duration(milliseconds: 300));

  final String clientId;
  final String clientSecret;
  final IgdbTokenStore tokens;
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
      'name,collections.name,collections.games.name,'
      'collections.games.first_release_date,collections.games.game_type,'
      'collections.games.version_parent';

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

  /// Runs an Apicalypse [body] against `games`. A refused token is dropped
  /// and fetched again once.
  Future<List<Map<String, Object?>>> _games(String body) async {
    requireConfigured();
    for (var attempt = 0; ; attempt++) {
      final token = await _accessToken();
      final response = await send(
        () => client.post(
          _baseUrl.resolve('games'),
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

  Future<List<LookupMatch>> _search(String query, int limit) async {
    final games = await _games(
      'search ${_quote(query)}; fields $_fields; '
      'where version_parent = null; limit $limit;',
    );
    return [for (final game in games) ?_match(game)];
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) => _search(query, limit);

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
            year: p.date == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    p.date! * 1000,
                    isUtc: true,
                  ).year,
            source: 'igdb:${p.id}',
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
  @override
  Future<LookupMatch> details(LookupMatch match) async {
    final parts = await seriesParts(match.source);
    if (parts == null) return match;
    final number = parts.parts
        .where((p) => p.source == match.source)
        .firstOrNull;
    return match.copyWith(
      series: Series(name: parts.name, number: number?.number),
    );
  }

  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    final games = await _games(
      'fields $_collectionFields; where id = ${_parse(source)}; limit 1;',
    );
    if (games.isEmpty) return null;
    return _collectionOf(games.first, name: name);
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
}
