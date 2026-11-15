import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/track_info.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/features/library/library_search.dart';
import 'package:library_app/features/music/song_search.dart';

import '../../helpers/pump_app.dart';

void main() {
  final fixture = loadFixture();
  final music = fixture.entriesOfType(MediaType.music);
  Entry album(String title) => music.firstWhere((e) => e.title == title);
  const darkSide = <TrackInfo>[
    (id: 'deezer:track:1', title: 'Speak to Me'),
    (id: 'deezer:track:4', title: 'Time'),
    (id: 'deezer:track:7', title: 'Us and Them'),
  ];
  List<String> rows(String q, {List<TrackInfo>? Function(Entry)? fetched}) => [
    for (final song in songsMatching(
      searchEntries(music, q),
      q,
      fetched: fetched ?? (_) => null,
    ))
      '${song.title}${song.rating == null ? '' : ' ${song.rating}'}',
  ];

  test('an album is found by the title of a rated track', () {
    expect(searchEntries(music, 'rooster').map((e) => e.title), ['Dirt']);
  });

  test('an artist named brings every track of their albums', () {
    // Until the list is on the device the stored tracks stand in.
    expect(rows('pink floyd'), ['Time 10', 'Us and Them 9']);
    // The fetched list in its order, with the stored ratings on it.
    expect(
      rows(
        'pink floyd',
        fetched: (a) =>
            a.title == 'The Dark Side of the Moon' ? darkSide : null,
      ),
      ['Speak to Me', 'Time 10', 'Us and Them 9'],
    );
  });

  test('a rated track the fetched list lacks comes after it', () {
    final items = tracksOf(album('The Dark Side of the Moon'), const [
      (id: 'deezer:track:4', title: 'Time'),
    ]);
    expect(items.map((s) => s.title), ['Time', 'Us and Them']);
    expect(items.map((s) => s.rating), [10, 9]);
    expect(items.every((s) => s.isTrack), isTrue);
  });

  test('a rated track is found by its own title, not its album', () {
    expect(rows('rooster'), ['Rooster 10']);
  });

  test('an album found by its title or a tag brings no tracks', () {
    expect(rows('dark side'), isEmpty);
    expect(rows('grunge'), isEmpty);
  });

  test('song entries are rows as before', () {
    final found = songsMatching(
      searchEntries(music, 'cramps'),
      'cramps',
      fetched: (_) => null,
    );
    expect(found.map((s) => s.title), ['Human Fly']);
    expect(found.single.isTrack, isFalse);
  });
}
