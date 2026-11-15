import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/features/library/entry_sections.dart';
import 'package:library_app/features/library/library_sort.dart';

import '../../helpers/sample_library.dart';

void main() {
  final today = DateTime(2026, 10, 10);

  test('year orders group by decade, Older first or last, undated last', () {
    final entries = sortEntries([
      mummy.copyWith(title: 'a', released: const Released(1999)),
      mummy.copyWith(title: 'b', released: const Released(2025)),
      mummy.copyWith(title: 'c', released: null),
      mummy.copyWith(title: 'd', released: const Released(1931)),
      mummy.copyWith(title: 'e', released: const Released(1991)),
      mummy.copyWith(title: 'f', released: const Released(2027, 3)),
    ], LibrarySort.yearNewest);
    final sections = sectionEntries(entries, LibrarySort.yearNewest);
    expect(sections.map((s) => s.label), [
      '2020s',
      '1990s',
      'Older',
      'Not released yet',
    ]);
    expect(sections.map((s) => s.railLabel), ['20s', '90s', 'Older', 'TBA']);
    expect(sections[1].entries.map((e) => e.title), ['a', 'e']);
    expect(sections[0].bubbleLabel, '2020s');

    final oldest = sectionEntries(
      sortEntries(entries, LibrarySort.yearOldest),
      LibrarySort.yearOldest,
    );
    expect(oldest.map((s) => s.label), [
      'Older',
      '1990s',
      '2020s',
      'Not released yet',
    ]);
  });

  test('newest added groups by month this year, then by year', () {
    final entries = sortEntries([
      mummy.copyWith(title: 'a', added: DateTime(2026, 10, 3)),
      mummy.copyWith(title: 'b', added: DateTime(2026, 10, 1)),
      mummy.copyWith(title: 'c', added: DateTime(2026, 3, 9)),
      mummy.copyWith(title: 'd', added: DateTime(2025, 12, 31)),
      mummy.copyWith(title: 'e', added: DateTime(2025, 1, 1)),
      mummy.copyWith(title: 'f', added: DateTime(2024, 6, 1)),
    ], LibrarySort.newestAdded);
    final sections = sectionEntries(
      entries,
      LibrarySort.newestAdded,
      today: today,
    );
    expect(sections.map((s) => s.label), [
      'October 2026',
      'March 2026',
      '2025',
      '2024',
    ]);
    expect(sections.map((s) => s.railLabel), ['Oct', 'Mar', '2025', '2024']);
    expect(sections.map((s) => s.bubbleLabel), [
      'Oct 2026',
      'Mar 2026',
      '2025',
      '2024',
    ]);
    expect(sections[0].entries.length, 2);
    expect(sections[2].entries.length, 2);
  });

  test('newest added: more years than the rail holds merge into Older', () {
    final entries = sortEntries([
      mummy.copyWith(title: 'now', added: DateTime(today.year, 2, 1)),
      for (var back = 1; back <= 30; back++)
        mummy.copyWith(title: 'y$back', added: DateTime(today.year - back)),
    ], LibrarySort.newestAdded);
    final sections = sectionEntries(
      entries,
      LibrarySort.newestAdded,
      today: today,
    );
    expect(sections.length, maxRailLabels);
    expect(sections[1].label, '${today.year - 1}');
    expect(sections[maxRailLabels - 2].label, '${today.year - 22}');
    expect(sections.last.label, 'Older');
    expect(sections.last.railLabel, 'Older');
    expect(sections.last.entries.length, 8);
    // One year fewer fits, and nothing merges.
    expect(
      sectionEntries(
        entries.take(24).toList(),
        LibrarySort.newestAdded,
        today: today,
      ).last.label,
      '${today.year - 23}',
    );
  });

  test('title order groups by first letter, digits and symbols under #', () {
    final entries = sortEntries([
      mummy.copyWith(title: 'Amélie'),
      mummy.copyWith(title: 'Élan'),
      mummy.copyWith(title: '28 Days Later'),
      mummy.copyWith(title: 'alien'),
      mummy.copyWith(title: '#1'),
    ], LibrarySort.titleAz);
    final sections = sectionEntries(entries, LibrarySort.titleAz);
    expect(sections.map((s) => s.label), ['#', 'A', 'E']);
    expect(sections[0].entries.length, 2);
    expect(sections[1].entries.length, 2);
  });

  test('artist order: leading "The" ignored, Various Artists last, by year '
      'within an artist, sections by the artist\'s letter', () {
    Entry album(String artist, String title, int? year) => dirt.copyWith(
      id: 'music/$title',
      title: title,
      creator: artist,
      released: year == null ? null : Released(year),
      tracks: null,
    );
    final entries = sortEntries([
      album('Various Artists', 'Aaa', 1990),
      album('Zebra', 'Early', 1980),
      album('The Beatles', 'Revolver', 1966),
      album('the beatles', 'Help!', 1965),
      album('The Beatles', 'Undated', null),
      album('', 'Nameless', 2000),
      album('Björk', 'Post', 1995),
      album('Björk', 'Debut', 1993),
      album('2Pac', 'Me Against the World', 1995),
    ], LibrarySort.artistAz);
    expect(entries.map((e) => e.title), [
      'Me Against the World',
      'Help!',
      'Revolver',
      'Undated',
      'Debut',
      'Post',
      'Nameless',
      'Early',
      'Aaa',
    ]);
    final sections = sectionEntries(entries, LibrarySort.artistAz);
    expect(sections.map((s) => s.label), [
      '#',
      'B',
      'U',
      'Z',
      'Various Artists',
    ]);
    expect(sections.last.railLabel, 'VA');
    expect(sections[1].entries.length, 5);
  });

  test('Artist, A to Z is the music tabs\' alone', () {
    expect(LibrarySort.general, isNot(contains(LibrarySort.artistAz)));
    expect(LibrarySort.values.map((s) => s.label), [
      'Newest added',
      'Title, A to Z',
      'Artist, A to Z',
      'Year, newest first',
      'Year, oldest first',
      'Rating, highest first',
    ]);
  });

  test('rating order: 10 down to 1, unrated last, ties by title', () {
    final entries = sortEntries([
      mummy.copyWith(title: 'b', rating: 8),
      mummy.copyWith(title: 'c', rating: null),
      mummy.copyWith(title: 'a', rating: 8),
      mummy.copyWith(title: 'd', rating: 10),
      mummy.copyWith(title: 'f', rating: null),
      mummy.copyWith(title: 'e', rating: 1),
    ], LibrarySort.ratingHighest);
    expect(entries.map((e) => e.title), ['d', 'a', 'b', 'e', 'c', 'f']);

    final sections = sectionEntries(entries, LibrarySort.ratingHighest);
    expect(sections.map((s) => s.label), [
      '10 / 10',
      '8 / 10',
      '1 / 10',
      'Unrated',
    ]);
    expect(sections.map((s) => s.railLabel), ['10', '8', '1', 'None']);
    expect(sections.map((s) => s.bubbleLabel), [
      '10 / 10',
      '8 / 10',
      '1 / 10',
      'Unrated',
    ]);
    expect(sections[1].entries.map((e) => e.title), ['a', 'b']);
  });

  test('the rail needs three screens and two sections', () {
    expect(
      showJumpRail(sectionCount: 2, contentHeight: 3000, viewportHeight: 1000),
      isTrue,
    );
    expect(
      showJumpRail(sectionCount: 1, contentHeight: 3000, viewportHeight: 1000),
      isFalse,
    );
    expect(
      showJumpRail(sectionCount: 5, contentHeight: 2999, viewportHeight: 1000),
      isFalse,
    );
  });
}
