import '../models/follow_kind.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../upcoming/creator_lookup.dart';
import 'http_lookup_source.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'music_lookup.dart';
import 'music_source.dart';
import 'text_clean.dart';
import 'track_info.dart';

/// Albums, songs, track lists, covers and artist photos from Deezer's
/// public API. No key. Ids are "deezer:album:302127" and
/// "deezer:track:3135556"; a song match also carries its album's id. The
/// search has no release date or genres, so [details] fetches the album
/// when a match is picked. Deezer answers errors as 200 with an `error`
/// object, which [_data] turns into failures.
class DeezerSource extends HttpLookupSource
    implements MusicSource, CreatorLookup {
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
      recordType: stringAt(item, 'record_type'),
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

  /// The album's release date as Deezer has it now (a song's album's), for
  /// the daily check of music not out yet.
  @override
  Future<Released?> releaseDate(String source) async {
    final album = await _albumOf(source);
    return album == null ? null : _released(album);
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

  // The music lookup (Add / edit entry › Music search; DESIGN.md 10c).

  /// How many artists a search is asked for, to rank by fans.
  static const _artistHits = 25;

  /// An artist with this share of the best known hit's fans or less (a
  /// hundredth) is a near-unknown namesake and left out.
  static const _artistFanShare = 100;

  /// The matching artists of the last searches, so the Albums and the Songs
  /// page of one search ask once.
  final _artistsByQuery = <String, List<ArtistHit>>{};

  /// Every artist's album list asked this session, newest first, by
  /// Deezer's artist id.
  final _discographies = <String, List<Map<String, Object?>>>{};

  /// A page of one of Deezer's lists: its items, its `total`, and where its
  /// `next` page starts (null at the end). A page may hold fewer items than
  /// asked (Deezer drops what is not available) while the next still starts
  /// a whole page on, so the cursor follows `next`.
  Future<({List<Map<String, Object?>> items, int? total, int? next})> _page(
    String path,
    String query, {
    required int cursor,
    required int limit,
  }) async {
    final json =
        await _data(path, {
          'q': query,
          'index': '$cursor',
          'limit': '$limit',
        }) ??
        const {};
    final total = json['total'];
    final next = stringAt(json, 'next');
    final index = next == null
        ? null
        : int.tryParse(Uri.tryParse(next)?.queryParameters['index'] ?? '');
    return (
      items: objectsAt(json, 'data'),
      total: total is num ? total.toInt() : null,
      next: next == null
          ? null
          : (index != null && index > cursor ? index : cursor + limit),
    );
  }

  /// Up to three artists for a search, the best known first: Deezer ranks
  /// a search's artists poorly ("Ghost & Gale" before Ghost), so the hits
  /// go by their fans, and one with a hundredth of the best's fans or
  /// fewer is left out.
  Future<List<ArtistHit>> _matchingArtists(String query) async {
    final key = query.toLowerCase();
    if (_artistsByQuery[key] case final known?) return known;
    final hits = await _list('/search/artist', {
      'q': query,
      'limit': '$_artistHits',
    });
    final artists = bestArtists(hits);
    _artistsByQuery[key] = artists;
    while (_artistsByQuery.length > 20) {
      _artistsByQuery.remove(_artistsByQuery.keys.first);
    }
    return artists;
  }

  /// The ranking of [_matchingArtists], on Deezer's artist records.
  static List<ArtistHit> bestArtists(List<Map<String, Object?>> hits) {
    int fans(Map<String, Object?> hit) =>
        hit['nb_fan'] is num ? (hit['nb_fan']! as num).toInt() : 0;
    // Equal fans keep Deezer's order.
    final ranked = [...hits.indexed]
      ..sort((a, b) {
        final byFans = fans(b.$2).compareTo(fans(a.$2));
        return byFans != 0 ? byFans : a.$1.compareTo(b.$1);
      });
    final best = ranked.isEmpty ? 0 : fans(ranked.first.$2);
    final artists = <ArtistHit>[];
    for (final (_, hit) in ranked) {
      if (artists.length == matchingArtists) break;
      if (fans(hit) * _artistFanShare <= best) continue;
      final id = hit['id'];
      final name = stringAt(hit, 'name');
      if (id is! num || name == null) continue;
      if (noPhoto.contains(name.trim().toLowerCase())) continue;
      final albums = hit['nb_album'];
      artists.add(
        ArtistHit(
          source: 'deezer:artist:${id.toInt()}',
          name: name,
          pictureUrl: stringAt(hit, 'picture_medium'),
          albums: albums is num ? albums.toInt() : null,
        ),
      );
    }
    return artists;
  }

  /// Every album, EP and single of the artist with Deezer's id [id],
  /// newest first (Deezer lists the albums, then the EPs, then the
  /// singles, each newest first), the undated last in Deezer's order;
  /// asked once a session.
  Future<List<Map<String, Object?>>> _discography(String id) async {
    if (_discographies[id] case final known?) return known;
    final albums = await _list('/artist/$id/albums', {'limit': '1000'});
    DateTime? day(Map<String, Object?> album) =>
        _released(album)?.availableFrom;
    final sorted = [...albums.indexed]
      ..sort((a, b) {
        final (dayA, dayB) = (day(a.$2), day(b.$2));
        if (dayA != null && dayB != null && dayA != dayB) {
          return dayB.compareTo(dayA);
        }
        if ((dayA == null) != (dayB == null)) return dayA == null ? 1 : -1;
        return a.$1.compareTo(b.$1);
      });
    return _discographies[id] = [for (final (_, album) in sorted) album];
  }

  /// The artist's songs from their albums, newest album first, from the
  /// album at [cursor] until [limit] songs are found; songs by others on
  /// the artist's records (a soundtrack's) are left out. A single repeats
  /// its album's title; the list that shows them keeps each title once.
  Future<MusicPage> _artistSongs(
    String artistId,
    String artist,
    int cursor,
    int limit,
  ) async {
    final albums = await _discography(artistId);
    final matches = <LookupMatch>[];
    var at = cursor;
    while (at < albums.length && matches.length < limit) {
      final album = albums[at];
      at++;
      final albumId = album['id'];
      if (albumId is! num) continue;
      final tracks = await _list('/album/${albumId.toInt()}/tracks', {
        'limit': '200',
      });
      for (final item in tracks) {
        final by = (item['artist'] as Map<String, Object?>?)?['id'];
        if (by is! num || '${by.toInt()}' != artistId) continue;
        final id = item['id'];
        final title = stringAt(item, 'title');
        if (id is! num || title == null) continue;
        matches.add(
          LookupMatch(
            type: MediaType.music,
            title: title,
            source: 'deezer:track:${id.toInt()}',
            creator: artist,
            album: stringAt(album, 'title'),
            albumSource: 'deezer:album:${albumId.toInt()}',
            released: _released(album),
            coverUrl: stringAt(album, 'cover_medium'),
            largeCoverUrl: stringAt(album, 'cover_big'),
          ),
        );
      }
    }
    return MusicPage(matches: matches, next: at < albums.length ? at : null);
  }

  @override
  Future<MusicPage> musicPage(
    MusicRequest request, {
    int limit = musicPageSize,
  }) async {
    final cursor = request.cursor;
    switch (request.list) {
      case MusicSearch(:final query):
        final songs = request.scope == MusicScope.songs;
        final page = await _page(
          songs ? '/search/track' : '/search/album',
          query,
          cursor: cursor,
          limit: limit,
        );
        return MusicPage(
          matches: [
            for (final item in page.items) ?(songs ? _track : _album)(item),
          ],
          total: page.total,
          next: page.next,
          artists: cursor == 0 ? await _matchingArtists(query) : const [],
        );
      case MusicArtist(:final source, :final name):
        final parts = source.split(':');
        if (parts.length != 3 || parts[0] != 'deezer' || parts[1] != 'artist') {
          throw LookupException(
            LookupFailure.other,
            message: 'not a Deezer artist id: $source',
          );
        }
        if (request.scope == MusicScope.songs) {
          return _artistSongs(parts[2], name, cursor, limit);
        }
        final albums = await _discography(parts[2]);
        final end = (cursor + limit).clamp(0, albums.length);
        return MusicPage(
          matches: [
            // An artist's list names no artist: they are all theirs.
            for (final item in albums.skip(cursor).take(limit))
              ?_album(item)?.copyWith(creator: name, released: _released(item)),
          ],
          total: albums.length,
          next: end < albums.length ? end : null,
        );
    }
  }

  // Followed artists (Settings › Upcoming releases; DESIGN.md 10c).

  @override
  Set<FollowKind> get creatorKinds => const {FollowKind.artists};

  /// The artist named exactly [name] among Deezer's hits, else the first.
  /// Deezer does not say when a band broke up; Wikidata does.
  @override
  Future<CreatorMatch?> findCreator(FollowKind kind, String name) async {
    final hits = await _list('/search/artist', {'q': name, 'limit': '5'});
    final exact = hits.where(
      (a) => (stringAt(a, 'name') ?? '').toLowerCase() == name.toLowerCase(),
    );
    final id = (exact.firstOrNull ?? hits.firstOrNull)?['id'];
    if (id is! num) return null;
    return (providerId: 'deezer:artist:${id.toInt()}', inactive: null);
  }

  /// The artist's newest albums and EPs (singles and compilations left
  /// out), each dated as Deezer lists it, soonest first.
  @override
  Future<List<LookupMatch>> creatorReleases(
    String providerId,
    FollowKind kind, {
    required DateTime today,
  }) async {
    final parts = providerId.split(':');
    if (parts.length != 3 || parts[0] != 'deezer' || parts[1] != 'artist') {
      throw LookupException(
        LookupFailure.other,
        message: 'not a Deezer artist id: $providerId',
      );
    }
    final artist = await _data('/artist/${parts[2]}');
    final name = artist == null ? null : stringAt(artist, 'name');
    final albums = await _list('/artist/${parts[2]}/albums', {'limit': '50'});
    return [
      for (final item in albums)
        if (const {'album', 'ep'}.contains(item['record_type']))
          if (_album(item) case final match?)
            if (_released(item) case final released?
                when isRecentOrAhead(released, today))
              match.copyWith(released: released, creator: name),
    ]..sort(
      (a, b) => a.released!.availableFrom.compareTo(b.released!.availableFrom),
    );
  }
}
