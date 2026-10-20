import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/lookup/season_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/data/models/entry_kind.dart';

void main() {
  final now = DateTime(2026, 10, 18, 9, 30);
  final today = DateTime(2026, 10, 18);
  setUp(() => seasonClock = () => today);
  tearDown(() => seasonClock = DateTime.now);

  const fetched = [
    Season(season: 1, released: Released(2022, 11, 23)),
    Season(season: 2, released: Released(2025, 8, 6)),
    // Announced: added, shown "Coming 2027".
    Season(season: 3, released: Released(2027)),
    // Listed with no date yet: waits.
    Season(season: 4),
  ];

  Entry show(
    String slug,
    EntryStatus status, {
    List<Season>? seasons,
    Released? released,
  }) => Entry(
    id: 'shows/$slug',
    type: MediaType.shows,
    title: slug,
    status: status,
    released: released,
    added: DateTime(2026, 1, 1),
    source: 'tmdb:tv:$slug',
    seasons: seasons,
  );

  const two = [
    Season(season: 1, released: Released(2022), status: EntryStatus.done),
    Season(season: 2, released: Released(2025), status: EntryStatus.done),
  ];

  late FakeLookupSource fake;
  late MemorySeasonCheckStore store;
  late SeasonCheck check;

  void setUpCheck({
    LookupFailure? failure,
    bool configured = true,
    Map<String, List<Season>> seasons = const {},
    Set<String> canceled = const {},
    MemorySeasonCheckStore? keep,
  }) {
    fake = FakeLookupSource(
      failure: failure,
      configured: configured,
      seasonsBySource: {
        for (final slug in ['watching', 'done', 'want', 'dnf', 'empty-dnf'])
          'tmdb:tv:$slug': fetched,
        ...seasons,
      },
      canceledSources: canceled,
    );
    store = keep ?? MemorySeasonCheckStore();
    check = SeasonCheck(lookups: LookupService([fake]), store: store);
  }

  Library library(List<Entry> entries) => Library(entries: entries);

  test('asks every linked show but DNF ones with seasons', () async {
    setUpCheck();
    await check.run(
      library([
        show('watching', EntryStatus.inProgress, seasons: two),
        show('done', EntryStatus.done, seasons: two),
        show('want', EntryStatus.want, seasons: two),
        show('dnf', EntryStatus.dnf, seasons: two),
        show('empty-dnf', EntryStatus.dnf),
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
    expect(fake.calls, [
      'seasons:tmdb:tv:watching',
      'seasons:tmdb:tv:done',
      'seasons:tmdb:tv:want',
      'seasons:tmdb:tv:empty-dnf',
    ]);
  });

  test('adds dated seasons above the highest as New, announced too', () async {
    setUpCheck();
    final watching = show('want', EntryStatus.done, seasons: two);
    final result = await check.run(library([watching]), now);
    final added = result.operations.single as AddSeasons;
    expect(added.seasons, const [
      Season(season: 3, released: Released(2027), fresh: true),
    ]);
    final after = added.apply(library([watching])).entries.single;
    // Not out yet: no badge, and the show stays Done.
    expect(after.hasNewSeasonOn(today), isFalse);
    expect(after.hasNewSeasonOn(DateTime(2028)), isTrue);
    expect(after.status, EntryStatus.done);
  });

  test(
    'a show without seasons gets them quietly, its status carried',
    () async {
      setUpCheck();
      final old = show(
        'empty-dnf',
        EntryStatus.dnf,
        released: const Released(2022),
      );
      final result = await check.run(library([old]), now);
      final added = result.operations.single as AddSeasons;
      expect([for (final s in added.seasons) s.fresh], [null, null, null]);
      final after = added.apply(library([old])).entries.single;
      expect(after.released, isNull);
      // DNF goes to the latest season out, the earlier ones are Done.
      expect(
        [for (final s in after.seasons!) s.status],
        [EntryStatus.done, EntryStatus.dnf, null],
      );
      expect(after.status, EntryStatus.dnf);
    },
  );

  test('an announced season gets the lookup\'s new date', () async {
    setUpCheck(
      seasons: {
        'tmdb:tv:want': const [
          ...two,
          Season(season: 3, released: Released(2027, 3, 4)),
        ],
      },
    );
    final watching = show(
      'want',
      EntryStatus.done,
      seasons: const [
        ...two,
        Season(season: 3, released: Released(2027)),
      ],
    );
    final result = await check.run(library([watching]), now);
    final redated = result.operations.single as SetSeasonDates;
    expect(redated.dates, const [
      Season(season: 3, released: Released(2027, 3, 4)),
    ]);
  });

  group('a dropped season', () {
    const announced = Season(season: 3, released: Released(2027));
    final listedWithout = {'tmdb:tv:want': two};

    Future<SeasonCheckResult> twoChecks(
      Entry show, {
      Map<String, List<Season>>? seasons,
      Set<String> canceled = const {},
    }) async {
      setUpCheck(seasons: seasons ?? listedWithout, canceled: canceled);
      final first = await check.run(library([show]), now);
      expect(first.operations, isEmpty, reason: 'one miss is not enough');
      expect(first.dropped, isEmpty);
      return check.run(library([show]), now.add(const Duration(days: 1)));
    }

    test('without a status is removed on the second miss', () async {
      final result = await twoChecks(
        show('want', EntryStatus.done, seasons: const [...two, announced]),
      );
      final removed = result.operations.single as RemoveSeason;
      expect(removed.season, 3);
    });

    test('with a status is asked about', () async {
      final result = await twoChecks(
        show(
          'want',
          EntryStatus.done,
          seasons: [
            ...two,
            announced.copyWith(status: EntryStatus.want),
          ],
        ),
      );
      expect(result.operations, isEmpty);
      expect(result.dropped, [
        (entryId: 'shows/want', season: 3, status: EntryStatus.want),
      ]);
    });

    test('a show marked Canceled drops its announced seasons', () async {
      final result = await twoChecks(
        show('want', EntryStatus.done, seasons: const [...two, announced]),
        seasons: {
          'tmdb:tv:want': const [...two, announced],
        },
        canceled: {'tmdb:tv:want'},
      );
      expect((result.operations.single as RemoveSeason).season, 3);
    });

    test('a miss, then a listing, starts over', () async {
      final watching = show(
        'want',
        EntryStatus.done,
        seasons: const [...two, announced],
      );
      setUpCheck(seasons: listedWithout);
      await check.run(library([watching]), now);
      expect(await store.missing(), {'shows/want#3'});
      setUpCheck(
        seasons: {
          'tmdb:tv:want': const [...two, announced],
        },
        keep: store,
      );
      final again = await check.run(
        library([watching]),
        now.add(const Duration(days: 1)),
      );
      expect(again.operations, isEmpty);
      expect(await store.missing(), isEmpty);
    });

    test('manual seasons and seasons out are never touched', () async {
      final result = await twoChecks(
        show(
          'want',
          EntryStatus.done,
          seasons: [
            two.first,
            // Out, and gone from the lookup.
            const Season(season: 2, released: Released(2025)),
            announced.copyWith(manual: true),
          ],
        ),
        seasons: {
          'tmdb:tv:want': [two.first],
        },
      );
      expect(result.operations, isEmpty);
      expect(result.dropped, isEmpty);
    });
  });

  test('a status the seasons no longer give is written', () async {
    setUpCheck(configured: false);
    final stale = Entry(
      id: 'shows/stale',
      type: MediaType.shows,
      title: 'Stale',
      // Season 2 came out today and is Want: the show is In progress now.
      status: EntryStatus.done,
      added: DateTime(2026),
      seasons: const [
        Season(season: 1, released: Released(2025), status: EntryStatus.done),
        Season(
          season: 2,
          released: Released(2026, 10, 18),
          status: EntryStatus.want,
        ),
      ],
    );
    final result = await check.run(library([stale]), now);
    expect(result.operations.single, isA<RefreshShowStatus>());
  });

  test('runs once a day', () async {
    setUpCheck();
    final watching = show('want', EntryStatus.done, seasons: two);
    await check.run(library([watching]), now);
    expect(await store.lastRun(), DateTime(2026, 10, 18));
    final again = await check.run(
      library([watching]),
      now.add(const Duration(hours: 8)),
    );
    expect(again.operations, isEmpty);
    expect(fake.calls, hasLength(1));
    final tomorrow = await check.run(
      library([watching]),
      DateTime(2026, 10, 19, 7),
    );
    expect(tomorrow.operations, hasLength(1));
  });

  test('offline is tried again; no key records the day', () async {
    setUpCheck(failure: LookupFailure.offline);
    final watching = show('want', EntryStatus.done, seasons: two);
    expect((await check.run(library([watching]), now)).operations, isEmpty);
    expect(await store.lastRun(), isNull);

    setUpCheck(configured: false);
    expect((await check.run(library([watching]), now)).operations, isEmpty);
    expect(fake.calls, isEmpty);
    expect(await store.lastRun(), DateTime(2026, 10, 18));
  });

  test('a server error is tried again; a bad answer records the day', () async {
    final watching = show('want', EntryStatus.done, seasons: two);
    for (final (status, recorded) in [
      (503, false),
      (500, false),
      (404, true),
    ]) {
      final source = _FailingSeasons(status);
      final memory = MemorySeasonCheckStore();
      final failing = SeasonCheck(
        lookups: LookupService([source]),
        store: memory,
      );
      expect((await failing.run(library([watching]), now)).operations, isEmpty);
      expect(source.asked, 1, reason: '$status');
      expect(
        await memory.lastRun(),
        recorded ? DateTime(2026, 10, 18) : isNull,
        reason: '$status',
      );
    }
  });

  test('the file store keeps the day and the missed seasons', () async {
    final dir = Directory.systemTemp.createTempSync('libri-season-check-');
    addTearDown(() => dir.deleteSync(recursive: true));
    await FileSeasonCheckStore(dir)
        .recordRun(DateTime(2026, 10, 18), {'shows/b#2', 'shows/a#3'});
    final text = File('${dir.path}/season_check.json').readAsStringSync();
    expect(text, contains('"checked": "2026-10-18"'));
    expect(text.indexOf('shows/a#3'), lessThan(text.indexOf('shows/b#2')));
    final store = FileSeasonCheckStore(dir);
    expect(await store.lastRun(), DateTime(2026, 10, 18));
    expect(await store.missing(), {'shows/a#3', 'shows/b#2'});
  });

  group('anime', () {
    Entry anime(
      String slug,
      EntryStatus status, {
      EntryKind? kind,
      List<Season>? seasons,
      Released? released,
    }) => Entry(
      id: 'anime/$slug',
      type: MediaType.anime,
      title: slug,
      status: status,
      released: released,
      added: DateTime(2026, 1, 1),
      source: 'anilist:$slug',
      kind: kind,
      seasons: seasons,
    );

    test(
      'a series linked to AniList is asked like a show; a movie is not',
      () async {
        setUpCheck(
          seasons: {'anilist:series': fetched, 'anilist:unknown': fetched},
        );
        await check.run(
          library([
            anime(
              'series',
              EntryStatus.inProgress,
              kind: EntryKind.series,
              seasons: two,
            ),
            anime('movie', EntryStatus.done, kind: EntryKind.movie),
            anime('unknown', EntryStatus.done, released: const Released(2022)),
            anime('dnf', EntryStatus.dnf, kind: EntryKind.series, seasons: two),
          ]),
          now,
        );
        expect(fake.calls, [
          'seasons:anilist:series',
          'seasons:anilist:unknown',
        ]);
      },
    );

    test(
      'an anime without a kind learns it: a series gets its seasons',
      () async {
        setUpCheck(seasons: {'anilist:frieren': fetched});
        fake = FakeLookupSource(
          seasonsBySource: {'anilist:frieren': fetched},
          kindBySource: {'anilist:frieren': EntryKind.series},
        );
        check = SeasonCheck(lookups: LookupService([fake]), store: store);
        final entry = anime(
          'frieren',
          EntryStatus.done,
          released: const Released(2023),
        );
        final result = await check.run(library([entry]), now);
        expect(result.operations.map((o) => o.runtimeType), [
          SetKind,
          AddSeasons,
        ]);
        var lib = library([entry]);
        for (final op in result.operations) {
          lib = op.apply(lib);
        }
        final after = lib.entries.single;
        expect(after.kind, EntryKind.series);
        expect(after.usesSeasons, isTrue);
        expect(after.released, isNull);
        // Done carried into the seasons out; the show stays Done.
        expect(after.seasons!.map((s) => s.status), [
          EntryStatus.done,
          EntryStatus.done,
          null,
        ]);
        expect(after.status, EntryStatus.done);
      },
    );

    test(
      'an anime without a kind that is a movie is marked so and left alone',
      () async {
        fake = FakeLookupSource(
          seasonsBySource: {'anilist:akira': const []},
          kindBySource: {'anilist:akira': EntryKind.movie},
        );
        store = MemorySeasonCheckStore();
        check = SeasonCheck(lookups: LookupService([fake]), store: store);
        final entry = anime(
          'akira',
          EntryStatus.done,
          released: const Released(1988),
        );
        final result = await check.run(library([entry]), now);
        final op = result.operations.single as SetKind;
        expect(op.kind, EntryKind.movie);
        final after = op.apply(library([entry])).entries.single;
        expect(after.released, const Released(1988));
        expect(after.seasons, isNull);
        // Known a movie now: never asked again.
        store = MemorySeasonCheckStore();
        check = SeasonCheck(lookups: LookupService([fake]), store: store);
        fake.calls.clear();
        await check.run(library([after]), now);
        expect(fake.calls, isEmpty);
      },
    );

    test(
      'a lookup that cannot say the kind leaves the anime as it is',
      () async {
        fake = FakeLookupSource(seasonsBySource: {'anilist:x': fetched});
        store = MemorySeasonCheckStore();
        check = SeasonCheck(lookups: LookupService([fake]), store: store);
        final result = await check.run(
          library([
            anime('x', EntryStatus.done, released: const Released(2022)),
          ]),
          now,
        );
        expect(result.operations, isEmpty);
      },
    );

    test('a drifted status is written for an anime series too', () async {
      setUpCheck();
      final entry = anime(
        'drift',
        EntryStatus.want,
        kind: EntryKind.series,
        seasons: const [
          Season(season: 1, released: Released(2022), status: EntryStatus.done),
        ],
      ).copyWith(source: null);
      final result = await check.run(library([entry]), now);
      expect(result.operations.single, isA<RefreshShowStatus>());
    });
  });
}

/// A show source whose seasons fail with [status].
class _FailingSeasons extends FakeLookupSource {
  _FailingSeasons(this.status);

  final int status;
  var asked = 0;

  @override
  Future<ShowSeasons?> seasons(String source) async {
    asked++;
    throw LookupException(LookupFailure.other, status: status);
  }
}
