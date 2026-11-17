import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../covers/artist_photos.dart';
import '../net/http_transport.dart';
import '../storage/json_file.dart';
import 'http_lookup_source.dart';
import 'itunes_books.dart';
import 'lookup_failure.dart';

/// What asking Apple about an artist came to. Only these are real answers;
/// a failure (offline, refused, a server error) is neither.
sealed class ArtistFound {
  const ArtistFound();
}

/// The photo as Apple serves it: a 640 × 640 JPEG.
class ArtistPhotoFound extends ArtistFound {
  const ArtistPhotoFound(this.bytes);

  final Uint8List bytes;
}

class ArtistNotFound extends ArtistFound {
  const ArtistNotFound(this.reason);

  final MissingReason reason;
}

/// Another Apple artist of the name, for Pick a photo: its page, and one
/// of its albums to tell it by.
typedef OtherArtist = ({String id, String page, String? album});

/// What Pick a photo offers from Apple for an artist: the matched artist's
/// photo, and the other artists of the name, whose pages are read only
/// when asked for.
typedef ArtistChoices = ({String? suggested, List<OtherArtist> others});

/// An artist's photo from Apple Music, as the desktop finds it (DESIGN.md
/// section 10e; the desktop's `lookup::apple_artists`).
///
/// Three kinds of request, each with its own pace. The match goes through
/// the iTunes Search API on the books lookup's client and limiter ([api];
/// the same host and the same limit of about twenty requests a minute): one
/// search for the artists of the name in the US store, then each
/// namesake's album list, at most [namesakeLimit], and, when none of them
/// lists an owned album, one song search for each of up to three saved
/// songs. The photo is read from
/// the matched artist's `music.apple.com` page, the one exception to "no
/// scraping": one page every two to four seconds with random spacing. The
/// image itself comes from Apple's image host.
///
/// Nothing here tries a refused request again: a 403 or a 429 stops the
/// photo work for the session ([stopped]), and every later call fails as
/// rate limited without a request. What was answered is kept in
/// `apple_artists.json` under the cache folder ([file]), so Pick a photo
/// reads no page twice.
class AppleArtists {
  AppleArtists(
    this.api, {
    this.file,
    this.pageGap = const Duration(seconds: 2),
    this.pageJitter = const Duration(seconds: 2),
    Random? random,
    DateTime Function()? now,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now;

  final ITunesBooks api;
  final JsonFile? file;
  final Duration pageGap;
  final Duration pageJitter;
  final Random _random;
  final DateTime Function() _now;

  /// The namesakes whose album lists are asked for, at most.
  static const namesakeLimit = 10;

  static const _version = 1;

  /// Apple refused a request this session: nothing more is asked.
  bool get stopped => _stopped;
  bool _stopped = false;

  final _names = <String, List<ArtistCandidate>>{};

  /// The songs searched for, by the artist's name key, each as its
  /// title's key: a song is searched for once per list of namesakes.
  final _songs = <String, List<String>>{};
  final _photos = <String, String?>{};
  Future<void>? _loading;
  DateTime? _nextPage;

  http.Client get _client => api.client;

  Future<void> _load() => _loading ??= () async {
    final json = await file?.read();
    if (json == null || json['version'] != _version) return;
    if (json['names'] case final Map<String, Object?> names) {
      for (final MapEntry(:key, :value) in names.entries) {
        _names[key] = [
          for (final item in value as List<Object?>? ?? const [])
            ?ArtistCandidate.fromJson(item),
        ];
      }
    }
    if (json['songs'] case final Map<String, Object?> songs) {
      for (final MapEntry(:key, :value) in songs.entries) {
        _songs[key] = [
          for (final title in value as List<Object?>? ?? const [])
            if (title is String) title,
        ];
      }
    }
    if (json['photos'] case final Map<String, Object?> photos) {
      for (final MapEntry(:key, :value) in photos.entries) {
        _photos[key] = value as String?;
      }
    }
  }();

  Future<void> _keep() async {
    try {
      await file?.write({
        'version': _version,
        'names': {
          for (final MapEntry(:key, :value) in _names.entries)
            key: [for (final candidate in value) candidate.toJson()],
        },
        'songs': _songs,
        'photos': _photos,
      });
    } on Exception {
      // A cache: asked again next time.
    }
  }

  /// Runs [request], and stops the session's photo work when Apple
  /// refuses.
  Future<T> _guard<T>(Future<T> Function() request) async {
    if (_stopped) {
      throw const LookupException(
        LookupFailure.rateLimited,
        message: 'Apple stopped answering this session',
      );
    }
    try {
      return await request();
    } on LookupException catch (e) {
      if (e.failure == LookupFailure.rateLimited) _stopped = true;
      rethrow;
    }
  }

  /// The Apple artists whose name is [name] by `sameArtistName`.
  Future<List<ArtistCandidate>> namesakes(String name) => _guard(() async {
    final items = await api.objects('/search', {
      'term': name,
      'media': 'music',
      'entity': 'musicArtist',
      'attribute': 'artistTerm',
      'limit': '50',
    }, once: true);
    return namesakesIn(items, name);
  });

  /// The artists of a search answer whose name is [name].
  static List<ArtistCandidate> namesakesIn(
    List<Map<String, Object?>> items,
    String name,
  ) => [
    for (final item in items)
      if (stringAt(item, 'artistName') case final found?)
        if (item['artistId'] case final num id)
          if (sameArtistName(found, name))
            ArtistCandidate(
              id: '${id.toInt()}',
              name: found,
              page: _pageOf(item, '${id.toInt()}'),
            ),
  ];

  /// The link carries a tracking query the page does not need.
  static String _pageOf(Map<String, Object?> item, String id) {
    final link = stringAt(item, 'artistLinkUrl')?.split('?').first;
    return link != null && link.startsWith('https://music.apple.com/')
        ? link
        : 'https://music.apple.com/us/artist/$id';
  }

  /// The titles of the artist's albums.
  Future<List<String>> albums(String id) => _guard(() async {
    final items = await api.objects('/lookup', {
      'id': id,
      'entity': 'album',
      'limit': '200',
    }, once: true);
    return [
      for (final item in items)
        if (item['wrapperType'] == 'collection')
          ?stringAt(item, 'collectionName'),
    ];
  });

  /// The tracks a search for the artist's song [title] finds, each as its
  /// artist's id and its name. One request, on the same client and limiter
  /// as the other searches, and refused like them.
  Future<List<({String id, String track})>> songRows(
    String name,
    String title,
  ) => _guard(() async {
    final items = await api.objects('/search', {
      'term': '$name $title',
      'media': 'music',
      'entity': 'song',
      'limit': '50',
    }, once: true);
    return songsIn(items);
  });

  /// The tracks of a song search's answer, each as its artist's id and
  /// its name.
  static List<({String id, String track})> songsIn(
    List<Map<String, Object?>> items,
  ) => [
    for (final item in items)
      if (item['wrapperType'] == 'track')
        if (item['artistId'] case final num id)
          if (stringAt(item, 'trackName') case final track?)
            (id: '${id.toInt()}', track: track),
  ];

  /// [listed] with the artist's saved songs searched for, when the albums
  /// tell nothing: no namesake lists an owned album and there are songs to
  /// ask about (`songsAsked`, three at most). A song is searched for once;
  /// what the searches found is kept with the namesakes.
  Future<List<ArtistCandidate>> _withSongs(
    String name,
    Iterable<String> owned,
    Iterable<String> songs,
    List<ArtistCandidate> listed,
  ) async {
    if (listed.isEmpty || listsOwned(name, owned, listed)) return listed;
    final key = artistNameKey(name);
    final asked = [...?_songs[key]];
    final out = [...listed];
    var changed = false;
    for (final title in songsAsked(songs)) {
      final titleKey = artistNameKey(title);
      if (asked.contains(titleKey)) continue;
      for (final (:id, :track) in await songRows(name, title)) {
        final at = out.indexWhere((candidate) => candidate.id == id);
        if (at >= 0 && !out[at].songs.contains(track)) {
          out[at] = out[at].withSongs([...out[at].songs, track]);
        }
      }
      asked.add(titleKey);
      changed = true;
    }
    if (changed) {
      _names[key] = out;
      _songs[key] = asked;
      await _keep();
    }
    return out;
  }

  /// The namesakes with their album lists, for `chooseArtist`; asked anew
  /// and kept. The songs searched for before go with the old list.
  Future<List<ArtistCandidate>> candidates(String name) async {
    await _load();
    final out = <ArtistCandidate>[];
    for (final namesake in (await namesakes(name)).take(namesakeLimit)) {
      out.add(
        ArtistCandidate(
          id: namesake.id,
          name: namesake.name,
          page: namesake.page,
          albums: await albums(namesake.id),
        ),
      );
    }
    final key = artistNameKey(name);
    _songs.remove(key);
    _names[key] = out;
    await _keep();
    return out;
  }

  /// [candidates] as kept from an earlier ask, else asked now.
  Future<List<ArtistCandidate>> _candidatesKept(String name) async {
    await _load();
    return _names[artistNameKey(name)] ?? await candidates(name);
  }

  /// The URL of the photo on the artist's page, or null when the page
  /// shows none (an album cover, another kind of image, no page). Pages
  /// are read [pageGap] apart plus up to [pageJitter] at random.
  Future<String?> photoOn(String page) => _guard(() async {
    final next = _nextPage;
    final now = _now();
    final jitter = pageJitter.inMilliseconds <= 0
        ? Duration.zero
        : Duration(milliseconds: _random.nextInt(pageJitter.inMilliseconds));
    final wait =
        (next == null || next.isBefore(now)
            ? Duration.zero
            : next.difference(now)) +
        (next == null ? Duration.zero : jitter);
    _nextPage = now.add(wait + pageGap);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    final http.Response response;
    try {
      response = await sendOrOffline(
        () => _client.get(
          Uri.parse(page),
          headers: {'Accept': 'text/html', 'User-Agent': api.userAgent},
        ),
        timeout: api.timeout,
      );
    } on NetworkUnreachable catch (e) {
      throw LookupException(LookupFailure.offline, message: e.message);
    } on FormatException catch (e) {
      throw LookupException(LookupFailure.other, message: e.message);
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw LookupException(
        LookupFailure.rateLimited,
        status: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw LookupException(LookupFailure.other, status: response.statusCode);
    }
    final image = ogImage(String.fromCharCodes(response.bodyBytes));
    return image == null ? null : artistPhotoUrl(image);
  });

  /// The photo on the page of the artist [id], read once and kept.
  Future<String?> photoOf(String id, String page) async {
    await _load();
    if (_photos.containsKey(id)) return _photos[id];
    final url = await photoOn(page);
    _photos[id] = url;
    await _keep();
    return url;
  }

  /// The image at [url], which must be a JPEG.
  Future<Uint8List> image(String url) => _guard(() async {
    final http.Response response;
    try {
      response = await sendOrOffline(
        () =>
            _client.get(Uri.parse(url), headers: {'User-Agent': api.userAgent}),
        timeout: api.timeout,
      );
    } on NetworkUnreachable catch (e) {
      throw LookupException(LookupFailure.offline, message: e.message);
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw LookupException(
        LookupFailure.rateLimited,
        status: response.statusCode,
      );
    }
    final bytes = response.bodyBytes;
    if (response.statusCode != 200) {
      throw LookupException(LookupFailure.other, status: response.statusCode);
    }
    if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const LookupException(
        LookupFailure.other,
        message: 'the photo is not a JPEG',
      );
    }
    return bytes;
  });

  /// Asks Apple about the library's artist [name], whose saved album
  /// titles are [owned] and whose saved songs are [songs]: the match, its
  /// page, the photo. Throws [LookupException] when Apple could not be
  /// asked, which is no answer.
  Future<ArtistFound> find(
    String name,
    Iterable<String> owned, [
    Iterable<String> songs = const [],
  ]) async {
    final listed = await _withSongs(name, owned, songs, await candidates(name));
    final chosen = chooseArtist(name, owned, songs, listed);
    if (chosen == null) return const ArtistNotFound(MissingReason.noMatch);
    final photo = await photoOn(chosen.page ?? '');
    _photos[chosen.id] = photo;
    await _keep();
    if (photo == null) return const ArtistNotFound(MissingReason.noPhoto);
    return ArtistPhotoFound(await image(photo));
  }

  /// What Pick a photo offers from Apple: the matched artist's photo, and
  /// the other artists of the name with one album each, their pages
  /// unread.
  Future<ArtistChoices> choices(
    String name,
    Iterable<String> owned, [
    Iterable<String> songs = const [],
  ]) async {
    final listed = await _withSongs(
      name,
      owned,
      songs,
      await _candidatesKept(name),
    );
    final chosen = chooseArtist(name, owned, songs, listed)?.id;
    String? suggested;
    final others = <OtherArtist>[];
    for (final candidate in listed) {
      final page = candidate.page ?? '';
      if (candidate.id == chosen) {
        suggested = await photoOf(candidate.id, page);
      } else {
        others.add((
          id: candidate.id,
          page: page,
          album: candidate.albums.firstOrNull,
        ));
      }
    }
    return (suggested: suggested, others: others);
  }
}
