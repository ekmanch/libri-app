import '../../data/models/entry_kind.dart';

/// The three tabs of the music list (Library › Music: artists, text view). The
/// view is remembered per tab. Albums and Songs match the filter sheet's Kind;
/// Artists is a way of browsing, not a filter.
enum MusicTab {
  artists,
  albums,
  songs;

  static MusicTab forKind(EntryKind? kind) => switch (kind) {
    EntryKind.album => albums,
    EntryKind.song => songs,
    _ => artists,
  };

  EntryKind? get kind => switch (this) {
    artists => null,
    albums => EntryKind.album,
    songs => EntryKind.song,
  };
}

extension MusicTabLabel on MusicTab {
  String get label => switch (this) {
    MusicTab.artists => 'Artists',
    MusicTab.albums => 'Albums',
    MusicTab.songs => 'Songs',
  };
}
