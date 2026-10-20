import '../models/media_type.dart';
import '../models/released.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'music_source.dart';
import 'text_clean.dart';
import 'track_info.dart';

/// Albums, songs, track lists, covers and artist photos from Deezer's
/// public API. No key. Ids are "deezer:album:302127" and
/// "deezer:track:3135556"; a song match also carries its album's id. The
/// search has no release date or genres, so [details] fetches the album
/// when a match is picked. Deezer answers errors as 200 with an `error`
/// object, which [_data] turns into failures.
class DeezerSource extends HttpLookupSource implements MusicSource {
  DeezerSource(super.client, {Uri? baseUrl, super.timeout})
    : _baseUrl = baseUrl ?? Uri.https('api.deezer.com'),
      super(minGap: const Duration(milliseconds: 120));

  final Uri _baseUrl;

  /// Names that are not an artist.
  static const noPhoto = {'various artists', 'unknown artist'};

  @override
  String get id => 'deezer';

  @override
  String get name => 'Deezer';

  @override
  Set<MediaType> get types => const {MediaType.music};

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  /// A GET that reads Deezer's answer: a failure for its `error` object
  /// (quota is rate limited, "no data" is null), else the JSON.
  Future<Map<String, Object?>?> _data(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await send(
      () => client.get(
        _baseUrl.replace(path: path, queryParameters: query),
        headers: _headers,
      ),
    );
    check(response);
    final json = decodeObject(response);
    final error = json['error'];
    if (error is Map<String, Object?>) {
      final code = error['code'];
      if (code == 800) return null;
      throw LookupException(
        code == 4 ? LookupFailure.rateLimited : LookupFailure.other,
        status: response.statusCode,
        message: stringAt(error, 'message') ?? 'Deezer error $code',
      );
    }
    return json;
  }

  Future<List<Map<String, Object?>>> _list(
    String path,
    Map<String, String> query,
  ) async => objectsAt(await _data(path, query) ?? const {}, 'data');

  static String? _artistName(Map<String, Object?> item) =>
      stringAt(item['artist'] as Map<String, Object?>? ?? const {}, 'name');

  LookupMatch? _album(Map<String, Object?> item) {
    final id = item['id'];
    final title = stringAt(item, 'title');
    if (id is! num || title == null) return null;
    return LookupMatch(
      type: MediaType.music,
      title: title,
      source: 'deezer:album:${id.toInt()}',
      creator: _artistName(item),
      coverUrl: stringAt(item, 'cover_medium'),
      largeCoverUrl: stringAt(item, 'cover_big'),
    );
  }

  LookupMatch? _track(Map<String, Object?> item) {
    final id = item['id'];
    final title = stringAt(item, 'title');
    if (id is! num || title == null) return null;
    final album = item['album'] as Map<String, Object?>? ?? const {};
    final albumId = album['id'];
    return LookupMatch(
      type: MediaType.music,
      title: title,
      source: 'deezer:track:${id.toInt()}',
      creator: _artistName(item),
      album: stringAt(album, 'title'),
      albumSource: albumId is num ? 'deezer:album:${albumId.toInt()}' : null,
      coverUrl: stringAt(album, 'cover_medium'),
      largeCoverUrl: stringAt(album, 'cover_big'),
    );
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async {
    final each = (limit / 2).ceil();
    final [albums, tracks] = await Future.wait([
      _list('/search/album', {'q': query, 'limit': '$each'}),
      _list('/search/track', {'q': query, 'limit': '$each'}),
    ]);
    return [
      for (final item in albums) ?_album(item),
      for (final item in tracks) ?_track(item),
    ];
  }

  /// Deezer's own query syntax, for an album by a known artist.
  static String _albumQuery(String title, String? artist) => [
    if (artist != null && artist.isNotEmpty) 'artist:"$artist"',
    'album:"$title"',
  ].join(' ');

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    final hits = [
      for (final item in await _list('/search/album', {
        'q': _albumQuery(title, creator),
        'limit': '10',
      }))
        ?_album(item),
    ];
    // The plain album before a remaster or a deluxe edition of it; the
    // artist must agree when one is known.
    final byArtist = [
      for (final hit in hits)
        if (creator == null ||
            creator.isEmpty ||
            (hit.creator != null && sameTitle(hit.creator!, creator)))
          hit,
    ];
    return pickByTitleAndYear(
      byArtist,
      title,
      year: null,
      titleOf: (m) => m.title,
      yearOf: (_) => null,
    );
  }

  /// ("album", "302127") from "deezer:album:302127".
  static (String kind, String id) _parse(String source) {
    final parts = source.split(':');
    if (parts.length != 3 ||
        parts[0] != 'deezer' ||
        (parts[1] != 'album' && parts[1] != 'track') ||
        int.tryParse(parts[2]) == null) {
      throw LookupException(
        LookupFailure.other,
        message: 'not a Deezer id: $source',
      );
    }
    return (parts[1], parts[2]);
  }

  /// The album record for an album or a track id.
  Future<Map<String, Object?>?> _albumOf(String source) async {
    final (kind, id) = _parse(source);
    if (kind == 'album') return _data('/album/$id');
    final track = await _data('/track/$id');
    final album = track?['album'] as Map<String, Object?>?;
    final albumId = album?['id'];
    return albumId is num ? _data('/album/${albumId.toInt()}') : null;
  }

  static Released? _released(Map<String, Object?> album) {
    final date = stringAt(album, 'release_date');
    return date == null ? null : Released.tryParse(date);
  }

  @override
  Future<LookupMatch> details(LookupMatch match) async {
    final album = await _albumOf(match.source);
    if (album == null) return match;
    final genres = album['genres'] as Map<String, Object?>? ?? const {};
    return match.copyWith(
      released: _released(album),
      tags: [for (final g in objectsAt(genres, 'data')) ?stringAt(g, 'name')],
      coverUrl: stringAt(album, 'cover_medium'),
    );
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    final album = await _albumOf(source);
    return album == null ? null : stringAt(album, 'cover_big');
  }

  @override
  Future<List<TrackInfo>> albumTracks(String albumSource) async {
    final (kind, id) = _parse(albumSource);
    if (kind != 'album') {
      throw LookupException(
        LookupFailure.other,
        message: 'not an album id: $albumSource',
      );
    }
    final items = await _list('/album/$id/tracks', {'limit': '200'});
    return [
      for (final item in items)
        if (item['id'] case final num trackId)
          if (stringAt(item, 'title') case final title?)
            (id: 'deezer:track:${trackId.toInt()}', title: title),
    ];
  }

  @override
  Future<String?> artistPhotoUrl(String name) async {
    if (noPhoto.contains(name.trim().toLowerCase())) return null;
    final hits = await _list('/search/artist', {'q': name, 'limit': '5'});
    for (final hit in hits) {
      final hitName = stringAt(hit, 'name');
      if (hitName != null && sameTitle(hitName, name)) {
        return stringAt(hit, 'picture_big');
      }
    }
    return null;
  }
}
