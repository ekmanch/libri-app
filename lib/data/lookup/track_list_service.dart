import '../images/artwork_resolver.dart';
import '../models/entry.dart';
import 'lookup_service.dart';
import 'music_source.dart';
import 'track_info.dart';
import 'track_list_store.dart';

/// A fetched track list, and whether it came from the device; or, with
/// [unmatched], the answer that the album has no online match, so nothing is
/// looked up and its tracks are the owner's own (`Entry.tracks`).
class TrackList {
  const TrackList(this.tracks, {required this.fromCache}) : unmatched = false;

  const TrackList.unmatched()
    : tracks = const [],
      fromCache = false,
      unmatched = true;

  final List<TrackInfo> tracks;
  final bool fromCache;
  final bool unmatched;
}

/// The track list of an album (Music › Album with track ratings): from the
/// store when it is there, else fetched from the music source and stored. The
/// album is known by its `source`, or by the id the artwork resolver matched it
/// to on the device. Opening an album writes nothing to the library.
class TrackListService {
  TrackListService({
    required this.lookups,
    required this.resolver,
    required this.store,
  });

  final LookupService lookups;
  final ArtworkResolver resolver;
  final TrackListStore store;

  /// The source that lists the album [source]: the one that issued the id
  /// (Apple Music for `itunes:album:<id>`), else the music source.
  TrackSource? _tracksOf(String source) {
    final issuer = lookups.sourceOf(source);
    if (issuer != null && issuer.isConfigured && issuer is TrackSource) {
      return issuer as TrackSource;
    }
    for (final source in lookups.sources) {
      if (source.isConfigured && source is MusicSource) {
        return source as MusicSource;
      }
    }
    return null;
  }

  /// [TrackList.unmatched] when the album has no `source` and the match on
  /// the device was made and found none; null when the source has no list
  /// for the album. Throws [LookupException] when the match or the fetch
  /// fails, so the sheet can tell a list that could not be loaded from an
  /// album without one.
  Future<TrackList?> load(Entry album) async {
    final source = album.source ?? await resolver.matchedSource(album);
    if (source == null) return const TrackList.unmatched();
    final cached = await store.read(source);
    if (cached != null) return TrackList(cached, fromCache: true);
    final music = _tracksOf(source);
    if (music == null) return null;
    final tracks = await music.albumTracks(source);
    if (tracks.isEmpty) return null;
    await store.write(source, tracks);
    return TrackList(tracks, fromCache: false);
  }

  /// Drops the lists of albums that are gone.
  Future<void> prune(Iterable<Entry> albums) => store.prune({
    for (final album in albums) ?(album.source ?? resolver.cachedSource(album)),
  });
}
