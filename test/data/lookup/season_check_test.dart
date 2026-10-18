import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/season_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/dev/fake_lookup.dart';

void main() {
  final now = DateTime(2026, 10, 18, 9, 30);

  const fetched = [
    Season(season: 1, released: Released(2022, 11, 23)),
    Season(season: 2, released: Released(2025, 8, 6)),
    // Twelve days ahead: added as a heads-up.
    Season(season: 3, released: Released(2026, 10, 30)),
    // Next year: not yet.
    Season(season: 4, released: Released(2027, 6, 1)),
  ];

  Entry show(
    String slug,
    EntryStatus status, {
    String? source,
    List<Season>? seasons,
  }) => Entry(
    id: 'shows/$slug',
    type: MediaType.shows,
    title: slug,
    status: status,
    added: DateTime(2026, 1, 1),
    source: source ?? 'tmdb:tv:$slug',
    seasons: seasons,
  );

  late FakeLookupSource fake;
  late MemorySeasonCheckStore store;
  late SeasonCheck check;

  void setUpCheck({LookupFailure? failure, bool configured = true}) {
    fake = FakeLookupSource(
      failure: failure,
      configured: configured,
      seasonsBySource: {
        for (final slug in ['watching', 'done', 'want', 'dnf', 'fresh'])
          'tmdb:tv:$slug': fetched,
      },
    );
    store = MemorySeasonCheckStore();
    check = SeasonCheck(lookups: LookupService([fake]), store: store);
  }

  final watching = show(
    'watching',
    EntryStatus.inProgress,
    seasons: const [
      Season(season: 1, released: Released(2022), status: EntryStatus.done),
      Season(season: 2, released: Released(2025), status: EntryStatus.done),
    ],
  );

  Library library(List<Entry> entries) => Library(entries: entries);

  test('only In progress and Done shows with a source are asked', () async {
    setUpCheck();
    await check.run(
      library([
        watching,
        show('done', EntryStatus.done, seasons: const [Season(season: 1)]),
        show('want', EntryStatus.want),
        show('dnf', EntryStatus.dnf),
        Entry(
          id: 'shows/no-source',
          type: MediaType.shows,
          title: 'No source',
          status: EntryStatus.done,
          added: DateTime(2026),
        ),
      ]),
      now,
    );
    expect(fake.calls, ['seasons:tmdb:tv:watching', 'seasons:tmdb:tv:done']);
  });

  test(
    'adds the seasons above the highest as New, announced ones too',
    () async {
      setUpCheck();
      final operations = await check.run(library([watching]), now);
      final added = operations.single;
      expect(added.entryId, watching.id);
      expect(added.seasons, const [
        Season(season: 3, released: Released(2026, 10, 30), fresh: true),
        Season(season: 4, released: Released(2027, 6, 1), fresh: true),
      ]);
      final after = added.apply(library([watching]));
      expect(
        after.entries.single.hasNewSeasonOn(DateTime(2026, 10, 30)),
        isTrue,
      );
      expect(added.summary(library([watching])), 'Add seasons 3–4 of watching');
    },
  );

  test('a show with no seasons gets them all quietly', () async {
    setUpCheck();
    final fresh = show('fresh', EntryStatus.done);
    final operations = await check.run(library([fresh]), now);
    expect(operations.single.seasons, const [
      Season(season: 1, released: Released(2022, 11, 23)),
      Season(season: 2, released: Released(2025, 8, 6)),
      Season(season: 3, released: Released(2026, 10, 30)),
      Season(season: 4, released: Released(2027, 6, 1)),
    ]);
  });

  test('nothing new means no operation', () async {
    setUpCheck();
    final upToDate = watching.copyWith(
      seasons: const [Season(season: 4, released: Released(2027, 6, 1))],
    );
    expect(await check.run(library([upToDate]), now), isEmpty);
  });

  test('runs once a day', () async {
    setUpCheck();
    await check.run(library([watching]), now);
    expect(await store.lastRun(), DateTime(2026, 10, 18));
    expect(
      await check.run(library([watching]), now.add(const Duration(hours: 8))),
      isEmpty,
    );
    expect(fake.calls, hasLength(1));
    final tomorrow = await check.run(
      library([watching]),
      DateTime(2026, 10, 19, 7),
    );
    expect(tomorrow, hasLength(1));
  });

  test('offline is tried again; no key records the day', () async {
    setUpCheck(failure: LookupFailure.offline);
    expect(await check.run(library([watching]), now), isEmpty);
    expect(await store.lastRun(), isNull);

    setUpCheck(configured: false);
    expect(await check.run(library([watching]), now), isEmpty);
    expect(fake.calls, isEmpty);
    expect(await store.lastRun(), DateTime(2026, 10, 18));
  });

  test('the file store keeps the day', () async {
    final dir = Directory.systemTemp.createTempSync('libri-season-check-');
    addTearDown(() => dir.deleteSync(recursive: true));
    await FileSeasonCheckStore(dir).recordRun(DateTime(2026, 10, 18));
    expect(
      File('${dir.path}/season_check.json').readAsStringSync(),
      contains('"checked": "2026-10-18"'),
    );
    expect(await FileSeasonCheckStore(dir).lastRun(), DateTime(2026, 10, 18));
  });
}
