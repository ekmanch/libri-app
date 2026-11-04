import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/season_split_store.dart';
import 'package:library_app/data/models/season_span.dart';
import 'package:library_app/data/models/season_split.dart';

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('season_splits'));
  tearDown(() => cache.deleteSync(recursive: true));

  File file() => File('${cache.path}/season_splits.json');

  const split = SeasonSplit(
    ids: [SeasonSplit.anilistId],
    seasons: [SeasonSpan(season: 1, episodes: 12)],
  );

  test('a list written now reads back, under the version', () async {
    final store = FileSeasonSplitStore(cache);
    final when = DateTime.utc(2026, 11, 4, 8);
    await store.write('anilist:1|', const [split], when);
    final read = await FileSeasonSplitStore(cache).read('anilist:1|');
    expect(read!.splits, const [split]);
    expect(read.fetched, when);
    expect(
      (jsonDecode(file().readAsStringSync()) as Map)['version'],
      FileSeasonSplitStore.version,
    );
  });

  test('a file from the build before folding is dropped once', () async {
    file().writeAsStringSync(
      jsonEncode({
        'anilist:269|tmdb:tv:30984': {
          'fetched': '2026-11-03T08:00:00.000Z',
          'splits': [split.toJson()],
        },
      }),
    );
    final store = FileSeasonSplitStore(cache);
    expect(await store.read('anilist:269|tmdb:tv:30984'), isNull);
    await store.write('anilist:1|', const [split], DateTime.utc(2026, 11, 4));
    final json = jsonDecode(file().readAsStringSync()) as Map;
    expect(json.keys, unorderedEquals(['version', 'anilist:1|']));
  });
}
