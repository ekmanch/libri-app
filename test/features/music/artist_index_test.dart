import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/features/music/artist_index.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

void main() {
  test('sorting ignores a leading "The" and shows the full name', () {
    expect(artistSortKey('The Beatles'), 'beatles');
    expect(artistSortKey('Theo'), 'theo');
    expect(artistLetter('The Cramps'), 'C');
    expect(artistLetter('2Pac'), '#');
    expect(artistLetter('Björk'), 'B');
  });

  test('groups the fixture by artist, Various Artists last', () {
    final artists = artistIndex(loadFixture().entries);
    final names = artists.map((a) => a.name).toList();
    expect(names.first, '2Pac');
    expect(names.last, 'Various Artists');
    final beatles = names.indexOf('The Beatles');
    expect(beatles, greaterThan(names.indexOf('Alice in Chains')));
    expect(beatles, lessThan(names.indexOf('Daft Punk')));
    final aic = artists.firstWhere((a) => a.name == 'Alice in Chains');
    expect(aic.countLabel, '1 album');
    expect(aic.initials, 'AI');
    expect(aic.ratedTracks.length, 3);
    final cramps = artists.firstWhere((a) => a.name == 'The Cramps');
    expect(cramps.countLabel, '1 song');
    expect(cramps.albums, isEmpty);
  });

  test('albums and songs are counted and ordered by year', () {
    final song = dirt.copyWith(
      id: 'music/would-alice-in-chains',
      title: 'Would?',
      kind: EntryKind.song,
      album: 'Dirt',
      tracks: null,
    );
    final older = dirt.copyWith(
      id: 'music/facelift-alice-in-chains',
      title: 'Facelift',
      released: null,
      tracks: null,
    );
    final artist = artistIndex([song, dirt, older]).single;
    expect(artist.countLabel, '2 albums, 1 song');
    // No year goes last in the year order.
    expect(artist.albums.map((e) => e.title), ['Dirt', 'Facelift']);
    expect(artist.songs.map((e) => e.title), ['Would?']);
  });

  test('names differing only in case are one artist; no name is Unknown', () {
    final a = dirt.copyWith(id: 'a', creator: 'alice in chains', tracks: null);
    final b = dirt.copyWith(id: 'b', creator: '', tracks: null);
    final artists = artistIndex([dirt, a, b]);
    expect(artists.map((x) => x.name), ['Alice in Chains', 'Unknown artist']);
    expect(artists.first.albums.length, 2);
  });

  test('sections by letter, Various Artists in its own last section', () {
    final sections = artistSections(artistIndex(loadFixture().entries));
    expect(sections.first.label, '#');
    expect(sections.last.label, 'Various Artists');
    expect(sections.last.railLabel, 'VA');
    expect(sections.map((s) => s.label), contains('B'));
    final b = sections.firstWhere((s) => s.label == 'B');
    expect(b.items.map((a) => a.name), ['The Beatles']);
  });
}
