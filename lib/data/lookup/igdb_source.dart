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
      'genres.name';

  @override
  String get id => 'igdb';

  @override
  String get name => 'IGDB';

  /// The collection a game is in, with its games: the series and its
  /// parts. `game_type` tells main games and remakes from bundles, DLC,
  /// remasters and ports, which are left out of the parts.
  static const _collectionFields =
      'collection.name,collection.games.name,'
      'collection.games.first_release_date,collection.games.game_type,'
      'collection.games.version_parent';

  /// IGDB's game types that count as a part of a series: 0 is a main game,
  /// 8 a remake.
  static const _partTypes = {0, 8};

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

  /// The collection in a game record (`collection`, expanded with its
  /// games), as a series: the games that are main games or remakes and no
  /// edition of another, in date order, numbered from 1. Null when the
  /// game is in no collection.
  static SeriesParts? _collectionOf(Map<String, Object?> game) {
    final collection = game['collection'];
    if (collection is! Map<String, Object?>) return null;
    final name = stringAt(collection, 'name');
    if (name == null) return null;
    final parts = [
      for (final g in objectsAt(collection, 'games'))
        if (g['id'] case final num id)
          if (stringAt(g, 'name') case final title?)
            if (g['version_parent'] == null && _isPart(g['game_type']))
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
      if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
      return x.compareTo(y);
    });
    return (
      name: name,
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

  /// A game type IGDB gives as a number or an expanded object; a record
  /// without one counts as a main game.
  static bool _isPart(Object? type) => switch (type) {
    null => true,
    final num id => _partTypes.contains(id.toInt()),
    final Map<String, Object?> expanded => switch (expanded['id']) {
      final num id => _partTypes.contains(id.toInt()),
      _ => true,
    },
    _ => true,
  };

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
    return _collectionOf(games.first);
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
