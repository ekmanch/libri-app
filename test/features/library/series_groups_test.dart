import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/features/entry/series.dart';
import 'package:library_app/features/library/entry_sections.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/library/series_groups.dart';

import '../../helpers/sample_library.dart';

/// A movie in [series] with [number], or in none.
Entry part(
  String id,
  String title, {
  String? series,
  int? number,
  bool? cover,
  int? year,
  EntryStatus status = EntryStatus.want,
  MediaType type = MediaType.movies,
  EntryKind? kind,
  DateTime? added,
}) => mummy.copyWith(
  id: id,
  type: type,
  kind: kind,
  title: title,
  status: status,
  released: year == null ? null : Released(year),
  added: added ?? DateTime(2026, 1, 1),
  series: series == null
      ? null
      : Series(name: series, number: number, cover: cover),
);

final kfp1 = part(
  'movies/kfp1',
  'Kung Fu Panda',
  series: 'Kung Fu Panda',
  number: 1,
  year: 2008,
  status: EntryStatus.done,
  added: DateTime(2026, 1, 3),
);
final kfp2 = part(
  'movies/kfp2',
  'Kung Fu Panda 2',
  series: 'Kung Fu Panda',
  number: 2,
  year: 2011,
  status: EntryStatus.done,
  added: DateTime(2026, 1, 1),
);
final kfp3 = part(
  'movies/kfp3',
  'Kung Fu Panda 3',
  series: 'Kung Fu Panda',
  number: 3,
  year: 2016,
  added: DateTime(2026, 1, 9),
);
final kfp4 = part(
  'movies/kfp4',
  'Kung Fu Panda 4',
  series: 'Kung Fu Panda',
  number: 4,
  year: 2024,
  added: DateTime(2026, 1, 2),
);
final theMummy = part(
  'movies/mummy',
  'The Mummy',
  series: 'The Mummy',
  number: 1,
  year: 1999,
  status: EntryStatus.done,
  added: DateTime(2026, 1, 5),
);
final alien = part(
  'movies/alien',
  'Alien',
  year: 1979,
  added: DateTime(2026, 1, 4),
);

void main() {
  group('groupSeriesRows', () {
    test('two parts or more become one row; one part stays a row', () {
      final rows = groupSeriesRows([kfp1, theMummy, kfp2, alien]);
      expect(rows.length, 3);
      expect(rows[0], isA<SeriesGroup>());
      expect(rows[1], EntryItem(theMummy));
      expect(rows[2], EntryItem(alien));
      final group = rows[0] as SeriesGroup;
      expect(group.name, 'Kung Fu Panda');
      expect(group.parts.map((p) => p.id), [kfp1.id, kfp2.id]);
    });

    test('the row sits where its first-sorting part would', () {
      // Newest added: Kung Fu Panda 3 (Jan 9) was added last, so the series
      // leads the list; title order puts it after Alien.
      final byAdded = sortEntries([
        kfp1,
        kfp2,
        kfp3,
        kfp4,
        theMummy,
        alien,
      ], LibrarySort.newestAdded);
      final rows = groupSeriesRows(byAdded);
      expect(rows.map((r) => r.lead.id), [kfp3.id, theMummy.id, alien.id]);
      expect((rows.first as SeriesGroup).lead, kfp3);

      final byTitle = groupSeriesRows(
        sortEntries([
          kfp1,
          kfp2,
          kfp3,
          kfp4,
          theMummy,
          alien,
        ], LibrarySort.titleAz),
      );
      expect(byTitle.map((r) => r.lead.id), [alien.id, kfp1.id, theMummy.id]);

      final byYearOldest = groupSeriesRows(
        sortEntries([
          kfp1,
          kfp2,
          kfp3,
          kfp4,
          theMummy,
          alien,
        ], LibrarySort.yearOldest),
      );
      expect(byYearOldest.map((r) => r.lead.id), [
        alien.id,
        theMummy.id,
        kfp1.id,
      ]);
    });

    test('parts are in series order whatever the sort', () {
      final rows = groupSeriesRows(
        sortEntries([kfp4, kfp2, kfp3, kfp1], LibrarySort.yearNewest),
      );
      final group = rows.single as SeriesGroup;
      expect(group.lead, kfp4);
      expect(group.parts.map((p) => p.title), [
        'Kung Fu Panda',
        'Kung Fu Panda 2',
        'Kung Fu Panda 3',
        'Kung Fu Panda 4',
      ]);
    });

    test('a part without a number goes last, in list order', () {
      final short = part(
        'movies/kfp-short',
        'Secrets of the Furious Five',
        series: 'Kung Fu Panda',
      );
      final rows = groupSeriesRows([short, kfp2, kfp1]);
      final group = rows.single as SeriesGroup;
      expect(group.parts.map((p) => p.id), [kfp1.id, kfp2.id, short.id]);
    });

    test('a series is told by type and name, like a title', () {
      final book = part(
        'books/kfp',
        'Kung Fu Panda: The Novel',
        type: MediaType.books,
        series: 'kung fu panda',
        number: 1,
      );
      final rows = groupSeriesRows([
        kfp1,
        book,
        kfp2.copyWith(series: const Series(name: 'kung fu panda', number: 2)),
      ]);
      expect(rows.length, 2);
      expect(rows[0], isA<SeriesGroup>());
      expect(rows[1], EntryItem(book));
    });

    test('shows and anime series never group, even with a series set', () {
      final show1 = part(
        'shows/s1',
        'Show 1',
        type: MediaType.shows,
        series: 'Shows',
        number: 1,
      );
      final show2 = part(
        'shows/s2',
        'Show 2',
        type: MediaType.shows,
        series: 'Shows',
        number: 2,
      );
      final anime1 = part(
        'anime/a1',
        'Anime 1',
        type: MediaType.anime,
        kind: EntryKind.series,
        series: 'Anime',
        number: 1,
      );
      final anime2 = part(
        'anime/a2',
        'Anime 2',
        type: MediaType.anime,
        kind: EntryKind.series,
        series: 'Anime',
        number: 2,
      );
      final movie1 = anime1.copyWith(id: 'anime/m1', kind: EntryKind.movie);
      final movie2 = anime2.copyWith(id: 'anime/m2', kind: EntryKind.movie);
      expect(groupSeriesRows([show1, show2]).length, 2);
      expect(groupSeriesRows([anime1, anime2]).length, 2);
      expect(groupSeriesRows([movie1, movie2]).length, 1);
    });

    test('an empty list, and a list with no series, stay as they are', () {
      expect(groupSeriesRows(const []), isEmpty);
      expect(groupSeriesRows([alien, theMummy]), [
        EntryItem(alien),
        EntryItem(theMummy),
      ]);
    });
  });

  group('SeriesGroup', () {
    final group =
        groupSeriesRows([kfp1, kfp2, kfp3, kfp4]).single as SeriesGroup;

    test('counts, years and the done label', () {
      expect(group.count, 4);
      expect(group.countLabel, '4 movies');
      expect(group.yearSpan, '2008–2024');
      expect(group.subtitle, '4 movies · 2008–2024');
      expect(group.doneCount, 2);
      expect(group.doneLabel, '2 of 4 done');
      expect(group.allDone, isFalse);
      expect(group.type, MediaType.movies);
    });

    test('all done, one year, no year, and the nouns per type', () {
      final done =
          groupSeriesRows([kfp1, kfp2.copyWith(released: const Released(2008))])
                  .single
              as SeriesGroup;
      expect(done.allDone, isTrue);
      expect(done.doneLabel, '2 of 2 done');
      expect(done.yearSpan, '2008');
      expect(done.subtitle, '2 movies · 2008');

      final undated =
          groupSeriesRows([
                kfp1.copyWith(released: null),
                kfp2.copyWith(released: null),
              ]).single
              as SeriesGroup;
      expect(undated.yearSpan, isNull);
      expect(undated.subtitle, '2 movies');

      final books =
          groupSeriesRows([
                part(
                  'books/b1',
                  'Berserk, Vol. 1',
                  type: MediaType.books,
                  series: 'Berserk',
                  number: 1,
                ),
                part(
                  'books/b2',
                  'Berserk, Vol. 2',
                  type: MediaType.books,
                  series: 'Berserk',
                  number: 2,
                ),
              ]).single
              as SeriesGroup;
      expect(books.countLabel, '2 volumes');
      final games =
          groupSeriesRows([
                part(
                  'games/g1',
                  'Hades',
                  type: MediaType.games,
                  series: 'Hades',
                  number: 1,
                ),
                part(
                  'games/g2',
                  'Hades II',
                  type: MediaType.games,
                  series: 'Hades',
                  number: 2,
                ),
              ]).single
              as SeriesGroup;
      expect(games.countLabel, '2 games');
    });

    test('the cover is part 1\'s until a part is marked', () {
      expect(group.coverEntry, kfp1);
      final picked =
          groupSeriesRows([
                kfp1,
                kfp2,
                kfp3.copyWith(
                  series: const Series(
                    name: 'Kung Fu Panda',
                    number: 3,
                    cover: true,
                  ),
                ),
              ]).single
              as SeriesGroup;
      expect(picked.coverEntry.id, kfp3.id);
      expect(seriesCoverEntry([kfp2, kfp1]), kfp2);
    });

    test('TMDB\'s "Collection" is dropped from the title', () {
      final lotr =
          groupSeriesRows([
                kfp1.copyWith(
                  series: const Series(
                    name: 'The Lord of the Rings Collection',
                    number: 1,
                  ),
                ),
                kfp2.copyWith(
                  series: const Series(
                    name: 'The Lord of the Rings Collection',
                    number: 2,
                  ),
                ),
              ]).single
              as SeriesGroup;
      expect(lotr.title, 'The Lord of the Rings');
      expect(lotr.name, 'The Lord of the Rings Collection');
      expect(seriesDisplayName('Berserk'), 'Berserk');
      expect(seriesDisplayName('Alien collection'), 'Alien');
      expect(seriesDisplayName('Collection'), 'Collection');
    });
  });

  test('grouping follows the status segment: All, Done and DNF only', () {
    expect(groupsSeriesFor(null), isTrue);
    expect(groupsSeriesFor(EntryStatus.done), isTrue);
    expect(groupsSeriesFor(EntryStatus.dnf), isTrue);
    expect(groupsSeriesFor(EntryStatus.want), isFalse);
    expect(groupsSeriesFor(EntryStatus.inProgress), isFalse);

    expect(groupsSeriesForFilter(const {}), isTrue);
    expect(
      groupsSeriesForFilter(const {EntryStatus.done, EntryStatus.dnf}),
      isTrue,
    );
    expect(groupsSeriesForFilter(const {EntryStatus.want}), isFalse);
    expect(
      groupsSeriesForFilter(const {EntryStatus.done, EntryStatus.inProgress}),
      isFalse,
    );
  });

  test('a long list is three screens or more', () {
    expect(longListScreens, 3);
    expect(isLongList(contentHeight: 2400, viewportHeight: 800), isTrue);
    expect(isLongList(contentHeight: 2399, viewportHeight: 800), isFalse);
  });

  test('sections put a series row where its lead part would be', () {
    final sorted = sortEntries([
      kfp1,
      kfp2,
      kfp3,
      kfp4,
      theMummy,
      alien,
    ], LibrarySort.yearNewest);
    final sections = sectionRows(
      groupSeriesRows(sorted),
      LibrarySort.yearNewest,
    );
    expect(sections.map((s) => s.label), ['2020s', '1990s', '1970s']);
    expect(sections[0].items.single, isA<SeriesGroup>());
    expect((sections[0].items.single as SeriesGroup).lead, kfp4);
    expect(sections[1].items.single, EntryItem(theMummy));
    expect(sections[2].items.single, EntryItem(alien));
  });
}
