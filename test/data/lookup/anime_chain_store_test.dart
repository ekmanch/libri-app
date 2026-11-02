import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/anilist_source.dart';
import 'package:library_app/data/lookup/anime_chain_store.dart';
import 'package:library_app/data/models/released.dart';

void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('anime_chains'));
  tearDown(() => cache.deleteSync(recursive: true));

  const first = AniNode(
    id: 154587,
    format: 'TV',
    status: 'FINISHED',
    english: "Frieren: Beyond Journey's End",
    romaji: 'Sousou no Frieren',
    start: Released(2023, 9, 29),
    end: Released(2024, 3, 22),
    episodes: 28,
    duration: 24,
  );
  const third = AniNode(
    id: 209939,
    format: 'TV',
    status: 'NOT_YET_RELEASED',
    start: Released(2027, 10),
  );

  test('a chain is found by any entry in it, read back whole', () async {
    final fetched = DateTime.utc(2026, 11, 2, 8);
    await FileAnimeChainStore(cache)
        .write((fetched: fetched, nodes: [first.toJson(), third.toJson()]));
    final store = FileAnimeChainStore(cache);
    final kept = await store.read(209939);
    expect(kept!.fetched, fetched);
    final back = AniNode.fromJson(kept.nodes.first);
    expect(back.title, "Frieren: Beyond Journey's End");
    expect(back.start, const Released(2023, 9, 29));
    expect(back.episodes, 28);
    expect(AniNode.fromJson(kept.nodes.last).start, const Released(2027, 10));
    expect(await store.read(1), isNull);
  });

  test('a chain walked again replaces the one kept', () async {
    final store = FileAnimeChainStore(cache);
    await store.write((fetched: DateTime.utc(2026), nodes: [third.toJson()]));
    await store.write((
      fetched: DateTime.utc(2026, 11, 2),
      nodes: [first.toJson(), third.toJson()],
    ));
    expect((await store.read(209939))!.nodes, hasLength(2));
    final json = File('${cache.path}/anime_chains.json').readAsStringSync();
    expect(RegExp('"fetched"').allMatches(json), hasLength(1));
  });
}
