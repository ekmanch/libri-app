import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/features/library/library_search.dart';

import '../../helpers/pump_app.dart';

void main() {
  final fixture = loadFixture();

  test('empty query gives nothing', () {
    expect(searchLibrary(fixture, '').isEmpty, isTrue);
    expect(searchLibrary(fixture, '  #').isEmpty, isTrue);
  });

  test('matches titles case-insensitively, sorted by title', () {
    final results = searchLibrary(fixture, 'the m');
    final titles = results.titles.map((e) => e.title).toList();
    expect(titles, contains('The Mummy'));
    expect(
      titles,
      equals(
        [...titles]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      ),
    );
  });

  test(
    'matches tags with counts, most used first, and lists their entries',
    () {
      final results = searchLibrary(fixture, 'hall');
      expect(results.tags.map((t) => t.name), ['halloween']);
      final count = fixture.entries
          .where((e) => e.tags.contains('halloween'))
          .length;
      expect(results.tags.single.count, count);
      expect(results.tagged['halloween']!.length, count);
    },
  );

  test('ignores a leading hash and includes seasonal-only entries', () {
    final results = searchLibrary(fixture, '#christmas');
    expect(results.tags.map((t) => t.name), ['christmas']);
    expect(results.tagged['christmas']!.any((e) => e.seasonalOnly), isTrue);
  });

  test('a tag in several categories is one match per category', () {
    final results = searchLibrary(fixture, 'clint');
    expect(results.tags.map((t) => t.label), [
      '#clint-eastwood · Actor',
      '#clint-eastwood · Director',
    ]);
    expect(results.tags.map((t) => t.count), [2, 1]);
    expect(results.tagged['clint-eastwood/directors']!.map((e) => e.title), [
      'Million Dollar Baby',
    ]);
    expect(results.tagged['clint-eastwood/actors']!.length, 2);
    // Scoped to shows, neither role has an entry, so the tag is left out.
    expect(
      searchLibrary(fixture, 'clint', type: MediaType.shows).tags,
      isEmpty,
    );
  });

  test('reports no results for nonsense', () {
    expect(searchLibrary(fixture, 'zzzz').isEmpty, isTrue);
  });

  test('scoped to a type: only its titles, tags and tagged entries', () {
    final results = searchLibrary(fixture, 'hall', type: MediaType.movies);
    final movies = fixture
        .entriesOfType(MediaType.movies)
        .where((e) => e.tags.contains('halloween'))
        .length;
    expect(results.tags.single.count, movies);
    expect(
      results.tagged['halloween']!.every((e) => e.type == MediaType.movies),
      isTrue,
    );
    expect(
      searchLibrary(fixture, 'ghib', type: MediaType.movies).isEmpty,
      isTrue,
    );
    expect(
      searchLibrary(
        fixture,
        'the m',
        type: MediaType.books,
      ).titles.every((e) => e.type == MediaType.books),
      isTrue,
    );
  });
}
