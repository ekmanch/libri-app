import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/tag_category.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

/// A tag in more than one category (Add / edit entry › Tag in two
/// categories): the tag list keeps one list per category, so a person or a
/// genre in several of its kind is listed in each; an entry says which it
/// has in `tag_categories`.
void main() {
  final fixture = loadFixture();

  group('the tag list', () {
    test('a tag listed under two categories has both, in category order', () {
      expect(fixture.categoriesOf('clint-eastwood'), [
        TagCategory.directors,
        TagCategory.actors,
      ]);
      expect(fixture.isMultiCategory('clint-eastwood'), isTrue);
      expect(fixture.categoriesOf('horror'), [TagCategory.genre]);
      expect(fixture.isMultiCategory('horror'), isFalse);
      expect(fixture.categoriesOf('nope'), isEmpty);
    });

    test(
      'a file from before, with every tag in one category, is unchanged',
      () {
        // Nothing to migrate: the map already held one list per category, and
        // an entry without tag_categories reads as before.
        const text = '''
{
  "version": 2,
  "tags": {
    "Genres": [
      "horror"
    ],
    "Directors": [
      "clint-eastwood"
    ]
  },
  "entries": [
    {
      "id": "movies/x-2000",
      "type": "movies",
      "title": "X",
      "released": "2000",
      "creator": null,
      "status": "want",
      "rating": null,
      "tags": [
        "horror",
        "clint-eastwood"
      ],
      "note": "",
      "description": "",
      "seasonal_only": false,
      "added": "2026-10-21",
      "source": null
    }
  ],
  "plans": []
}
''';
        final library = decodeLibrary(text);
        expect(encodeLibrary(library), text);
        final entry = library.entries.single;
        expect(entry.tagCategories, isNull);
        expect(library.categoriesOn(entry, 'clint-eastwood'), [
          TagCategory.directors,
        ]);
        expect(entry.hasTagAs('clint-eastwood', TagCategory.directors), isTrue);
        expect(entry.hasTagAs('clint-eastwood', TagCategory.actors), isTrue);
      },
    );

    test('people and genres are the kinds that share categories', () {
      expect(TagCategory.directors.kind, TagKind.people);
      expect(TagCategory.gameGenre.kind, TagKind.genres);
      expect(TagCategory.mood.kind, isNull);
      expect(TagCategory.directors.sharesKindWith(TagCategory.actors), isTrue);
      expect(TagCategory.directors.sharesKindWith(TagCategory.genre), isFalse);
      expect(
        TagCategory.directors.sharesKindWith(TagCategory.directors),
        isFalse,
      );
      expect(TagCategory.actors.family, [
        TagCategory.authors,
        TagCategory.directors,
        TagCategory.actors,
      ]);
      expect(TagCategory.musicGenre.family, [
        TagCategory.genre,
        TagCategory.gameGenre,
        TagCategory.musicGenre,
      ]);
      expect(TagCategory.season.family, [TagCategory.season]);
    });
  });

  group('tag_categories on an entry', () {
    test('is written after tags, in category order, and round-trips', () {
      final text = encodeLibrary(fixture);
      expect(
        text,
        contains(
          '      "tags": [\n'
          '        "drama",\n'
          '        "clint-eastwood",\n'
          '        "hilary-swank",\n'
          '        "morgan-freeman"\n'
          '      ],\n'
          '      "tag_categories": {\n'
          '        "clint-eastwood": [\n'
          '          "Directors",\n'
          '          "Actors"\n'
          '        ]\n'
          '      },\n'
          '      "note": "Rewatch with the commentary on.",',
        ),
      );
      final baby = decodeLibrary(text)
          .entryById('movies/million-dollar-baby-2004')!;
      expect(baby.tagCategories, {
        'clint-eastwood': [TagCategory.directors, TagCategory.actors],
      });
      final western = fixture.entryById(
        'movies/the-good-the-bad-and-the-ugly-1966',
      )!;
      expect(western.tagCategories, {
        'clint-eastwood': [TagCategory.actors],
      });
      // An entry with no such tag has no key at all.
      expect(text, isNot(contains('"tag_categories": null')));
      expect(fixture.entryById('movies/the-mummy-1999')!.tagCategories, isNull);
    });

    test('says which categories the tag has here', () {
      final western = fixture.entryById(
        'movies/the-good-the-bad-and-the-ugly-1966',
      )!;
      expect(fixture.categoriesOn(western, 'clint-eastwood'), [
        TagCategory.actors,
      ]);
      expect(western.hasTagAs('clint-eastwood', TagCategory.actors), isTrue);
      expect(
        western.hasTagAs('clint-eastwood', TagCategory.directors),
        isFalse,
      );
      expect(western.hasTagAs('adventure', TagCategory.genre), isTrue);
      expect(western.hasTagAs('horror', TagCategory.genre), isFalse);
      expect(fixture.countTagAs('clint-eastwood', TagCategory.actors), 2);
      expect(fixture.countTagAs('clint-eastwood', TagCategory.directors), 1);
    });

    test('a tag in several categories with no pick counts in all of them', () {
      final library = sampleLibrary().copyWith(
        tags: {
          TagCategory.directors: ['clint-eastwood'],
          TagCategory.actors: ['clint-eastwood'],
        },
        entries: [
          mummy.copyWith(tags: ['clint-eastwood']),
        ],
      );
      final entry = library.entries.single;
      expect(library.categoriesOn(entry, 'clint-eastwood'), [
        TagCategory.directors,
        TagCategory.actors,
      ]);
      expect(entry.hasTagAs('clint-eastwood', TagCategory.actors), isTrue);
      // A pick is read against the tag's categories, in their order.
      final picked = entry.copyWith(
        tagCategories: {
          'clint-eastwood': [TagCategory.actors],
        },
      );
      expect(library.categoriesOn(picked, 'clint-eastwood'), [
        TagCategory.actors,
      ]);
      expect(picked.categoriesOf('clint-eastwood', [TagCategory.directors]), [
        TagCategory.directors,
      ], reason: 'a tag in one category ignores a stale pick');
    });
  });

  test('Entry.categoriesOf keeps a pick in category order', () {
    final entry = mummy.copyWith(
      tags: ['x'],
      tagCategories: {
        'x': [TagCategory.actors, TagCategory.authors],
      },
    );
    expect(entry.categoriesOf('x', TagCategory.actors.family), [
      TagCategory.authors,
      TagCategory.actors,
    ]);
    expect(
      entry.categoriesOf('x', [TagCategory.directors, TagCategory.actors]),
      [TagCategory.actors],
    );
    expect(Entry.fromJson(entry.toJson()), entry);
  });
}
