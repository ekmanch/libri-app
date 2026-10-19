import '../images/artwork_resolver.dart';
import '../models/entry.dart';
import 'lookup_service.dart';
import 'music_source.dart';
import 'track_info.dart';
import 'track_list_store.dart';

/// A fetched track list, and whether it came from the device.
class TrackList {
  const TrackList(this.tracks, {required this.fromCache});

  final List<TrackInfo> tracks;
  final bool fromCache;
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

  MusicSource? get _music {
    for (final source in lookups.sources) {
      if (source.isConfigured && source is MusicSource) {
        return source as MusicSource;
      }
    }
    return null;
  }

  /// Null when no album id could be found (no source, no match). Throws
  /// [LookupException] when the fetch fails, so the sheet can tell being
  /// offline from an album the source does not know.
  Future<TrackList?> load(Entry album) async {
    final source = album.source ?? await resolver.matchedSource(album);
    if (source == null) return null;
    final cached = await store.read(source);
    if (cached != null) return TrackList(cached, fromCache: true);
    final music = _music;
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
