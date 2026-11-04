import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/operations/operations.dart';

void main() {
  final file = File('assets/fixtures/library.json');

  test('decoding then encoding the fixture is byte-identical', () {
    final text = file.readAsStringSync();
    expect(encodeLibrary(decodeLibrary(text)), text);
  });

  test('a rating change touches exactly one line', () {
    final library = decodeLibrary(file.readAsStringSync());
    final before = encodeLibrary(library).split('\n');
    final changed = const SetRating('movies/the-mummy-1999', 7).apply(library);
    final after = encodeLibrary(changed).split('\n');

    expect(after.length, before.length);
    final diffs = [
      for (var i = 0; i < before.length; i++)
        if (before[i] != after[i]) (before[i], after[i]),
    ];
    expect(diffs, [('      "rating": 9,', '      "rating": 7,')]);
  });

  test('linking an entry to a lookup touches exactly one line', () {
    final library = decodeLibrary(file.readAsStringSync());
    final before = encodeLibrary(library).split('\n');
    final entries = [
      for (final entry in library.entries)
        if (entry.id == 'movies/the-mummy-1999')
          entry.copyWith(source: 'tmdb:movie:564')
        else
          entry,
    ];
    final after = encodeLibrary(library.copyWith(entries: entries)).split('\n');

    expect(after.length, before.length);
    final diffs = [
      for (var i = 0; i < before.length; i++)
        if (before[i] != after[i]) (before[i], after[i]),
    ];
    // A movie has no type-specific fields, so source is its last line.
    expect(diffs, [
      ('      "source": null', '      "source": "tmdb:movie:564"'),
    ]);
  });

  test('an anime\'s TMDB show is one line, right after its source', () {
    final library = decodeLibrary(file.readAsStringSync());
    final before = encodeLibrary(library).split('\n');
    final entries = [
      for (final entry in library.entries)
        if (entry.id == 'anime/frieren-beyond-journeys-end-2023')
          entry.copyWith(tmdb: 'tmdb:tv:209867')
        else
          entry,
    ];
    final text = encodeLibrary(library.copyWith(entries: entries));
    final after = text.split('\n');
    expect(after.length, before.length + 1);
    final at = after.indexOf('      "tmdb": "tmdb:tv:209867",');
    expect(after[at - 1], '      "source": null,');
    expect(after[at + 1], '      "kind": "series",');
    // Read back as written.
    expect(
      decodeLibrary(text)
          .entryById('anime/frieren-beyond-journeys-end-2023')!
          .tmdb,
      'tmdb:tv:209867',
    );
  });

  test('a show\'s split is one line, right before its seasons', () {
    final library = decodeLibrary(file.readAsStringSync());
    final before = encodeLibrary(library).split('\n');
    final entries = [
      for (final entry in library.entries)
        if (entry.id == 'anime/frieren-beyond-journeys-end-2023')
          entry.copyWith(seasonsFrom: 'tmdb:group:5f3d826d2da8460031c7c7c0')
        else
          entry,
    ];
    final text = encodeLibrary(library.copyWith(entries: entries));
    final after = text.split('\n');
    expect(after.length, before.length + 1);
    final at = after.indexOf(
      '      "seasons_from": "tmdb:group:5f3d826d2da8460031c7c7c0",',
    );
    expect(after[at - 1], '      "kind": "series",');
    expect(after[at + 1], '      "seasons": [');
    expect(
      decodeLibrary(text)
          .entryById('anime/frieren-beyond-journeys-end-2023')!
          .seasonsFrom,
      'tmdb:group:5f3d826d2da8460031c7c7c0',
    );
  });

  test('tag categories out of order in the file are written in order', () {
    // The app once appended a new category at the end of the map, so a
    // saved file could have Studios after Other; the data repo's
    // library.py rejects that. Decoding sorts the groups and encoding
    // writes them in TagCategory order, Studios right after Directors.
    const text = '''
{
  "version": 2,
  "tags": {
    "Genres": [
      "adventure"
    ],
    "Directors": [
      "mike-flanagan"
    ],
    "Other": [
      "favorite"
    ],
    "Studios": [
      "pixar"
    ]
  },
  "entries": [],
  "plans": []
}
''';
    final library = decodeLibrary(text);
    expect(library.tags.keys.toList(), [
      TagCategory.genre,
      TagCategory.directors,
      TagCategory.studios,
      TagCategory.other,
    ]);
    final lines = encodeLibrary(library).split('\n');
    final groups = [
      for (final line in lines)
        if (line.startsWith('    "'))
          line.trim().replaceAll(RegExp(r'[":\[]'), '').trim(),
    ];
    expect(groups, ['Genres', 'Directors', 'Studios', 'Other']);
    expect(
      encodeLibrary(decodeLibrary(encodeLibrary(library))),
      encodeLibrary(library),
    );
  });

  test('the data repo layout with source after added re-encodes the same', () {
    // The entries in ekmanch/library carry "source": null right after
    // "added"; the app must write that file back byte for byte.
    const text = '''
{
  "version": 2,
  "tags": {
    "Genres": [
      "adventure"
    ]
  },
  "entries": [
    {
      "id": "movies/the-mummy-1999",
      "type": "movies",
      "title": "The Mummy",
      "released": "1999",
      "creator": null,
      "status": "done",
      "rating": null,
      "tags": [
        "adventure"
      ],
      "note": "",
      "description": "",
      "seasonal_only": false,
      "added": "2026-10-01",
      "source": null
    },
    {
      "id": "games/silent-hill-2-2001",
      "type": "games",
      "title": "Silent Hill 2",
      "released": "2001",
      "creator": null,
      "status": "want",
      "rating": null,
      "tags": [],
      "note": "",
      "description": "",
      "seasonal_only": false,
      "added": "2026-10-01",
      "source": null,
      "platform": "PlayStation 2"
    }
  ],
  "plans": []
}
''';
    expect(encodeLibrary(decodeLibrary(text)), text);
  });

  test('clearing a rating keeps the key', () {
    final library = decodeLibrary(file.readAsStringSync());
    final changed = const SetRating(
      'movies/the-mummy-1999',
      null,
    ).apply(library);
    expect(encodeLibrary(changed), contains('"rating": null'));
  });
}
