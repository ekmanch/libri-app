import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/features/entry/tag_dialogs.dart';

import '../../helpers/sample_library.dart';

void main() {
  /// Clint Eastwood under Directors and Actors: a director on the first
  /// movie, an actor on both, and a third entry with no pick (as a file
  /// edited by hand might have), which counts in both.
  Library eastwood() => sampleLibrary().copyWith(
    tags: {
      TagCategory.genre: ['drama'],
      TagCategory.directors: ['clint-eastwood'],
      TagCategory.actors: ['clint-eastwood', 'hilary-swank'],
    },
    entries: [
      mummy.copyWith(
        id: 'movies/million-dollar-baby-2004',
        tags: ['drama', 'clint-eastwood', 'hilary-swank'],
        tagCategories: {
          'clint-eastwood': [TagCategory.directors, TagCategory.actors],
        },
      ),
      mummy.copyWith(
        id: 'movies/the-good-the-bad-and-the-ugly-1966',
        tags: ['clint-eastwood'],
        tagCategories: {
          'clint-eastwood': [TagCategory.actors],
        },
      ),
      mummy.copyWith(id: 'movies/unforgiven-1992', tags: ['clint-eastwood']),
    ],
    plans: [],
  );

  group('AddTag', () {
    test('adds a tag under several categories of one kind', () {
      final added = const AddTag('sergio-leone', [
        TagCategory.actors,
        TagCategory.directors,
      ]).apply(eastwood());
      expect(added.categoriesOf('sergio-leone'), [
        TagCategory.directors,
        TagCategory.actors,
      ]);
      expect(added.tags[TagCategory.directors], [
        'clint-eastwood',
        'sergio-leone',
      ]);
      expect(
        const AddTag('sergio-leone', [TagCategory.actors]).summary(added),
        'Add the tag #sergio-leone',
      );
    });

    test('reads the one category a queue from before held', () {
      final old = AddTag.fromJson({'name': 'rpg', 'category': 'Game genres'});
      expect(old.categories, [TagCategory.gameGenre]);
      expect(AddTag.fromJson(old.toJson()).categories, old.categories);
      expect(old.toJson().containsKey('category'), isFalse);
    });

    test('an existing tag, or no category, changes nothing', () {
      final library = eastwood();
      expect(
        const AddTag('clint-eastwood', [TagCategory.authors]).apply(library),
        library,
      );
      expect(const AddTag('new', []).apply(library), library);
    });
  });

  group('SetTagCategories', () {
    test('adding a category lists the tag there and pins every entry', () {
      final library = eastwood().copyWith(
        tags: {
          TagCategory.genre: ['drama'],
          TagCategory.directors: ['clint-eastwood'],
          TagCategory.actors: ['hilary-swank'],
        },
        entries: [
          for (final e in eastwood().entries) e.copyWith(tagCategories: null),
        ],
      );
      final result = const SetTagCategories('clint-eastwood', [
        TagCategory.directors,
        TagCategory.actors,
      ]).apply(library);
      expect(result.tags[TagCategory.actors], [
        'hilary-swank',
        'clint-eastwood',
      ]);
      // Every entry keeps the one category it had, now written down.
      for (final entry in result.entries) {
        expect(entry.tagCategories, {
          'clint-eastwood': [TagCategory.directors],
        }, reason: entry.id);
      }
    });

    test('taking a category away drops the tag where it was the only one', () {
      final result = const SetTagCategories('clint-eastwood', [
        TagCategory.directors,
      ]).apply(eastwood());
      expect(result.tags[TagCategory.actors], ['hilary-swank']);
      expect(result.categoriesOf('clint-eastwood'), [TagCategory.directors]);
      final [baby, western, unforgiven] = result.entries;
      // Back to one category: no pick is written.
      expect(baby.tags, ['drama', 'clint-eastwood', 'hilary-swank']);
      expect(baby.tagCategories, isNull);
      // Only an actor there: the tag goes.
      expect(western.tags, isEmpty);
      expect(western.tagCategories, isNull);
      // No pick meant both, so it stays as the director.
      expect(unforgiven.tags, ['clint-eastwood']);
      expect(unforgiven.tagCategories, isNull);
    });

    test('a tag that loses every entry is pruned', () {
      final library = eastwood().copyWith(entries: [eastwood().entries[1]]);
      final result = const SetTagCategories('clint-eastwood', [
        TagCategory.directors,
      ]).apply(library);
      expect(result.allTags.contains('clint-eastwood'), isFalse);
      expect(result.tags.containsKey(TagCategory.directors), isFalse);
    });

    test('keeps the categories an entry had among the new ones', () {
      final result = const SetTagCategories('clint-eastwood', [
        TagCategory.authors,
        TagCategory.actors,
      ]).apply(eastwood());
      expect(result.categoriesOf('clint-eastwood'), [
        TagCategory.authors,
        TagCategory.actors,
      ]);
      final [baby, western, unforgiven] = result.entries;
      expect(baby.tagCategories!['clint-eastwood'], [TagCategory.actors]);
      expect(western.tagCategories!['clint-eastwood'], [TagCategory.actors]);
      expect(unforgiven.tagCategories!['clint-eastwood'], [TagCategory.actors]);
    });

    test(
      'an unknown tag, no category or the same categories change nothing',
      () {
        final library = eastwood();
        expect(
          const SetTagCategories('nope', [TagCategory.actors]).apply(library),
          library,
        );
        expect(
          const SetTagCategories('clint-eastwood', []).apply(library),
          library,
        );
        expect(
          const SetTagCategories('clint-eastwood', [
            TagCategory.actors,
            TagCategory.directors,
          ]).apply(library),
          library,
        );
        expect(
          const SetTagCategories('clint-eastwood', [
            TagCategory.actors,
          ]).summary(library),
          'Put the tag #clint-eastwood under Actors',
        );
      },
    );
  });

  group('saving an entry tidies its picks', () {
    test('a pick for a tag in one category is dropped; none means all', () {
      final library = eastwood();
      final saved = UpdateEntry(
        library.entries.first.copyWith(
          tagCategories: {
            'drama': [TagCategory.genre],
            'clint-eastwood': [TagCategory.actors],
          },
        ),
      ).apply(library);
      expect(saved.entries.first.tagCategories, {
        'clint-eastwood': [TagCategory.actors],
      });
      final added = AddEntry(
        mummy.copyWith(id: 'movies/new', tags: ['clint-eastwood']),
      ).apply(library);
      expect(added.entries.last.tagCategories, {
        'clint-eastwood': [TagCategory.directors, TagCategory.actors],
      });
      final plain = UpdateEntry(
        library.entries.first.copyWith(
          tags: ['drama'],
          tagCategories: {
            'clint-eastwood': [TagCategory.actors],
          },
        ),
      ).apply(library);
      expect(plain.entries.first.tagCategories, isNull);
    });
  });

  test('tagUsageLabel counts the roles, largest first', () {
    expect(
      tagUsageLabel('clint-eastwood', eastwood()),
      'Used on 3 entries: as an actor on 3, as a director on 2.',
    );
    expect(tagUsageLabel('drama', eastwood()), 'Used on 1 entry.');
    expect(tagUsageLabel('hilary-swank', eastwood()), 'Used on 1 entry.');
  });
}
