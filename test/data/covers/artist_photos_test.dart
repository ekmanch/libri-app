import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/artist_photos.dart';

/// The desktop's cases (`assets/fixtures/artist_photos.json` in
/// `ekmanch/libri-kde`), run as they are: the two apps must never differ.
/// The desktop's file is the source and `test/fixtures/` holds a copy.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/artist_photos.json').readAsStringSync(),
  ) as Map<String, Object?>;
  List<Map<String, Object?>> cases(String rule) =>
      (fixture[rule]! as List).cast<Map<String, Object?>>();
  List<String> strings(Object? list) => (list! as List).cast<String>();
  List<MissingEdit> edits(Object? list) => [
    for (final edit in list! as List) MissingEdit.fromJson(edit)!,
  ];

  test('the copy is the desktop\'s, byte for byte, when its repo is here', () {
    final desktop = File('../libri-kde/assets/fixtures/artist_photos.json');
    if (!desktop.existsSync()) return;
    expect(
      File('test/fixtures/artist_photos.json').readAsBytesSync(),
      desktop.readAsBytesSync(),
    );
  });

  test('name_key', () {
    for (final c in cases('name_key')) {
      expect(artistNameKey(c['name']! as String), c['key'], reason: '$c');
    }
  });

  test('same_name', () {
    for (final c in cases('same_name')) {
      expect(
        sameArtistName(c['a']! as String, c['b']! as String),
        c['same'],
        reason: '$c',
      );
    }
  });

  test('title_core and same_title', () {
    for (final c in cases('title_core')) {
      expect(titleCore(c['title']! as String), c['core'], reason: '$c');
    }
    for (final c in cases('same_title')) {
      final (a, b) = (c['a']! as String, c['b']! as String);
      expect(sameTitle(a, b), c['same'], reason: '$c');
      expect(sameTitle(b, a), c['same'], reason: '$c');
    }
  });

  test('songs_asked', () {
    for (final c in cases('songs_asked')) {
      expect(songsAsked(strings(c['songs'])), c['asked'], reason: '$c');
    }
  });

  test('file_path', () {
    for (final c in cases('file_path')) {
      expect(artistPhotoPath(c['name']! as String), c['path'], reason: '$c');
    }
    expect(artistSlugOfPath('artists/adele.jpg'), 'adele');
    expect(artistSlugOfPath('artists/_missing.json'), isNull);
    expect(artistSlugOfPath('music/adele.jpg'), isNull);
    expect(isArtistPath('artists/_missing.json'), isTrue);
    expect(isArtistPath('artistsx/a.jpg'), isFalse);
  });

  test('skipped', () {
    for (final c in cases('skipped')) {
      expect(isSkippedArtist(c['name']! as String), c['skipped'], reason: '$c');
    }
  });

  test('og_image', () {
    for (final c in cases('og_image')) {
      expect(ogImage(c['html']! as String), c['url'], reason: '$c');
    }
  });

  test('photo_url', () {
    for (final c in cases('photo_url')) {
      final og = c['og_image']! as String;
      expect(artistArtOf(og).name, c['art'], reason: '$c');
      expect(artistPhotoUrl(og), c['photo'], reason: '$c');
    }
  });

  test('choose', () {
    for (final c in cases('choose')) {
      // `songs` are the artist's saved songs, and a candidate's `songs`
      // what the searches for them found under its id.
      final chosen = chooseArtist(
        c['name']! as String,
        strings(c['owned']),
        strings(c['songs'] ?? const <String>[]),
        [
          for (final candidate in c['candidates']! as List)
            ArtistCandidate.fromJson(candidate)!,
        ],
      );
      expect(chosen?.id, c['chosen'], reason: '${c['about']}');
    }
  });

  test('a candidate survives the cache file with the songs found', () {
    const candidate = ArtistCandidate(
      id: '1',
      name: 'Adele',
      albums: ['21'],
      songs: ['Hello'],
      page: 'https://music.apple.com/us/artist/1',
    );
    final read = ArtistCandidate.fromJson(
      jsonDecode(jsonEncode(candidate.toJson())),
    )!;
    expect(read.toJson(), candidate.toJson());
    expect(read.songs, ['Hello']);
  });

  test('missing and picked: read, and written back to the same bytes', () {
    for (final c in [...cases('missing'), ...cases('picked')]) {
      final text = c['text']! as String;
      final missing = MissingArtists.decode(text);
      expect(
        missing.backfilled == null
            ? null
            : formatArtistDay(missing.backfilled!),
        c['backfilled'],
      );
      expect(missing.artists.keys.toList()..sort(), c['slugs']);
      expect(missing.encode(), text, reason: '${c['about']}');
      // Only the `picked` cases name the size and the list.
      if (!c.containsKey('picked')) continue;
      expect(missing.photoSize, c['photo_size'], reason: '${c['about']}');
      expect(missing.photoSide, c['photo_size'] ?? 640);
      expect(missing.picked.toList()..sort(), c['picked']);
    }
  });

  test('missing_rewritten and picked_rewritten', () {
    for (final c in [
      ...cases('missing_rewritten'),
      ...cases('picked_rewritten'),
    ]) {
      expect(
        MissingArtists.decode(c['read']! as String).encode(),
        c['written'],
        reason: '${c['about']}',
      );
    }
  });

  test('missing_refused', () {
    for (final c in cases('missing_refused')) {
      expect(
        () => MissingArtists.decode(c['text']! as String),
        throwsA(isA<MissingFormatException>()),
        reason: '$c',
      );
    }
  });

  test('missing_merge and picked_merge', () {
    for (final c in [...cases('missing_merge'), ...cases('picked_merge')]) {
      final files = strings(c['files']).toSet();
      // `library` lists the slugs of the library's artists; a case
      // without it has everyone in the library.
      final library = c['library'] == null
          ? null
          : strings(c['library']).toSet();
      String? merge() => mergedMissing(
        c['theirs'] as String?,
        edits(c['edits']),
        files.contains,
        inLibrary: library?.contains,
      );
      if (c['refused'] == true) {
        expect(
          merge,
          throwsA(isA<MissingFormatException>()),
          reason: '${c['about']}',
        );
      } else {
        expect(merge(), c['written'], reason: '${c['about']}');
      }
    }
  });

  test('an edit survives the queue file', () {
    for (final c in [...cases('missing_merge'), ...cases('picked_merge')]) {
      for (final edit in edits(c['edits'])) {
        expect(
          MissingEdit.fromJson(jsonDecode(jsonEncode(edit.toJson())))!.toJson(),
          edit.toJson(),
        );
      }
    }
  });

  test('due', () {
    for (final c in cases('due')) {
      final tried = TriedArtist(
        name: 'A',
        tried: parseArtistDay(c['tried'])!,
        reason: MissingReason.noMatch,
      );
      expect(
        tried.isDue(parseArtistDay(c['today'])!, parseArtistDay(c['added'])),
        c['due'],
        reason: '$c',
      );
    }
    // Without an entry an artist is always due.
    expect(
      MissingArtists().isDue('adele', DateTime(2026, 11, 15), null),
      isTrue,
    );
  });

  test('cover_order', () {
    for (final c in cases('cover_order')) {
      final saved = [
        for (final s in (c['saved']! as List).cast<Map<String, Object?>>())
          (song: s['kind'] == 'song', added: parseArtistDay(s['added'])!),
      ];
      expect(artistCoverOrder(saved), c['order'], reason: '${c['about']}');
    }
  });

  test('a photo_size or a picked that cannot be read is kept as read', () {
    const odd =
        '{\n'
        '  "version": 1,\n'
        '  "photo_size": "large",\n'
        '  "picked": {"a": 1},\n'
        '  "artists": {}\n'
        '}\n';
    final record = MissingArtists.decode(odd);
    expect(record.photoSize, isNull);
    expect(record.photoSide, 640);
    expect(record.picked, isEmpty);
    expect(record.encode(), odd);
    for (final size in ['0', '-5', '1200.0', '[1200]', 'null']) {
      final text = odd.replaceFirst('"large"', size);
      final read = MissingArtists.decode(text);
      expect(read.photoSize, isNull, reason: size);
      expect(read.encode(), text, reason: size);
    }
    final mixed = odd.replaceFirst('{"a": 1}', '["a", 1]');
    expect(MissingArtists.decode(mixed).picked, isEmpty);
    expect(MissingArtists.decode(mixed).encode(), mixed);
  });

  test('photo_at', () {
    for (final c in cases('photo_at')) {
      expect(
        artistPhotoAt(c['url']! as String, c['side']! as int),
        c['at'],
        reason: '$c',
      );
    }
  });
}
