import 'lookup_match.dart';
import 'music_lookup.dart';
import 'track_info.dart';

/// A source that lists the tracks of its own albums. An album's track list
/// follows the album's own id, so an album saved from the second catalog
/// (`itunes:album:<id>`) is listed by that catalog, not by Deezer.
abstract interface class TrackSource {
  /// The tracks of the album with lookup id [albumSource]
  /// ("deezer:album:302127"), in order. Throws [LookupException].
  Future<List<TrackInfo>> albumTracks(String albumSource);
}

/// The second music catalog, asked only on demand (Add / edit entry ›
/// Extended search: more results; Pick a cover: more covers found). Apple
/// Music implements it; so does the fake.
abstract interface class ExtendedMusicSource {
  /// Every album or song the catalog finds for [query], in its own order.
  /// Throws [LookupException].
  Future<List<LookupMatch>> extendedSearch(String query, MusicScope scope);

  /// Albums titled [title] (by [creator] when known), each with a cover,
  /// for Pick a cover. Throws [LookupException].
  Future<List<LookupMatch>> moreCovers(String title, {String? creator});
}

/// What the music source knows beyond matches: an album's track list (Music ›
/// Album with track ratings), an artist's photo and the pages of the music
/// lookup. Deezer implements it; so
/// does the fake. The services find it among the lookup sources, so nothing
/// else names Deezer.
abstract interface class MusicSource implements TrackSource {
  @override
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
