import '../models/media_type.dart';
import '../models/released.dart';
import 'http_lookup_source.dart';
import 'itunes_books.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'lookup_source.dart';
import 'music_lookup.dart';
import 'music_source.dart';
import 'text_clean.dart';
import 'track_info.dart';

/// Apple Music through the iTunes Search API, the second music catalog
/// (DESIGN.md 10c, "Apple Music on demand"): asked only when the owner
/// taps Extended search or "Search for more covers", and for the entries
/// saved from it, whose ids are `itunes:album:<id>` and `itunes:track:<id>`
/// (a plain `itunes:<id>` is an Apple Books id, see [ITunesBooks]). It
/// serves no type on its own ([types] is empty), so no search, automatic
/// match, artist list or daily check of new releases ever reaches it; an
/// entry's cover, track list and release date find it by the entry's id.
/// It asks on the books lookup's client and limiter ([api]), since the two
/// share Apple's twenty requests a minute. An empty answer from one store
/// is no reliable miss, so a search asks every one of [stores] and merges
/// by id, and a lookup by id asks them in turn until one answers.
class ITunesMusicSource extends LookupSource
    implements TrackSource, ExtendedMusicSource {
  ITunesMusicSource(this.api, {this.stores = const ['SE', 'US']});

  final ITunesBooks api;

  /// The storefronts asked, in order.
  final List<String> stores;

  /// How many rows one store is asked for.
  static const searchLimit = 50;

  @override
  String get id => ITunesBooks.id;

  @override
  String get name => 'Apple Music';

  @override
  Set<MediaType> get types => const {};

  @override
  bool issued(String source) => parse(source) != null;

  /// ("album", "1440650711") from "itunes:album:1440650711"; null for
  /// anything else, an Apple Books id ("itunes:6756269989") included.
  static (String kind, String id)? parse(String source) {
    final parts = source.split(':');
    if (parts.length != 3 ||
        parts[0] != ITunesBooks.id ||
        (parts[1] != 'album' && parts[1] != 'track') ||
        int.tryParse(parts[2]) == null) {
      return null;
    }
    return (parts[1], parts[2]);
  }

  static (String kind, String id) _parsed(String source) =>
      parse(source) ??
      (throw LookupException(
        LookupFailure.other,
        message: 'not an Apple Music id: $source',
      ));

  /// Never searched on its own: the music search is Deezer's.
  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async => const [];

  /// Never matched automatically.
  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async => null;

  /// Apple titles a single "Boss Bitch - Single" and an EP "… - EP".
  static final _recordNote = RegExp(r'\s+-\s+(Single|EP)$');

  static LookupMatch? _album(Map<String, Object?> item) {
    final id = item['collectionId'];
    final name = stringAt(item, 'collectionName');
    if (id is! num || name == null) return null;
    final note = _recordNote.firstMatch(name)?.group(1);
    final artwork = stringAt(item, 'artworkUrl100');
    return LookupMatch(
      type: MediaType.music,
      title: name.replaceFirst(_recordNote, ''),
      source: '${ITunesBooks.id}:album:${id.toInt()}',
      creator: stringAt(item, 'artistName'),
      released: _released(item),
      recordType: switch (note) {
        'Single' => 'single',
        'EP' => 'ep',
        _ => 'album',
      },
      tags: [?stringAt(item, 'primaryGenreName')],
      coverUrl: artwork == null
          ? null
          : ITunesBooks.artworkAt(artwork, ITunesBooks.rowArtwork),
      largeCoverUrl: artwork == null
          ? null
          : ITunesBooks.artworkAt(artwork, ITunesBooks.largeArtwork),
    );
  }

  static LookupMatch? _track(Map<String, Object?> item) {
    final id = item['trackId'];
    final title = stringAt(item, 'trackName');
    if (id is! num || title == null) return null;
    final albumId = item['collectionId'];
    final artwork = stringAt(item, 'artworkUrl100');
    return LookupMatch(
      type: MediaType.music,
      title: title,
      source: '${ITunesBooks.id}:track:${id.toInt()}',
      creator: stringAt(item, 'artistName'),
      released: _released(item),
      album: stringAt(item, 'collectionName')?.replaceFirst(_recordNote, ''),
      albumSource: albumId is num
          ? '${ITunesBooks.id}:album:${albumId.toInt()}'
          : null,
      tags: [?stringAt(item, 'primaryGenreName')],
      coverUrl: artwork == null
          ? null
          : ITunesBooks.artworkAt(artwork, ITunesBooks.rowArtwork),
      largeCoverUrl: artwork == null
          ? null
          : ITunesBooks.artworkAt(artwork, ITunesBooks.largeArtwork),
    );
  }

  static Released? _released(Map<String, Object?> item) {
    final date = stringAt(item, 'releaseDate')?.split('T').first;
    return date == null ? null : Released.tryParse(date);
  }

  static bool _isAlbum(Map<String, Object?> item) =>
      item['wrapperType'] == 'collection';

  static bool _isSong(Map<String, Object?> item) =>
      item['wrapperType'] == 'track' && item['kind'] == 'song';

  /// The records Apple lists for [id] ([entity] adds an album's songs), from
  /// the first store that has any.
  Future<List<Map<String, Object?>>> _lookup(
    String id, {
    String? entity,
  }) async {
    for (final store in stores) {
      final items = await api.objects('/lookup', {
        'id': id,
        'entity': ?entity,
        'country': store,
        'limit': '200',
      });
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  /// The album's or the song's own record as a match, or null when no
  /// store has it.
  Future<LookupMatch?> _record(String source) async {
    final (kind, id) = _parsed(source);
    final items = await _lookup(id);
    for (final item in items) {
      final match = kind == 'album'
          ? (_isAlbum(item) ? _album(item) : null)
          : (_isSong(item) ? _track(item) : null);
      if (match != null) return match;
    }
    return null;
  }

  /// The search rows already carry the date and the genre.
  @override
  Future<LookupMatch> details(LookupMatch match) async => match;

  @override
  Future<Released?> releaseDate(
    String source, {
    List<String> platforms = const [],
  }) async => (await _record(source))?.released;

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async =>
      (await _record(source))?.cacheCoverUrl;

  /// The album's songs in disc and track order.
  @override
  Future<List<TrackInfo>> albumTracks(String albumSource) async {
    final (kind, id) = _parsed(albumSource);
    if (kind != 'album') {
      throw LookupException(
        LookupFailure.other,
        message: 'not an album id: $albumSource',
      );
    }
    int at(Map<String, Object?> item, String key) =>
        item[key] is num ? (item[key]! as num).toInt() : 0;
    final songs = [
      for (final item in await _lookup(id, entity: 'song'))
        if (_isSong(item)) item,
    ];
    final ordered = [...songs.indexed]
      ..sort((a, b) {
        final byDisc = at(a.$2, 'discNumber').compareTo(at(b.$2, 'discNumber'));
        if (byDisc != 0) return byDisc;
        final byTrack = at(
          a.$2,
          'trackNumber',
        ).compareTo(at(b.$2, 'trackNumber'));
        return byTrack != 0 ? byTrack : a.$1.compareTo(b.$1);
      });
    return [
      for (final (_, item) in ordered)
        if (item['trackId'] case final num trackId)
          if (stringAt(item, 'trackName') case final title?)
            (id: '${ITunesBooks.id}:track:${trackId.toInt()}', title: title),
    ];
  }

  /// [term] in every store, merged by id in the stores' order. A store that
  /// fails after another answered is passed over; when none answered the
  /// failure is thrown.
  Future<List<LookupMatch>> _searchStores(String term, MusicScope scope) async {
    final songs = scope == MusicScope.songs;
    final seen = <String>{};
    final out = <LookupMatch>[];
    LookupException? failure;
    var answered = false;
    for (final store in stores) {
      final List<Map<String, Object?>> items;
      try {
        items = await api.objects('/search', {
          'term': term,
          'media': 'music',
          'entity': songs ? 'song' : 'album',
          'country': store,
          'limit': '$searchLimit',
        });
      } on LookupException catch (e) {
        failure = e;
        // Apple refusing one store refuses the next too.
        if (e.failure == LookupFailure.rateLimited ||
            e.failure == LookupFailure.offline) {
          break;
        }
        continue;
      }
      answered = true;
      for (final item in items) {
        final match = songs
            ? (_isSong(item) ? _track(item) : null)
            : (_isAlbum(item) ? _album(item) : null);
        if (match != null && seen.add(match.source)) out.add(match);
      }
    }
    if (!answered && failure != null) throw failure;
    return out;
  }

  @override
  Future<List<LookupMatch>> extendedSearch(String query, MusicScope scope) =>
      _searchStores(query.trim(), scope);

  /// The covers Apple has for the album [title] by [creator] (a song is
  /// asked by its album, which is what its cover shows): only albums of
  /// that title, edition notes set aside, and by that artist when known.
  @override
  Future<List<LookupMatch>> moreCovers(String title, {String? creator}) async {
    final hits = await _searchStores(
      [title, if (creator != null && creator.isNotEmpty) creator].join(' '),
      MusicScope.albums,
    );
    return [
      for (final hit in hits)
        if (hit.cacheCoverUrl != null && sameLooseTitle(hit.title, title))
          if (creator == null ||
              creator.isEmpty ||
              (hit.creator != null && sameTitle(hit.creator!, creator)))
            hit,
    ];
  }

  /// Apple Music's part of Pick a cover is asked on demand ([moreCovers]).
  @override
  Future<List<LookupMatch>> coverChoices(
    String title, {
    required MediaType type,
    String? creator,
  }) async => const [];
}
