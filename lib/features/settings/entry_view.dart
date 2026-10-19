/// How a list of entries is shown. Remembered per type on the device.
enum EntryView { text, listWithPhotos, grid }

extension EntryViewLabel on EntryView {
  /// The menu label (Library › View menu open): "with covers" for media and
  /// music albums, "with photos" for music artists and songs.
  String labelFor({required bool photos}) => switch (this) {
    EntryView.text => 'Text',
    EntryView.listWithPhotos =>
      photos ? 'List with photos' : 'List with covers',
    EntryView.grid => photos ? 'Grid with photos' : 'Grid with covers',
  };

  String get label => switch (this) {
    EntryView.text => 'Text',
    EntryView.listWithPhotos => 'List with photos',
    EntryView.grid => 'Grid',
  };
}
