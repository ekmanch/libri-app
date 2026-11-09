import 'music_lookup.dart';
import 'track_info.dart';

/// What the music source knows beyond matches: an album's track list (Music ›
/// Album with track ratings), an artist's photo and the pages of the music
/// lookup. Deezer implements it; so
/// does the fake. The services find it among the lookup sources, so nothing
/// else names Deezer.
abstract interface class MusicSource {
  /// The tracks of the album with lookup id [albumSource]
  /// ("deezer:album:302127"), in order. Throws [LookupException].
  Future<List<TrackInfo>> albumTracks(String albumSource);

  /// A photo of the artist called [name], or null when the source has no
  /// artist of exactly that name. "Various Artists" and "Unknown artist"
  /// never have one.
  Future<String?> artistPhotoUrl(String name);

  /// One page of a music list (Add / edit entry › Music search): up to
  /// [limit] matches from [MusicRequest.cursor] on, where the next page
  /// starts, and on a search's first page the artists whose names match.
  /// Throws [LookupException].
  Future<MusicPage> musicPage(
    MusicRequest request, {
    int limit = musicPageSize,
  });
}
