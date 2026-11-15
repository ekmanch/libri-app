import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/features/library/home_type_provider.dart';
import 'package:library_app/features/library/library_filter.dart';
import 'package:library_app/features/library/library_filter_provider.dart';
import 'package:library_app/features/library/library_search.dart';
import 'package:library_app/features/music/music_tab.dart';

import '../../helpers/pump_app.dart';

void main() {
  final fixture = loadFixture();
  List<String> titles(String q, {MediaType? type}) => [
    for (final e in searchEntries(
      type == null ? fixture.entries : fixture.entriesOfType(type),
      normalizeQuery(q),
    ))
      e.title,
  ];

  test('the query is trimmed, lower-cased and loses a leading hash', () {
    expect(normalizeQuery('  The M '), 'the m');
    expect(normalizeQuery('#Christmas'), 'christmas');
    expect(normalizeQuery('  # '), '');
  });

  test('matches a title, whatever the case', () {
    expect(titles('the mum'), ['The Mummy']);
    expect(titles('THE MUM'), ['The Mummy']);
  });

  test('matches the creator', () {
    expect(
      titles('king'),
      unorderedEquals(['Paddington 2', 'The Shining', 'The Long Walk']),
    );
    expect(titles('king', type: MediaType.books), [
      'The Shining',
      'The Long Walk',
    ]);
  });

  test('an entry whose tag matches is a result', () {
    final tagged = [
      for (final e in fixture.entries)
        if (e.tags.contains('halloween')) e.title,
    ];
    expect(titles('hallow'), containsAll(tagged));
    expect(titles('zzzz'), isEmpty);
  });

  test('matching tags: counted over the list searched, most used first', () {
    final all = matchingTags(fixture, fixture.entries, 'hall');
    expect(all.map((t) => t.name), ['halloween']);
    expect(
      all.single.count,
      fixture.entries.where((e) => e.tags.contains('halloween')).length,
    );
    final movies = fixture.entriesOfType(MediaType.movies);
    expect(
      matchingTags(fixture, movies, 'hall').single.count,
      movies.where((e) => e.tags.contains('halloween')).length,
    );
    // Only anime carries it.
    expect(matchingTags(fixture, movies, 'ghib'), isEmpty);
    final counts = [
      for (final tag in matchingTags(fixture, fixture.entries, 'c')) tag.count,
    ];
    expect(counts, [...counts]..sort((a, b) => b.compareTo(a)));
  });

  test('a tag in several categories is one match per category', () {
    final tags = matchingTags(fixture, fixture.entries, 'clint');
    expect(tags.map((t) => t.label), [
      '#clint-eastwood · Actor',
      '#clint-eastwood · Director',
    ]);
    expect(tags.map((t) => t.count), [2, 1]);
    expect(
      matchingTags(fixture, fixture.entriesOfType(MediaType.shows), 'clint'),
      isEmpty,
    );
  });

  test('match counts per type leave out the types without any', () {
    final counts = matchCounts(fixture.entries, 'king');
    expect(counts, {MediaType.movies: 1, MediaType.books: 2});
  });

  test('music opens on Artists, else Albums, else Songs', () {
    final music = fixture.entriesOfType(MediaType.music);
    expect(musicTabForQuery(music, 'pink'), MusicTab.artists);
    expect(musicTabForQuery(music, 'abbey'), MusicTab.albums);
    expect(musicTabForQuery(music, 'human fly'), MusicTab.songs);
  });

  group('the query', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(librarySearchProvider, (_, _) {});
    });
    String query() => container.read(librarySearchProvider);
    LibrarySearchNotifier search() =>
        container.read(librarySearchProvider.notifier);

    test('is cleared by another type, and by Home', () {
      container.read(homeTypeProvider.notifier).set(MediaType.movies);
      search().set('dune');
      container.read(homeTypeProvider.notifier).set(MediaType.books);
      expect(query(), '');
      search().set('dune');
      container.read(homeTypeProvider.notifier).set(null);
      expect(query(), '');
    });

    test('stays across status chips and music tabs', () {
      container.read(homeTypeProvider.notifier).set(MediaType.music);
      search().set('adele');
      container.read(homeMusicTabProvider.notifier).set(MusicTab.albums);
      container
          .read(homeStatusProvider.notifier)
          .set(MediaType.movies, EntryStatus.done);
      expect(query(), 'adele');
    });

    test('is kept through openType, which resets the status chip', () {
      container
          .read(homeStatusProvider.notifier)
          .set(MediaType.books, EntryStatus.done);
      search().set('dune');
      search().openType(MediaType.books);
      expect(query(), 'dune');
      expect(container.read(homeTypeProvider), MediaType.books);
      expect(container.read(homeStatusProvider)[MediaType.books], isNull);
      // The next change of type is an ordinary one again.
      container.read(homeTypeProvider.notifier).set(MediaType.movies);
      expect(query(), '');

      search().set('pink');
      search().openType(MediaType.music, music: MusicTab.albums);
      expect(query(), 'pink');
      expect(container.read(homeMusicTabProvider), MusicTab.albums);
    });

    test('is cleared when a filter\'s results open or close', () {
      search().set('dune');
      container
          .read(libraryFilterProvider.notifier)
          .set(const LibraryFilter(tags: {'scifi'}));
      expect(query(), '');
      search().set('dune');
      container
          .read(libraryFilterProvider.notifier)
          .set(const LibraryFilter(tags: {'scifi', 'epic'}));
      expect(query(), 'dune');
      container.read(libraryFilterProvider.notifier).clear();
      expect(query(), '');
    });

    test('narrows only the page shown, and no page under a filter', () {
      container.read(homeTypeProvider.notifier).set(MediaType.movies);
      search().set(' Dune ');
      expect(container.read(pageQueryProvider(MediaType.movies)), 'dune');
      expect(container.read(pageQueryProvider(MediaType.books)), '');
      expect(container.read(pageQueryProvider(null)), '');
    });
  });
}
