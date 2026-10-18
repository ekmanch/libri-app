import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/features/entry/seasons.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/widgets/segmented_control.dart';

import '../../helpers/pump_app.dart';

class _Opener extends StatelessWidget {
  const _Opener(this.entryId);
  final String entryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showEntryDetailsSheet(context, entryId),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

const _twinPeaks = 'shows/twin-peaks-1990';
const _shadows = 'shows/what-we-do-in-the-shadows-2019';
const _strangerThings = 'shows/stranger-things-2016';
const _hillHouse = 'shows/the-haunting-of-hill-house-2018';

void main() {
  Future<ProviderContainer> open(
    WidgetTester tester,
    String entryId, {
    Library? library,
  }) async {
    final container = await pumpApp(tester, _Opener(entryId), library: library);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  Entry saved(ProviderContainer c, String id) =>
      (c.read(libraryRepositoryProvider) as FixtureLibraryRepository).current!
          .entryById(id)!;

  Finder pill(int season) =>
      find.bySemanticsLabel(RegExp('^Season $season status: '));

  /// Scrolls [finder] into view in the sheet, then taps it.
  Future<void> tapIn(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('a show lists its seasons, and the header the years it ran', (
    tester,
  ) async {
    await open(tester, _twinPeaks);
    expect(find.text('SHOW · 1990–2017'), findsOneWidget);
    expect(find.text('SEASONS'), findsOneWidget);
    expect(find.text('3 seasons'), findsOneWidget);
    for (final n in [1, 2, 3]) {
      expect(find.text('Season $n'), findsOneWidget);
    }
    expect(find.text('Apr 8, 1990'), findsOneWidget);
    expect(pill(1), findsOneWidget);
    expect(find.textContaining('All 3 seasons'), findsNothing);
  });

  testWidgets('six seasons or more: the latest three and a row to all', (
    tester,
  ) async {
    await open(tester, _shadows);
    expect(find.text('Season 1'), findsNothing);
    expect(find.text('Season 4'), findsOneWidget);
    expect(find.text('Season 6'), findsOneWidget);
    await tapIn(tester, find.text('All 6 seasons'));
    expect(find.byType(AllSeasonsScreen), findsOneWidget);
    expect(find.text('6 seasons · 2019–2024'), findsOneWidget);
    for (final n in [1, 2, 3, 4, 5, 6]) {
      expect(find.text('Season $n'), findsWidgets);
    }
  });

  testWidgets(
    'a pick in the status sheet sets the season and the show follows',
    (tester) async {
      final container = await open(tester, _strangerThings);
      expect(
        find.bySemanticsLabel(RegExp('Season 4 status: not set')),
        findsOne,
      );
      await tapIn(tester, pill(4));
      expect(find.byType(SeasonStatusSheet), findsOneWidget);
      expect(find.text('Released May 27, 2022.'), findsOneWidget);
      await tapIn(
        tester,
        find.descendant(
          of: find.byType(SeasonStatusSheet),
          matching: find.text('In progress'),
        ),
      );
      expect(find.byType(SeasonStatusSheet), findsNothing);
      final show = saved(container, _strangerThings);
      expect(show.seasons![3].status, EntryStatus.inProgress);
      // Season 3 is DNF, but a season In progress comes first.
      expect(show.status, EntryStatus.inProgress);
      expect(
        find.bySemanticsLabel(RegExp('Season 4 status: in progress')),
        findsOne,
      );
    },
  );

  testWidgets('catch-up marks the earlier seasons Done and stays open', (
    tester,
  ) async {
    final container = await open(tester, _strangerThings);
    await tapIn(tester, pill(5));
    expect(find.text('Mark seasons 1–4 Done'), findsOneWidget);
    expect(
      find.text("For catching up when you add a show you're partway through."),
      findsOneWidget,
    );
    await tapIn(tester, find.text('Mark seasons 1–4 Done'));
    expect(find.byType(SeasonStatusSheet), findsOneWidget);
    expect(find.text('Mark seasons 1–4 Done'), findsNothing);
    final seasons = saved(container, _strangerThings).seasons!;
    expect(
      [for (final s in seasons) s.status],
      [
        EntryStatus.done,
        EntryStatus.done,
        EntryStatus.done,
        EntryStatus.done,
        null,
      ],
    );
  });

  testWidgets('no catch-up for season 1 or when all before are Done', (
    tester,
  ) async {
    await open(tester, _twinPeaks);
    await tapIn(tester, pill(3));
    expect(find.textContaining('Mark season'), findsNothing);
    expect(SeasonStatusSheet.catchUpLabel(2), 'Mark season 1 Done');
    expect(SeasonStatusSheet.catchUpLabel(29), 'Mark seasons 1–28 Done');
  });

  testWidgets('a new season is marked New, and the header says so', (
    tester,
  ) async {
    final fixture = loadFixture();
    final twinPeaks = fixture.entryById(_twinPeaks)!;
    final withNew = twinPeaks.copyWith(
      seasons: [
        ...twinPeaks.seasons!,
        const Season(season: 4, released: Released(2026, 10, 9), fresh: true),
      ],
    );
    final container = await open(
      tester,
      _twinPeaks,
      library: fixture.copyWith(
        entries: [
          for (final e in fixture.entries) e.id == _twinPeaks ? withNew : e,
        ],
      ),
    );
    expect(find.text('New season'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    await tapIn(tester, pill(4));
    await tapIn(
      tester,
      find.descendant(
        of: find.byType(SeasonStatusSheet),
        matching: find.text('Want'),
      ),
    );
    expect(find.text('New season'), findsNothing);
    expect(find.text('New'), findsNothing);
    expect(saved(container, _twinPeaks).seasons!.last.fresh, isNull);
  });

  testWidgets('several seasons: a status row from the seasons, no control', (
    tester,
  ) async {
    await open(tester, _twinPeaks);
    expect(find.byType(StatusSegmentedControl), findsNothing);
    expect(find.bySemanticsLabel('Status, Done, from seasons'), findsOneWidget);
  });

  testWidgets('one season: the status control is that season, no list', (
    tester,
  ) async {
    final container = await open(tester, _hillHouse);
    expect(find.text('SEASONS'), findsNothing);
    expect(find.byType(ShowStatusRow), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(StatusSegmentedControl),
        matching: find.text('Want'),
      ),
    );
    await tester.pumpAndSettle();
    final show = saved(container, _hillHouse);
    expect(show.status, EntryStatus.want);
    expect(show.seasons!.single.status, EntryStatus.want);

    // A second season appears (A35): the list replaces the control, and
    // the show keeps the status Season 1 gives.
    await container
        .read(libraryRepositoryProvider)
        .apply(
          const AddSeasons(_hillHouse, [
            Season(season: 2, released: Released(2099), fresh: true),
          ]),
        );
    await tester.pumpAndSettle();
    expect(find.byType(StatusSegmentedControl), findsNothing);
    expect(find.bySemanticsLabel('Status, Want, from seasons'), findsOneWidget);
    expect(find.text('SEASONS'), findsOneWidget);
    expect(find.text('Coming 2099'), findsOneWidget);
    // Not out yet: no New label.
    expect(find.text('New'), findsNothing);
  });

  test('a season\'s date says Coming until it is out', () {
    final today = DateTime(2026, 10, 18);
    expect(
      seasonDateLabel(const Season(season: 1, released: Released(2027)), today),
      'Coming 2027',
    );
    expect(
      seasonDateLabel(
        const Season(season: 1, released: Released(2026, 10, 30)),
        today,
      ),
      'Coming Oct 30, 2026',
    );
    expect(
      seasonDateLabel(
        const Season(season: 1, released: Released(2026, 10, 18)),
        today,
      ),
      'Oct 18, 2026',
    );
    expect(
      seasonDateLabel(const Season(season: 1), today),
      'Release date not set',
    );
  });

  test('All seasons opens at the one in progress, else the first not Done', () {
    List<Season> seasons(List<EntryStatus?> statuses) => [
      for (final (i, s) in statuses.indexed) Season(season: i + 1, status: s),
    ];
    const done = EntryStatus.done, watching = EntryStatus.inProgress;
    expect(AllSeasonsScreen.currentIndex(seasons([done, done, watching])), 2);
    expect(AllSeasonsScreen.currentIndex(seasons([done, null, null])), 1);
    expect(AllSeasonsScreen.currentIndex(seasons([null, null])), 0);
    expect(AllSeasonsScreen.currentIndex(seasons([done, done])), 1);
  });

  testWidgets('All seasons scrolls to the season being watched', (
    tester,
  ) async {
    final fixture = loadFixture();
    final southPark = Entry(
      id: 'shows/south-park-1997',
      type: MediaType.shows,
      title: 'South Park',
      status: EntryStatus.inProgress,
      added: DateTime(2026, 10, 18),
      seasons: [
        for (var n = 1; n <= 29; n++)
          Season(
            season: n,
            released: Released(1996 + n),
            status: n < 29 ? EntryStatus.done : EntryStatus.inProgress,
          ),
      ],
    );
    await pumpApp(
      tester,
      AllSeasonsScreen(showId: southPark.id),
      library: fixture.copyWith(entries: [...fixture.entries, southPark]),
    );
    expect(find.text('29 seasons · 1997–2025'), findsOneWidget);
    expect(find.text('Season 29'), findsOneWidget);
    expect(tester.getRect(find.text('Season 29')).bottom, lessThan(780));
    expect(find.text('Season 1').hitTestable(), findsNothing);
  });
}
