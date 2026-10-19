import '../../data/models/music_kind.dart';

/// The three tabs of the music list (Library › Music: artists, text view). The
/// view is remembered per tab. Albums and Songs match the filter sheet's Kind;
/// Artists is a way of browsing, not a filter.
enum MusicTab {
  artists,
  albums,
  songs;

  static MusicTab forKind(MusicKind? kind) => switch (kind) {
    null => artists,
    MusicKind.album => albums,
    MusicKind.song => songs,
  };

  MusicKind? get kind => switch (this) {
    artists => null,
    albums => MusicKind.album,
    songs => MusicKind.song,
  };
}

extension MusicTabLabel on MusicTab {
  String get label => switch (this) {
    MusicTab.artists => 'Artists',
    MusicTab.albums => 'Albums',
    MusicTab.songs => 'Songs',
  };
}
