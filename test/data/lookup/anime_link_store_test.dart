import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/anime_link_store.dart';
import 'package:library_app/data/models/entry_kind.dart';

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('anime_links'));
  tearDown(() => cache.deleteSync(recursive: true));

  File file() => File('${cache.path}/anime_links.json');

  test('a link from an older build reads, its re-split flag ignored', () async {
    file().writeAsStringSync(
      jsonEncode({
        '154587': {
          'tmdb': 'tmdb:tv:209867',
          'kind': 'series',
          'checked': '2026-10-20T08:00:00.000Z',
          'resplit': true,
        },
        '47': {
          'tmdb': null,
          'kind': 'movie',
          'checked': '2026-10-20T08:00:00.000Z',
        },
      }),
    );
    final store = FileAnimeLinkStore(cache);
    final frieren = await store.read(154587);
    expect(frieren!.tmdb, 'tmdb:tv:209867');
    expect(frieren.tmdbChecked, isNull);
    final akira = await store.read(47);
    expect(akira!.kind, EntryKind.movie);
    expect(akira.tmdb, isNull);
  });

  test('a link written now reads back as it was', () async {
    final store = FileAnimeLinkStore(cache);
    final link = (
      kind: EntryKind.series,
      checked: DateTime.utc(2026, 11, 2, 8),
      tmdb: 'tmdb:tv:209867',
      tmdbChecked: DateTime.utc(2026, 11, 2, 9),
      tvdb: 424536,
      tvdbSeason: 1,
      armChecked: DateTime.utc(2026, 11, 4, 9),
    );
    await store.write(154587, link);
    expect(await FileAnimeLinkStore(cache).read(154587), link);
    expect(await store.read(1), isNull);
  });
}
