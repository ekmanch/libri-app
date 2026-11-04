import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/episode_info.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/season_span.dart';
import 'package:library_app/data/models/season_split.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/features/entry/season_screen.dart';

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

const _strangerThings = 'shows/stranger-things-2016';

/// The fake standing in for AniList's chain episodes.
class _AniListFake extends FakeLookupSource {
  _AniListFake({super.splitsBySource});

  @override
  String get name => 'AniList';
}

void main() {
  final now = DateTime(2026, 10, 19, 12);

  setUp(() => seasonClock = () => now);
  tearDown(() => seasonClock = DateTime.now);

  Future<ProviderContainer> openDetails(
    WidgetTester tester, {
    FakeLookupSource? source,
    LookupFailure? failure,
  }) async {
    final container = await pumpApp(
      tester,
      const _Opener(_strangerThings),
      lookupOverrides: fakeLookupOverrides(source: source, failure: failure),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> openSeasonRow(WidgetTester tester, int season) async {
    final row = find.bySemanticsLabel(RegExp('^Season $season, .*Episodes\$'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('a season row opens its episodes, out on one day', (
    tester,
  ) async {
    await openDetails(tester);
    await openSeasonRow(tester, 1);
    expect(find.byType(SeasonScreen), findsOneWidget);
    expect(find.text('STRANGER THINGS'), findsOneWidget);
    expect(find.text('Season 1'), findsWidgets);
    expect(find.text('Jul 15, 2016 · 8 episodes'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(
      find.text('Chapter One: The Vanishing of Will Byers'),
      findsOneWidget,
    );
    // The date is in the header only.
    expect(find.text('47 min'), findsOneWidget);
    expect(find.textContaining('Jul 15 ·'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Episode details from TMDB.'),
      100,
    );
    expect(find.text('Episode details from TMDB.'), findsOneWidget);
  });

  testWidgets('an airing season: count out, dimmed rows, Title TBA', (
    tester,
  ) async {
    const List<EpisodeInfo> episodes = [
      (number: 1, title: 'Out One', aired: Released(2026, 10, 12), runtime: 22),
      (number: 2, title: 'Out Two', aired: Released(2026, 10, 19), runtime: 23),
      (number: 3, title: null, aired: Released(2026, 10, 26), runtime: null),
      (number: 4, title: null, aired: null, runtime: null),
    ];
    await openDetails(
      tester,
      source: FakeLookupSource(
        episodesBySeason: {('fake:stranger-things', 5): episodes},
      ),
    );
    await openSeasonRow(tester, 5);
    expect(
      find.text('Started Oct 12, 2026 · 2 of 4 episodes out'),
      findsOneWidget,
    );
    expect(find.text('Oct 12 · 22 min'), findsOneWidget);
    expect(find.text('Oct 19 · 23 min'), findsOneWidget);
    expect(find.text('Title TBA'), findsNWidgets(2));
    expect(find.text('Airs Oct 26'), findsOneWidget);
    expect(find.text('Air date not set'), findsOneWidget);
    final dimmed = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Airs Oct 26'),
        matching: find.byType(Opacity),
      ),
    );
    expect(dimmed.opacity, lessThan(1));
    final out = tester.widget<Opacity>(
      find.ancestor(of: find.text('Out One'), matching: find.byType(Opacity)),
    );
    expect(out.opacity, 1);
  });

  testWidgets('a one-season show\'s row opens its season', (tester) async {
    final container = await pumpApp(
      tester,
      const _Opener('shows/the-haunting-of-hill-house-2018'),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await openSeasonRow(tester, 1);
    expect(find.text('THE HAUNTING OF HILL HOUSE'), findsOneWidget);
    expect(find.text('Oct 12, 2018 · 10 episodes'), findsOneWidget);
    // The season screen keeps its own pill, which sets the show's status.
    await tester.tap(find.bySemanticsLabel(RegExp('^Season 1 status: done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DNF').last);
    await tester.pumpAndSettle();
    final saved =
        (container.read(libraryRepositoryProvider) as FixtureLibraryRepository)
            .current!
            .entryById('shows/the-haunting-of-hill-house-2018')!;
    expect(saved.status, EntryStatus.dnf);
  });

  testWidgets('the status pill opens the sheet, not the season', (
    tester,
  ) async {
    await openDetails(tester);
    final pill = find.bySemanticsLabel(RegExp('^Season 4 status: '));
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(find.byType(SeasonScreen), findsNothing);
    expect(find.text('Mark seasons 1–3 Done'), findsOneWidget);
  });

  testWidgets('the season screen\'s pill sets the season\'s status', (
    tester,
  ) async {
    final container = await openDetails(tester);
    await openSeasonRow(tester, 4);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Season 4 status: not set')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watching').last);
    await tester.pumpAndSettle();
    final saved = (container.read(
      libraryRepositoryProvider,
    ) as FixtureLibraryRepository).current!.entryById(_strangerThings)!;
    expect(saved.seasons![3].status, EntryStatus.inProgress);
    expect(find.byType(SeasonScreen), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Season 4 status: watching')),
      findsOneWidget,
    );
  });

  testWidgets('offline with nothing stored says so', (tester) async {
    await openDetails(tester, failure: LookupFailure.offline);
    await openSeasonRow(tester, 1);
    expect(find.text('The episodes need a connection.'), findsOneWidget);
    // The header falls back to the season's date.
    expect(find.text('Jul 15, 2016'), findsOneWidget);
  });

  testWidgets('a season with no episodes says so', (tester) async {
    await openDetails(tester);
    await openSeasonRow(tester, 2);
    expect(
      find.text('No episodes were found for this season.'),
      findsOneWidget,
    );
  });

  group('labels', () {
    final today = DateTime(2026, 10, 19);
    const season = Season(season: 2, released: Released(2026, 10, 30));

    test('the header before, while and after airing', () {
      List<EpisodeInfo> from(List<Released?> dates) => [
        for (final (i, d) in dates.indexed)
          (number: i + 1, title: 'T', aired: d, runtime: 22),
      ];
      expect(
        SeasonScreen.headerLine(
          season,
          from([const Released(2026, 10, 30), null]),
          today,
        ),
        'Coming Oct 30, 2026 · 2 episodes',
      );
      expect(
        SeasonScreen.headerLine(
          season,
          from([const Released(2026, 10, 1), const Released(2026, 10, 30)]),
          today,
        ),
        'Started Oct 1, 2026 · 1 of 2 episodes out',
      );
      expect(
        SeasonScreen.headerLine(
          season,
          from([const Released(2026, 10, 1)]),
          today,
        ),
        'Oct 1, 2026 · 1 episode',
      );
      expect(
        SeasonScreen.headerLine(season, null, today),
        'Coming Oct 30, 2026',
      );
    });

    test('an episode in another year carries its year', () {
      expect(
        SeasonScreen.shortDate(const Released(2027, 1, 5), 2026),
        'Jan 5, 2027',
      );
      expect(
        SeasonScreen.shortDate(const Released(2026, 10, 5), 2026),
        'Oct 5',
      );
    });

    test('an episode out without a title is numbered', () {
      expect(
        SeasonScreen.episodeTitle((
          number: 5,
          title: null,
          aired: const Released(2026, 1, 1),
          runtime: null,
        ), today),
        'Episode 5',
      );
    });
  });

  testWidgets('the credit names the provider the episodes came from', (
    tester,
  ) async {
    await openDetails(tester, source: _AniListFake());
    await openSeasonRow(tester, 1);
    await tester.scrollUntilVisible(
      find.text('Episode details from AniList.'),
      100,
    );
    expect(find.text('Episode details from AniList.'), findsOneWidget);
  });

  group('preloading (owner\'s request, 2026-11-03)', () {
    Iterable<String> episodeCalls(FakeLookupSource fake) =>
        fake.calls.where((c) => c.startsWith('episodes:'));

    testWidgets('the details preload the seasons they list', (tester) async {
      final fake = FakeLookupSource();
      await openDetails(tester, source: fake);
      expect(episodeCalls(fake), [
        for (var n = 1; n <= 5; n++) 'episodes:fake:stranger-things:$n',
      ]);
      // A season opened then comes from the phone: nothing fetched again
      // but its neighbor, season 2 (the fake has episodes for season 1
      // alone; a season with none is not stored, and asked again).
      await openSeasonRow(tester, 1);
      expect(find.byType(SeasonScreen), findsOneWidget);
      expect(find.text('Jul 15, 2016 · 8 episodes'), findsOneWidget);
      expect(episodeCalls(fake).skip(5), ['episodes:fake:stranger-things:2']);
    });

    testWidgets('a long show: the latest three, then all seasons the rows '
        'in view, then a season screen its neighbors', (tester) async {
      const show = 'fake:what-we-do-in-the-shadows';
      final episodes = {
        for (var n = 1; n <= 6; n++)
          (show, n): <EpisodeInfo>[
            (
              number: 1,
              title: 'Episode $n.1',
              aired: Released(2018 + n, 3, 1),
              runtime: 22,
            ),
          ],
      };
      final fake = FakeLookupSource(episodesBySeason: episodes);
      await pumpApp(
        tester,
        const _Opener('shows/what-we-do-in-the-shadows-2019'),
        lookupOverrides: fakeLookupOverrides(source: fake),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(episodeCalls(fake), [
        for (final n in [4, 5, 6]) 'episodes:$show:$n',
      ]);
      await tester.ensureVisible(find.text('All 6 seasons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All 6 seasons'));
      await tester.pumpAndSettle();
      // Every row is in view on the phone: the three not stored yet.
      expect(episodeCalls(fake).skip(3), [
        for (final n in [1, 2, 3]) 'episodes:$show:$n',
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Season 4's neighbors, 3 and 5, are both stored now: nothing more.
      await openSeasonRow(tester, 4);
      expect(episodeCalls(fake), hasLength(6));
    });

    testWidgets('a season screen preloads its neighbors', (tester) async {
      const show = 'fake:what-we-do-in-the-shadows';
      final fake = FakeLookupSource(
        episodesBySeason: {
          for (var n = 1; n <= 6; n++)
            (show, n): <EpisodeInfo>[
              (
                number: 1,
                title: 'Episode $n.1',
                aired: Released(2018 + n, 3, 1),
                runtime: 22,
              ),
            ],
        },
      );
      await pumpApp(
        tester,
        const _Opener('shows/what-we-do-in-the-shadows-2019'),
        lookupOverrides: fakeLookupOverrides(source: fake),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // The details stored 4 to 6; season 4's neighbor 3 is fetched, 5
      // is stored.
      await openSeasonRow(tester, 4);
      expect(episodeCalls(fake).skip(3), ['episodes:$show:3']);
    });
  });

  testWidgets('seasons in a split by arc take the arc names', (tester) async {
    const arcs = SeasonSplit(
      ids: ['tmdb:group:arcs'],
      arcs: true,
      seasons: [
        SeasonSpan(
          season: 1,
          name: 'Journey',
          episodes: 28,
          released: Released(2023, 9, 29),
        ),
        SeasonSpan(
          season: 2,
          name: 'North',
          episodes: 10,
          released: Released(2026, 1, 16),
        ),
      ],
    );
    // The fixture's Frieren has no lookup id: matched on the device to
    // the catalog's AniList id.
    final fake = _AniListFake(
      splitsBySource: {
        'anilist:154587': [arcs],
      },
    );
    await pumpApp(
      tester,
      const _Opener('anime/frieren-beyond-journeys-end-2023'),
      lookupOverrides: fakeLookupOverrides(source: fake),
      library: loadFixture().copyWith(
        entries: [
          for (final e in loadFixture().entries)
            if (e.id == 'anime/frieren-beyond-journeys-end-2023')
              e.copyWith(seasonsFrom: 'tmdb:group:arcs')
            else
              e,
        ],
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Journey'), findsOneWidget);
    expect(find.text('North'), findsOneWidget);
    expect(find.text('Season 1'), findsNothing);
    final row = find.bySemanticsLabel(RegExp(r'^North, .*Episodes$'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(SeasonScreen), findsOneWidget);
    expect(find.text('North'), findsOneWidget);
    expect(
      find.bySemanticsLabel('North status: watching. Change'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('North status: watching. Change'));
    await tester.pumpAndSettle();
    expect(find.text('North'), findsNWidgets(2));
  });
}
