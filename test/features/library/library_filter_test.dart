import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/features/library/library_filter.dart';
import 'package:library_app/features/library/library_sort.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

void main() {
  final fixture = loadFixture();

  group('Decade', () {
    test('buckets years, with everything before 1960 as Older', () {
      expect(Decade.of(null), isNull);
      expect(Decade.of(1959), const Decade.older());
      expect(Decade.of(1960), const Decade(1960));
      expect(Decade.of(1999), const Decade(1990));
      expect(Decade.of(2027), const Decade(2020));
      expect(const Decade(1980).label, '1980s');
      expect(const Decade.older().label, 'Older');
    });

    test('options span the library, gaps filled, Older only when needed', () {
      expect(Decade.optionsFor([1965, 1999, null, 2027]).map((d) => d.label), [
        '1960s',
        '1970s',
        '1980s',
        '1990s',
        '2000s',
        '2010s',
        '2020s',
      ]);
      expect(Decade.optionsFor([1954, 2031]).map((d) => d.label), [
        'Older',
        '2030s',
      ]);
      expect(Decade.optionsFor([1950, 1955]).map((d) => d.label), ['Older']);
      expect(Decade.optionsFor([null]), isEmpty);
      expect(Decade.optionsFor(const []), isEmpty);
    });
  });

  group('LibraryFilter', () {
    test('empty filter only hides seasonal-only entries', () {
      const filter = LibraryFilter.none;
      expect(filter.isEmpty, isTrue);
      expect(filter.count, 0);
      final shown = filter.apply(fixture.entries);
      expect(shown.any((e) => e.seasonalOnly), isFalse);
      expect(
        shown.length,
        fixture.entries.where((e) => !e.seasonalOnly).length,
      );
      final withSeasonal = const LibraryFilter(includeSeasonalOnly: true)
          .apply(fixture.entries);
      expect(withSeasonal.length, fixture.entries.length);
    });

    test('any choice matches within type, status and released', () {
      final filter = LibraryFilter(
        types: const {MediaType.movies, MediaType.shows},
        statuses: const {EntryStatus.want},
        decades: {const Decade(2010), const Decade(2020)},
      );
      final shown = filter.apply(fixture.entries);
      expect(shown, isNotEmpty);
      for (final e in shown) {
        expect([MediaType.movies, MediaType.shows], contains(e.type));
        expect(e.status, EntryStatus.want);
        expect(e.year, greaterThanOrEqualTo(2010));
      }
      expect(filter.count, 5);
    });

    test('every chosen tag must be present', () {
      final one = const LibraryFilter(tags: {'horror'}).apply(fixture.entries);
      final both = const LibraryFilter(tags: {'horror', 'halloween'})
          .apply(fixture.entries);
      expect(both.length, lessThan(one.length));
      expect(both.every((e) => e.tags.contains('halloween')), isTrue);
      expect(both.every((e) => e.tags.contains('horror')), isTrue);
    });

    test('entries without a year never match a decade', () {
      final undated = mummy.copyWith(released: null);
      expect(
        LibraryFilter(decades: {const Decade.older()}).matches(undated),
        isFalse,
      );
      expect(LibraryFilter.none.matches(undated), isTrue);
    });

    test('toggles and chips', () {
      var filter = LibraryFilter.none
          .toggleType(MediaType.books)
          .toggleTag('cozy');
      filter = filter
          .toggleStatus(EntryStatus.done)
          .copyWith(includeSeasonalOnly: true);
      expect(filter.chips.map((c) => c.label), [
        'Books',
        'Done',
        '#cozy',
        'Seasonal-only included',
      ]);
      filter = filter.chips[0].remove(filter);
      expect(filter.types, isEmpty);
      filter = filter.chips.last.remove(filter);
      expect(filter.includeSeasonalOnly, isFalse);
      expect(filter.toggleTag('cozy').tags, isEmpty);
      expect(LibraryFilter.none == const LibraryFilter(), isTrue);
    });
  });

  group('status options', () {
    test('follow the chosen types', () {
      expect(LibraryFilter.none.statusOptions, EntryStatus.values);
      expect(const LibraryFilter(types: {MediaType.movies}).statusOptions, [
        EntryStatus.want,
        EntryStatus.done,
        EntryStatus.dnf,
      ]);
      expect(const LibraryFilter(types: {MediaType.music}).statusOptions, [
        EntryStatus.want,
        EntryStatus.done,
      ]);
      expect(
        const LibraryFilter(types: {MediaType.music, MediaType.books})
            .statusOptions,
        EntryStatus.values,
      );
    });

    test('a type toggle drops statuses the types cannot have', () {
      const filter = LibraryFilter(
        types: {MediaType.books},
        statuses: {EntryStatus.inProgress, EntryStatus.dnf, EntryStatus.done},
      );
      final movies = filter
          .toggleType(MediaType.movies)
          .toggleType(MediaType.books);
      expect(movies.statuses, {EntryStatus.dnf, EntryStatus.done});
      expect(movies.toggleType(MediaType.movies).statuses, movies.statuses);
      final music = movies.toggleType(MediaType.music);
      expect(music.statuses, {EntryStatus.dnf, EntryStatus.done});
      expect(music.toggleType(MediaType.movies).statuses, {EntryStatus.done});
    });
  });

  group('kind', () {
    final song = dirt.copyWith(id: 'music/song', kind: EntryKind.song);

    test('narrows music only', () {
      const songs = LibraryFilter(kinds: {EntryKind.song});
      expect(songs.matches(song), isTrue);
      expect(songs.matches(dirt), isFalse); // An album.
      expect(songs.matches(mummy), isTrue); // Not music.
    });

    test('is dropped with Music, and counts as a chip', () {
      final filter = LibraryFilter.none
          .toggleType(MediaType.music)
          .toggleKind(EntryKind.album);
      expect(filter.count, 2);
      expect(filter.chips.map((c) => c.label), ['Music', 'Albums']);
      expect(filter.toggleType(MediaType.music).kinds, isEmpty);
      expect(filter.toggleType(MediaType.movies).kinds, {EntryKind.album});
    });

    test('one kind is a music tab; a status or both kinds are results', () {
      const music = LibraryFilter(types: {MediaType.music});
      expect(music.typeView, (type: MediaType.music, status: null, kind: null));
      expect(
        music.copyWith(kinds: {EntryKind.song}).typeView?.kind,
        EntryKind.song,
      );
      expect(
        music.copyWith(kinds: {EntryKind.song, EntryKind.album}).typeView,
        isNull,
      );
      expect(music.copyWith(statuses: {EntryStatus.done}).typeView, isNull);
    });
  });

  group('tag groups', () {
    List<TagCategory> groups(LibraryFilter f) => [
      for (final (category, _) in f.tagGroupsIn(fixture)) category,
    ];

    test('follow the tags the chosen types use', () {
      // Every group the library has (the fixture has no authors or
      // directors), in category order.
      expect(groups(LibraryFilter.none), [
        for (final c in TagCategory.values)
          if (fixture.tags.containsKey(c)) c,
      ]);
      expect(groups(LibraryFilter.none), contains(TagCategory.studios));
      final music = groups(const LibraryFilter(types: {MediaType.music}));
      expect(music, contains(TagCategory.musicGenre));
      expect(music, isNot(contains(TagCategory.genre)));
      expect(music, isNot(contains(TagCategory.gameGenre)));
      // A game tagged #crime brings Genres along for Games.
      final games = groups(const LibraryFilter(types: {MediaType.games}));
      expect(games, containsAll([TagCategory.genre, TagCategory.gameGenre]));
      expect(games, isNot(contains(TagCategory.musicGenre)));
    });

    test('a chosen tag whose group goes away is dropped', () {
      const filter = LibraryFilter(tags: {'horror', 'jazz'});
      final music = filter.toggleType(MediaType.music).keepTagsShownIn(fixture);
      expect(music.tags, {'jazz'});
    });

    test('a new tag starts in the genre category of its type', () {
      expect(TagCategory.defaultFor(MediaType.games), TagCategory.gameGenre);
      expect(TagCategory.defaultFor(MediaType.music), TagCategory.musicGenre);
      expect(TagCategory.defaultFor(MediaType.anime), TagCategory.genre);
    });
  });

  group('sortEntries', () {
    test('newest added first, then by title', () {
      final sorted = sortEntries(fixture.entries, LibrarySort.newestAdded);
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i - 1].added.isBefore(sorted[i].added), isFalse);
      }
    });

    test('newest added: same-day ties keep library order, latest first', () {
      final day = DateTime(2026, 10, 16);
      final sorted = sortEntries([
        mummy.copyWith(id: 'older', title: 'Akira', added: day),
        mummy.copyWith(id: 'other', title: 'Bleach', added: day),
        mummy.copyWith(id: 'newest', title: 'Zeta', added: day),
      ], LibrarySort.newestAdded);
      expect(sorted.map((e) => e.id), ['newest', 'other', 'older']);
    });

    test('title A to Z ignores case', () {
      final sorted = sortEntries([
        mummy.copyWith(title: 'b'),
        mummy.copyWith(title: 'A'),
        mummy.copyWith(title: 'c'),
      ], LibrarySort.titleAz);
      expect(sorted.map((e) => e.title), ['A', 'b', 'c']);
    });

    test('year orders put undated entries last', () {
      final entries = [
        mummy.copyWith(title: 'none', released: null),
        mummy.copyWith(title: 'old', released: const Released(1980)),
        mummy.copyWith(title: 'new', released: const Released(2020)),
      ];
      expect(sortEntries(entries, LibrarySort.yearNewest).map((e) => e.title), [
        'new',
        'old',
        'none',
      ]);
      expect(sortEntries(entries, LibrarySort.yearOldest).map((e) => e.title), [
        'old',
        'new',
        'none',
      ]);
    });
  });

  test('homeOrder: in progress, want, done, dnf; newest added first', () {
    final ordered = homeOrder(fixture.entriesOfType(MediaType.books));
    final statuses = ordered.map((e) => e.status).toList();
    int rank(EntryStatus s) => const {
      EntryStatus.inProgress: 0,
      EntryStatus.want: 1,
      EntryStatus.done: 2,
      EntryStatus.dnf: 3,
    }[s]!;
    for (var i = 1; i < statuses.length; i++) {
      expect(rank(statuses[i - 1]) <= rank(statuses[i]), isTrue);
      if (statuses[i - 1] == statuses[i]) {
        expect(ordered[i - 1].added.isBefore(ordered[i].added), isFalse);
      }
    }
    expect(statuses.first, EntryStatus.inProgress);
  });
}
