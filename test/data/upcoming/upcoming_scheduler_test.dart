import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/check_day_store.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/release_check.dart';
import 'package:library_app/data/lookup/season_check.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/net/network_kind.dart';
import 'package:library_app/data/operations/library_operation.dart';
import 'package:library_app/data/upcoming/check_control.dart';
import 'package:library_app/data/upcoming/creator_check.dart';
import 'package:library_app/data/upcoming/creator_lookup.dart';
import 'package:library_app/data/upcoming/creator_status.dart';
import 'package:library_app/data/upcoming/upcoming_scheduler.dart';
import 'package:library_app/dev/fake_lookup.dart';

void main() {
  final today = DateTime(2026, 10, 30);
  var now = DateTime(2026, 10, 30, 9, 30);

  Entry entry(
    String id,
    MediaType type, {
    EntryStatus status = EntryStatus.done,
    Released? released,
    String? source,
    List<Season>? seasons,
    List<String> tags = const [],
    String? creator,
  }) => Entry(
    id: id,
    type: type,
    title: id,
    status: status,
    released: released,
    added: DateTime(2026, 1, 1),
    source: source,
    seasons: seasons,
    tags: tags,
    creator: creator,
  );

  // A show with a season still to come (daily) and one without (weekly), a
  // wanted game (daily) and a dated-less done game (weekly), and an author.
  final coming = entry(
    'shows/coming',
    MediaType.shows,
    source: 'tmdb:tv:1',
    seasons: const [
      Season(season: 1, released: Released(2025), status: EntryStatus.done),
      Season(season: 2, released: Released(2027, 3)),
    ],
  );
  final settled = entry(
    'shows/settled',
    MediaType.shows,
    source: 'tmdb:tv:2',
    seasons: const [
      Season(season: 1, released: Released(2020), status: EntryStatus.done),
    ],
  );
  final wanted = entry(
    'games/wanted',
    MediaType.games,
    status: EntryStatus.want,
    source: 'igdb:1',
  );
  final undated = entry('games/undated', MediaType.games, source: 'igdb:2');
  final book = entry(
    'books/it',
    MediaType.books,
    creator: 'Stephen King',
    tags: const ['stephen-king'],
  );
  final library = Library(
    tags: const {
      TagCategory.authors: ['stephen-king'],
    },
    entries: [coming, settled, wanted, undated, book],
  );

  late FakeLookupSource fake;
  late MemorySeasonCheckStore seasonDays;
  late MemoryCheckDayStore releaseDays;
  late MemoryCheckDayStore creatorDays;
  late MemoryUpcomingScheduleStore schedule;
  late List<LibraryOperation> applied;

  setUp(() {
    fake = FakeLookupSource();
    seasonDays = MemorySeasonCheckStore();
    releaseDays = MemoryCheckDayStore();
    creatorDays = MemoryCheckDayStore();
    schedule = MemoryUpcomingScheduleStore();
    applied = [];
  });

  UpcomingScheduler scheduler({NetworkKind? network}) {
    final lookups = LookupService([fake]);
    return UpcomingScheduler(
      seasons: SeasonCheck(lookups: lookups, store: seasonDays),
      releases: ReleaseCheck(lookups: lookups, store: releaseDays),
      creators: CreatorCheck(
        lookups: lookups,
        statuses: MemoryCreatorStatusStore(),
        releases: MemoryFoundReleaseStore(),
        store: creatorDays,
      ),
      store: schedule,
      network: network ?? const FixedNetworkKind(),
      now: () => now,
    );
  }

  Future<UpcomingRunResult> run(
    UpcomingScheduler s, {
    AppSettings settings = AppSettings.defaults,
    bool wifiOnly = false,
    bool everything = false,
  }) => s.run(
    library: library,
    settings: settings,
    wifiOnly: wifiOnly,
    everything: everything,
    apply: (op) async => applied.add(op),
  );

  Iterable<String> asked(String prefix) =>
      fake.calls.where((c) => c.startsWith(prefix));

  test('shares are stable and seven; a missed week means all of them', () {
    expect(
      UpcomingScheduler.shareOf('books/it'),
      UpcomingScheduler.shareOf('books/it'),
    );
    expect(UpcomingScheduler.shareOf('books/it'), inInclusiveRange(0, 6));
    expect(UpcomingScheduler.shareOn(today), inInclusiveRange(0, 6));
    expect(
      UpcomingScheduler.shareOn(today.add(const Duration(days: 7))),
      UpcomingScheduler.shareOn(today),
    );
    expect(UpcomingScheduler.dueShares(null, today), {0, 1, 2, 3, 4, 5, 6});
    expect(
      UpcomingScheduler.dueShares(
        today.subtract(const Duration(days: 1)),
        today,
      ),
      {UpcomingScheduler.shareOn(today)},
    );
    expect(
      UpcomingScheduler.dueShares(
        today.subtract(const Duration(days: 3)),
        today,
      ),
      {
        UpcomingScheduler.shareOn(today),
        UpcomingScheduler.shareOn(today.subtract(const Duration(days: 1))),
        UpcomingScheduler.shareOn(today.subtract(const Duration(days: 2))),
      },
    );
    expect(
      UpcomingScheduler.dueShares(
        today.subtract(const Duration(days: 9)),
        today,
      ),
      {0, 1, 2, 3, 4, 5, 6},
    );
    expect(UpcomingScheduler.dueShares(today, today), isEmpty);
  });

  test('a first run asks about everything and records the day', () async {
    final s = scheduler();
    final result = await run(s);
    expect(result.outcome, UpcomingRunOutcome.ran);
    expect(result.complete, isTrue);
    expect(asked('seasons:'), ['seasons:tmdb:tv:1', 'seasons:tmdb:tv:2']);
    expect(asked('released:'), ['released:igdb:1', 'released:igdb:2']);
    expect(asked('creator:'), ['creator:authors:Stephen King']);
    final stored = await schedule.read();
    expect(stored.lastRun, today);
    expect(stored.lastChecked, now);
    expect(s.progress.value, CheckProgress.idle);
  });

  test(
    'the next day asks daily items, and weekly ones only in their share',
    () async {
      await run(scheduler());
      fake.calls.clear();
      now = DateTime(2026, 10, 31, 8);
      final result = await run(scheduler());
      expect(result.outcome, UpcomingRunOutcome.ran);
      final share = UpcomingScheduler.shareOn(DateTime(2026, 10, 31));
      bool inShare(String id) => UpcomingScheduler.shareOf(id) == share;
      expect(asked('seasons:'), [
        'seasons:tmdb:tv:1',
        if (inShare(settled.id)) 'seasons:tmdb:tv:2',
      ]);
      expect(asked('released:'), [
        'released:igdb:1',
        if (inShare(undated.id)) 'released:igdb:2',
      ]);
      expect(
        asked('releases:').isNotEmpty,
        inShare('authors/stephen-king'),
        reason: 'a creator is asked in its share only',
      );
    },
  );

  test(
    'a run already done today does nothing; Check now runs it all again',
    () async {
      await run(scheduler());
      fake.calls.clear();
      now = DateTime(2026, 10, 30, 15);
      expect((await run(scheduler())).outcome, UpcomingRunOutcome.alreadyRan);
      expect(fake.calls, isEmpty);
      final result = await run(scheduler(), everything: true);
      expect(result.outcome, UpcomingRunOutcome.ran);
      expect(asked('seasons:'), hasLength(2));
      expect(asked('released:'), hasLength(2));
    },
  );

  test(
    'the master switch off and mobile data on Wi-Fi only stop the run',
    () async {
      expect(
        (await run(
          scheduler(),
          settings: const AppSettings(upcomingEnabled: false),
        )).outcome,
        UpcomingRunOutcome.disabled,
      );
      expect(fake.calls, isEmpty);
      expect(
        (await run(
          scheduler(network: const FixedNetworkKind(mobile: true)),
          wifiOnly: true,
        )).outcome,
        UpcomingRunOutcome.onMobileData,
      );
      expect(fake.calls, isEmpty);
      // Check now runs on mobile data anyway.
      final result = await run(
        scheduler(network: const FixedNetworkKind(mobile: true)),
        wifiOnly: true,
        everything: true,
      );
      expect(result.outcome, UpcomingRunOutcome.ran);
      expect(fake.calls, isNotEmpty);
    },
  );

  test(
    'progress counts the items asked; Stop ends the run with no day recorded',
    () async {
      final s = scheduler();
      final seen = <CheckProgress>[];
      s.progress.addListener(() => seen.add(s.progress.value));
      final result = await run(s);
      expect(seen.first, const CheckProgress(running: true, done: 0, total: 5));
      expect(seen.where((p) => p.running).last.done, 5);
      expect(result.complete, isTrue);

      fake.calls.clear();
      seasonDays = MemorySeasonCheckStore();
      releaseDays = MemoryCheckDayStore();
      creatorDays = MemoryCheckDayStore();
      schedule = MemoryUpcomingScheduleStore();
      final stopped = scheduler();
      stopped.progress.addListener(() {
        if (stopped.progress.value.done == 1) stopped.stop();
      });
      final result2 = await run(stopped);
      expect(result2.outcome, UpcomingRunOutcome.ran);
      expect(result2.complete, isFalse);
      expect(fake.calls.length, lessThan(5));
      expect((await schedule.read()).lastRun, isNull);
      expect((await schedule.read()).lastChecked, now);
      expect(await seasonDays.lastRun(), isNull);
    },
  );
}
