import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/features/library/entry_sections.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/library/sectioned_list_body.dart';
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

  group('the orders of the Artists tab', () {
    Entry album(String artist, String title, DateTime added) => dirt.copyWith(
      id: 'music/$title',
      title: title,
      creator: artist,
      added: added,
      tracks: null,
    );
    Entry song(String artist, String title, DateTime added) =>
        album(artist, title, added).copyWith(kind: EntryKind.song);
    final day1 = DateTime(2026, 1, 1), day2 = DateTime(2026, 1, 2);
    // In the library's order.
    final entries = [
      album('Zebra', 'z1', day1),
      album('The Beatles', 'b1', day1),
      album('The Beatles', 'b2', day1),
      song('Abba', 'a1', day2),
      song('Abba', 'a2', day1),
      song('Abba', 'a3', day1),
      album('Various Artists', 'v1', day1),
      song('Cher', 'c1', day1),
    ];
    List<String> names(ArtistsSort sort) => [
      for (final a in artistIndex(entries, sort: sort)) a.name,
    ];

    test('the menu, in order', () {
      expect(ArtistsSort.values.map((s) => s.label), [
        'Name, A to Z',
        'Newest added',
        'Most albums',
        'Most songs',
      ]);
    });

    test('by name is the default', () {
      expect(artistIndex(entries).map((a) => a.name), [
        'Abba',
        'The Beatles',
        'Cher',
        'Zebra',
        'Various Artists',
      ]);
    });

    test('newest added: the newest album or song, later in the library '
        'first on the same day', () {
      expect(names(ArtistsSort.newestAdded), [
        'Abba',
        'Cher',
        'Various Artists',
        'The Beatles',
        'Zebra',
      ]);
    });

    test('most albums, ties by name with Various Artists last', () {
      expect(names(ArtistsSort.mostAlbums), [
        'The Beatles',
        'Zebra',
        'Various Artists',
        'Abba',
        'Cher',
      ]);
    });

    test('most songs counts song entries, never tracks rated on an album', () {
      // Dirt has rated tracks and no song entry.
      expect(dirt.tracks, isNotEmpty);
      final list = artistIndex([...entries, dirt], sort: ArtistsSort.mostSongs);
      expect(list.map((a) => a.name), [
        'Abba',
        'Cher',
        'Alice in Chains',
        'The Beatles',
        'Zebra',
        'Various Artists',
      ]);
    });
    group('sections follow the sort', () {
      List<ListSection<ArtistSummary>> sections(
        List<Entry> entries,
        ArtistsSort sort,
      ) => artistSections(
        artistIndex(entries, sort: sort),
        sort: sort,
        today: DateTime(2026, 11, 15),
      );

      test('newest added: this year\'s months, then years', () {
        final list = sections([
          album('Old', 'o1', DateTime(2024, 5, 1)),
          album('Mid', 'm1', DateTime(2025, 12, 31)),
          album('New', 'n1', DateTime(2026, 3, 1)),
          // An artist counts from the newest of its albums and songs.
          album('Old and new', 'x1', DateTime(2023, 1, 1)),
          song('Old and new', 'x2', DateTime(2026, 11, 2)),
        ], ArtistsSort.newestAdded);
        expect(list.map((s) => s.label), [
          'November 2026',
          'March 2026',
          '2025',
          '2024',
        ]);
        expect(list.map((s) => s.railLabel), ['Nov', 'Mar', '2025', '2024']);
        expect(list.first.items.single.name, 'Old and new');
      });

      test('newest added: the oldest years merge into Older', () {
        final list = sections([
          for (var month = 1; month <= 11; month++)
            album('m$month', 'm$month', DateTime(2026, month, 1)),
          for (var year = 2000; year <= 2025; year++)
            album('y$year', 'y$year', DateTime(year, 6, 1)),
        ], ArtistsSort.newestAdded);
        expect(list.length, maxRailLabels);
        expect(list.first.label, 'November 2026');
        expect(list[10].label, 'January 2026');
        expect(list[11].label, '2025');
        expect(list[maxRailLabels - 2].label, '2014');
        expect(list.last.label, 'Older');
        expect(list.last.railLabel, 'Older');
        expect(list.last.items.map((a) => a.name).first, 'y2013');
        expect(list.last.items.length, 14);
      });

      test('most albums: the counts, highest first, then No albums', () {
        final list = sections(entries, ArtistsSort.mostAlbums);
        expect(list.map((s) => s.label), ['2 albums', '1 album', 'No albums']);
        expect(list.map((s) => s.railLabel), ['2', '1', 'None']);
        expect(list.last.items.map((a) => a.name), ['Abba', 'Cher']);
      });

      test('most songs: the counts, then No songs', () {
        final list = sections(entries, ArtistsSort.mostSongs);
        expect(list.map((s) => s.label), ['3 songs', '1 song', 'No songs']);
        expect(list.last.items.map((a) => a.name), [
          'The Beatles',
          'Zebra',
          'Various Artists',
        ]);
      });

      List<Entry> withCounts(Iterable<int> counts) => [
        for (final n in counts)
          for (var i = 0; i < n; i++) album('Artist $n', 'a$n-$i', day1),
        song('Songs only', 's1', day1),
      ];

      test('counts stay one by one while they fit the rail', () {
        // 23 counts and "No albums": 24 sections.
        final list = sections(
          withCounts([for (var n = 1; n <= 22; n++) n, 60]),
          ArtistsSort.mostAlbums,
        );
        expect(list.length, maxRailLabels);
        expect(list.first.label, '60 albums');
        expect(list[1].label, '22 albums');
        expect(list.last.label, 'No albums');
      });

      test('too many counts: 1 to 10 one by one and ranges above', () {
        final list = sections(
          withCounts([for (var n = 1; n <= 23; n++) n, 31, 50, 51, 60]),
          ArtistsSort.mostAlbums,
        );
        expect(list.map((s) => s.label), [
          'Over 50 albums',
          '31–50 albums',
          '21–30 albums',
          '16–20 albums',
          '11–15 albums',
          for (var n = 10; n >= 2; n--) '$n albums',
          '1 album',
          'No albums',
        ]);
        expect(list.map((s) => s.railLabel).take(5), [
          '50+',
          '31–50',
          '21–30',
          '16–20',
          '11–15',
        ]);
        expect(list.first.items.map((a) => a.name), ['Artist 60', 'Artist 51']);
        expect(list[1].items.length, 2);
        expect(list[2].items.length, 3);
      });
    });
  });
}
