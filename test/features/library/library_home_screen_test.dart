import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/series_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/series.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/features/music/music_tab.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/widgets/cover_placeholder.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/entry_list_views.dart';
import 'package:library_app/features/library/filter_sheet.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/features/library/home_return_provider.dart';
import 'package:library_app/features/library/home_sections.dart';
import 'package:library_app/features/library/home_type_provider.dart';
import 'package:library_app/features/library/library_filter.dart';
import 'package:library_app/features/library/library_filter_provider.dart';
import 'package:library_app/features/library/library_home_screen.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/library/tag_list_screen.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/tag_group.dart';
import 'package:library_app/widgets/entry_row.dart';
import 'package:library_app/widgets/labels.dart';
import 'package:library_app/widgets/segmented_control.dart';
import 'package:library_app/widgets/sheet_frame.dart';

import 'package:library_app/dev/long_lists.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

void main() {
  final fixture = loadFixture();
  List<String> visibleOf(MediaType type) => fixture
      .entriesOfType(type)
      .where((e) => !e.seasonalOnly)
      .map((e) => e.title)
      .toList();

  /// Scrolls the chip row (lazy, so a far chip is not built yet) and taps.
  Future<void> pickChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(PillChip, label);
    final row = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    // "Home" is the first chip, so scroll back toward it.
    final dx = label == 'Home' ? 80.0 : -80.0;
    await tester.dragUntilVisible(chip, row, Offset(dx, 0));
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Finder inSegments(String label) => find.descendant(
    of: find.byType(StatusSegmentedControl),
    matching: find.text(label),
  );

  /// The fixture as of October 11, 2026: the day the home tests look from, so
  /// Recently added (the last 30 days) has rows whatever today is.
  final homeDay = DateTime(2026, 10, 11);
  void fixHomeDay() {
    seasonClock = () => homeDay;
    addTearDown(() => seasonClock = DateTime.now);
  }

  testWidgets(
    'All: the plan, then Coming soon, In progress and Recently added',
    (tester) async {
      fixHomeDay();
      await pumpApp(tester, const LibraryHomeScreen());
      expect(find.text('ACTIVE PLAN'), findsOneWidget);
      expect(find.text('Halloween 2026'), findsOneWidget);
      expect(find.text('Search titles and tags'), findsOneWidget);
      expect(find.byType(StatusSegmentedControl), findsNothing);
      // No per-type headings or counts any more.
      expect(find.text('MOVIES'), findsNothing);
      expect(find.bySemanticsLabel('Show all movies'), findsNothing);

      final visible = fixture.entries.where((e) => !e.seasonalOnly).toList();
      final expected = homeSections(visible, today: homeDay);
      expect(expected.map((s) => s.kind), [
        HomeSectionKind.comingSoon,
        HomeSectionKind.inProgress,
        HomeSectionKind.recentlyAdded,
      ]);
      expect(find.text('COMING SOON'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      final going = expected[1];
      expect(find.text('See all ${going.total}'), findsOneWidget);
      final rows = tester.widgetList<HomeRow>(find.byType(HomeRow)).toList();
      // Coming soon: GTA VI's exact date before The Batman Part II's month.
      expect(rows[0].row.title, 'Grand Theft Auto VI');
      expect(rows[0].row.right, 'Nov 19');
      expect(rows[1].row.title, 'The Batman Part II');
      expect(rows[1].row.right, 'Oct 2027');
      expect(find.text('Game · Rockstar Games'), findsOneWidget);
      // In progress: newest added first with nothing changed on this phone.
      expect(
        rows.skip(2).take(going.rows.length).map((r) => r.row.id),
        going.rows.map((r) => r.id),
      );
      expect(find.text('Show · Season 2'), findsOneWidget);
      // Recently added: the newest in the fixture, added six days before, and
      // ten rows at most.
      final recent = expected[2];
      expect(recent.rows.length, lessThanOrEqualTo(HomeSection.limit));
      await tester.scrollUntilVisible(
        find.text('RECENTLY ADDED'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('RECENTLY ADDED'), findsOneWidget);
      expect(find.text('6 days ago'), findsOneWidget);
      expect(
        find.byKey(ValueKey('home-recentlyAdded-${recent.rows.first.id}')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a home row opens the entry; See all opens In progress results', (
    tester,
  ) async {
    fixHomeDay();
    Entry? opened;
    final container = await pumpApp(
      tester,
      LibraryHomeScreen(onOpenEntry: (e) => opened = e),
    );
    await tester.tap(find.byType(HomeRow).first);
    await tester.pumpAndSettle();
    expect(opened?.title, 'Grand Theft Auto VI');

    final going = fixture.entries
        .where((e) => !e.seasonalOnly && e.status == EntryStatus.inProgress)
        .length;
    await tester.tap(find.text('See all $going'));
    await tester.pumpAndSettle();
    expect(
      container.read(libraryFilterProvider),
      const LibraryFilter(statuses: {EntryStatus.inProgress}),
    );
    expect(container.read(homeTypeProvider), isNull);
    expect(find.bySemanticsLabel('Remove In progress'), findsOneWidget);
    expect(find.text('Clear all'), findsOneWidget);
    expect(find.text('$going entries'), findsOneWidget);
    expect(find.text('SHOWS'), findsOneWidget);
    expect(find.text('GAMES'), findsOneWidget);
    expect(find.byType(HomeRow), findsNothing);
    expect(find.byType(EntryRow), findsNWidgets(going));

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('IN PROGRESS'), findsOneWidget);
  });

  testWidgets('with nothing coming, going or new the home says so', (
    tester,
  ) async {
    fixHomeDay();
    final quiet = fixture.copyWith(
      entries: [
        for (final e in fixture.entries)
          if (e.status != EntryStatus.inProgress &&
              upcomingRelease(e, homeDay) == null)
            e.copyWith(added: DateTime(2025, 1, 1)),
      ],
    );
    await pumpApp(tester, const LibraryHomeScreen(), library: quiet);
    expect(find.text('ACTIVE PLAN'), findsOneWidget);
    expect(find.text(HomeNothingToShow.text), findsOneWidget);
    expect(find.byType(HomeRow), findsNothing);
    expect(find.text('Your library is empty'), findsNothing);
  });

  testWidgets('a return to the home clears the type, status and filter', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await pickChip(tester, 'Books');
    // Five segments scroll sideways at 360 dp.
    await tester.ensureVisible(inSegments('Done'));
    await tester.tap(inSegments('Done'));
    await tester.pumpAndSettle();
    expect(container.read(homeStatusProvider), EntryStatus.done);

    container.read(homeReturnProvider.notifier).goHome();
    await tester.pumpAndSettle();
    expect(container.read(homeTypeProvider), isNull);
    expect(container.read(homeStatusProvider), isNull);
    expect(find.byType(StatusSegmentedControl), findsNothing);
    // The chip row scrolled back to the start on its own, so All is in view.
    final row = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
    );
    expect(tester.state<ScrollableState>(row).position.pixels, 0);
    expect(
      tester.widget<PillChip>(find.widgetWithText(PillChip, 'Home')).selected,
      isTrue,
    );
    expect(find.widgetWithText(PillChip, 'Home').hitTestable(), findsOneWidget);

    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(tags: {'horror'}));
    await tester.pumpAndSettle();
    expect(find.byType(PillChip), findsNothing);
    container.read(homeReturnProvider.notifier).goHome();
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).isActive, isFalse);
    expect(find.widgetWithText(PillChip, 'Home'), findsOneWidget);
  });

  testWidgets('a return to the home scrolls All to the top', (tester) async {
    fixHomeDay();
    // Short enough that the All list scrolls.
    final container = await pumpApp(
      tester,
      const LibraryHomeScreen(),
      size: const Size(360, 420),
    );
    Finder allList() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    await tester.drag(find.byType(HomeRow).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(allList()).position.pixels,
      greaterThan(0),
    );

    container.read(homeReturnProvider.notifier).goHome();
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(allList()).position.pixels, 0);
  });

  testWidgets('a type chip shows that type in place with segments and count', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    // Shows: few enough that every row is on screen at once.
    await pickChip(tester, 'Shows');
    final shows = visibleOf(MediaType.shows);
    expect(container.read(homeTypeProvider), MediaType.shows);
    expect(find.text('MOVIES'), findsNothing);
    expect(find.text('SHOWS'), findsNothing);
    expect(find.text('ACTIVE PLAN'), findsNothing);
    expect(find.byType(StatusSegmentedControl), findsOneWidget);
    expect(find.text('${shows.length} shows'), findsOneWidget);
    expect(find.byType(EntryRow), findsNWidgets(shows.length));
    expect(find.text('Search shows'), findsOneWidget);
    expect(find.text('Newest added'), findsOneWidget);
    expect(find.byTooltip('Change view'), findsOneWidget);

    await pickChip(tester, 'Home');
    expect(container.read(homeTypeProvider), isNull);
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('ACTIVE PLAN'), findsOneWidget);
  });

  testWidgets(
    'the active plan card opens the plan (in place without a shell)',
    (tester) async {
      await pumpApp(tester, const LibraryHomeScreen());
      await tester.tap(find.text('Halloween 2026'));
      await tester.pumpAndSettle();
      expect(find.text('This plan'), findsOneWidget);
      expect(find.text('2 of 8 done'), findsOneWidget);
    },
  );

  group('the header scrolls with the list', () {
    Future<ProviderContainer> pumpLong(WidgetTester tester) => pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: padForLongLists(fixture, perType: 60),
    );

    testWidgets(
      'the title, search box, chips and segments scroll away; the count row pins',
      (tester) async {
        await pumpLong(tester);
        await pickChip(tester, 'Movies');
        expect(find.text('Library'), findsOneWidget);
        expect(find.byType(StatusSegmentedControl), findsOneWidget);
        await tester.drag(find.byType(EntryRow).first, const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(find.text('Library'), findsNothing);
        expect(find.text('Search movies'), findsNothing);
        expect(find.byType(PillChip), findsNothing);
        expect(find.byType(StatusSegmentedControl), findsNothing);
        // The count row sits at the top, with the sort and view buttons.
        final count = find.textContaining(RegExp(r'^\d+ movies$'));
        expect(tester.getTopLeft(count).dy, lessThan(30));
        expect(find.text('Newest added'), findsOneWidget);
        expect(find.byTooltip('Change view'), findsOneWidget);
        // The rail starts under the pinned row.
        expect(find.byKey(EntryListBody.railKey), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(EntryListBody.railKey)).dy,
          countRowExtent(TextScaler.noScaling),
        );
        // The pinned row still works: the sort sheet opens from it.
        await tester.tap(find.text('Newest added'));
        await tester.pumpAndSettle();
        expect(find.text('Title, A to Z'), findsOneWidget);
      },
    );

    testWidgets(
      'Library in the pill scrolls to the top first, then goes to All',
      (tester) async {
        final container = await pumpLong(tester);
        await pickChip(tester, 'Movies');
        final rail = find.byKey(EntryListBody.railKey);
        final railTopBefore = tester.getTopLeft(rail).dy;
        expect(railTopBefore, greaterThan(200));
        await tester.drag(find.byType(EntryRow).first, const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(find.text('Library'), findsNothing);

        container.read(homeReturnProvider.notifier).goHome();
        await tester.pumpAndSettle();
        // Back at the top, still on Movies.
        expect(find.text('Library'), findsOneWidget);
        expect(container.read(homeTypeProvider), MediaType.movies);
        expect(find.byType(StatusSegmentedControl), findsOneWidget);
        expect(tester.getTopLeft(rail).dy, railTopBefore);

        container.read(homeReturnProvider.notifier).goHome();
        await tester.pumpAndSettle();
        expect(container.read(homeTypeProvider), isNull);
        expect(find.byType(StatusSegmentedControl), findsNothing);
      },
    );

    testWidgets('a short list leaves the header where it is', (tester) async {
      await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Shows');
      await tester.drag(find.byType(EntryRow).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      // Eight shows and the header fit on one screen: nothing to scroll.
      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(StatusSegmentedControl), findsOneWidget);
    });

    testWidgets('a rail jump lands with the header out of the way', (
      tester,
    ) async {
      await pumpLong(tester);
      await pickChip(tester, 'Movies');
      await tester.tap(
        find
            .descendant(
              of: find.byKey(EntryListBody.railKey),
              matching: find.text('Oct'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsNothing);
      expect(find.text('OCTOBER 2026'), findsOneWidget);
    });
  });

  testWidgets('segments filter by status and reset when the type changes', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickChip(tester, 'Movies');
    await tester.tap(inSegments('Want'));
    await tester.pumpAndSettle();
    final wanted = fixture
        .entriesOfType(MediaType.movies)
        .where((e) => !e.seasonalOnly && e.status == EntryStatus.want)
        .length;
    expect(find.text('$wanted movies'), findsOneWidget);
    expect(find.byType(EntryRow), findsNWidgets(wanted));

    await pickChip(tester, 'Shows');
    final shows = visibleOf(MediaType.shows);
    expect(find.text('${shows.length} shows'), findsOneWidget);
  });

  testWidgets('a status nothing has shows a line, not the empty state', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: fixture.copyWith(
        entries: [
          ...fixture.entries.where((e) => e.type != MediaType.movies),
          mummy,
        ],
      ),
    );
    await pickChip(tester, 'Movies');
    await tester.tap(inSegments('DNF'));
    await tester.pumpAndSettle();
    expect(find.text('0 movies'), findsOneWidget);
    expect(find.text('Nothing marked DNF yet.'), findsOneWidget);
    expect(find.byType(EntryRow), findsNothing);
  });

  testWidgets('the sort sheet changes the order and is remembered per type', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await pickChip(tester, 'Movies');
    await tester.tap(find.text('Newest added'));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    // Library › Sort menu lists the rating order last.
    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SheetFrame),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => LibrarySort.values.any((s) => s.label == t))
        .toList();
    expect(labels.last, 'Rating, highest first');
    await tester.tap(find.text('Title, A to Z'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<EntryRow>(find.byType(EntryRow))
        .map((r) => r.title)
        .toList();
    expect(rows.first, 'Amélie');
    expect(
      container.read(displayPreferencesProvider).sortFor(MediaType.movies),
      LibrarySort.titleAz,
    );
    expect(
      container.read(displayPreferencesProvider).sortFor(MediaType.books),
      LibrarySort.newestAdded,
    );
  });

  testWidgets(
    'the view menu switches to covers and the grid, remembered per type',
    (tester) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Movies');
      expect(find.byType(CoverPlaceholder), findsNothing);

      await tester.tap(find.byTooltip('Change view'));
      await tester.pumpAndSettle();
      expect(find.text('VIEW'), findsOneWidget);
      await tester.tap(find.text('List with covers'));
      await tester.pumpAndSettle();
      expect(find.byType(CoverPlaceholder), findsWidgets);
      expect(find.byType(EntryRow), findsWidgets);

      await tester.tap(find.byTooltip('Change view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grid with covers'));
      await tester.pumpAndSettle();
      expect(find.byType(CoverGridTile), findsWidgets);
      expect(find.bySemanticsLabel('Done'), findsWidgets);
      expect(
        container.read(displayPreferencesProvider).viewFor(MediaType.movies),
        EntryView.grid,
      );
      expect(
        container.read(displayPreferencesProvider).viewFor(MediaType.shows),
        EntryView.text,
      );
    },
  );

  testWidgets('music has artist tabs instead of status segments', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickChip(tester, 'Music');
    expect(find.byType(StatusSegmentedControl), findsNothing);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Search music'), findsOneWidget);
  });

  testWidgets('an empty type shows its empty state', (tester) async {
    await pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: fixture.copyWith(
        entries: fixture.entries
            .where((e) => e.type != MediaType.music)
            .toList(),
      ),
    );
    await pickChip(tester, 'Music');
    expect(find.text('No music yet'), findsOneWidget);
    expect(
      find.text('Albums and songs you add will show up here.'),
      findsOneWidget,
    );
    expect(find.text('Add music'), findsOneWidget);
    expect(find.byType(StatusSegmentedControl), findsNothing);
  });

  testWidgets('an active filter shows removable chips, a count and results', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(types: {MediaType.shows}, tags: {'horror'}));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Remove Shows'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove #horror'), findsOneWidget);
    expect(find.text('Clear all'), findsOneWidget);
    expect(find.text('ACTIVE PLAN'), findsNothing);
    expect(find.byType(PillChip), findsNothing);
    expect(find.textContaining(RegExp(r'^\d+ entr')), findsOneWidget);
    expect(find.text('SHOWS'), findsOneWidget);
    expect(find.text('MOVIES'), findsNothing);
    expect(find.text('2'), findsOneWidget); // The badge on the filter button.

    await tester.tap(find.bySemanticsLabel('Remove Shows'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).types, isEmpty);
    expect(find.text('MOVIES'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider), LibraryFilter.none);
    expect(find.text('ACTIVE PLAN'), findsOneWidget);
  });

  testWidgets(
    'the filter sheet lists tags A to Z; a long group is a row that opens its full list',
    (tester) async {
      // Twenty-five authors make a long group; genres stay inline chips.
      final authors = [
        for (var i = 0; i < 25; i++) 'author-${String.fromCharCode(0x61 + i)}',
      ];
      final library = fixture.copyWith(
        tags: {...fixture.tags, TagCategory.authors: authors},
        entries: [
          ...fixture.entries,
          for (final (i, tag) in authors.indexed)
            fixture.entries.first.copyWith(
              id: 'books/author-$i',
              type: MediaType.books,
              title: 'Book $i',
              tags: [tag],
            ),
        ],
      );
      final container = await pumpApp(
        tester,
        const LibraryHomeScreen(),
        library: library,
      );
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      // Genres are inline, A to Z (the fixture stores them unsorted).
      await tester.scrollUntilVisible(
        find.text('Genres'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      final adventure = tester.getTopLeft(
        find.widgetWithText(PillChip, '#adventure'),
      );
      final horror = tester.getTopLeft(
        find.widgetWithText(PillChip, '#horror'),
      );
      expect(adventure.dy <= horror.dy, isTrue);
      expect(find.widgetWithText(PillChip, '#author-a'), findsNothing);
      final row = find.bySemanticsLabel('Authors, 25 authors');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(TagListScreen), findsOneWidget);
      expect(find.text('25 authors'), findsOneWidget);
      await tester.tap(find.text('Author B'));
      await tester.pumpAndSettle();
      expect(find.text('25 authors · 1 selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      // Back on the sheet, the row and the count know about the pick.
      expect(
        find.bySemanticsLabel('Authors, 25 authors · 1 selected'),
        findsOneWidget,
      );
      expect(find.text('Show 1 entry'), findsOneWidget);
      await tester.tap(find.text('Show 1 entry'));
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider).tags, {'author-b'});
      // A search shows a long group's matches inline.
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'author-c');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PillChip, '#author-c'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Authors, 25 authors · 1 selected'),
        findsNothing,
      );
    },
  );

  testWidgets('a filter nothing matches shows the empty state', (tester) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(tags: {'horror', 'cozy', 'jazz'}));
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches these filters'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).isEmpty, isTrue);
  });

  testWidgets('the filter sheet applies a filter', (tester) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillChip, 'Games'));
    await tester.tap(find.widgetWithText(PillChip, 'Want'));
    await tester.tap(find.widgetWithText(PillChip, 'Done'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).types, {MediaType.games});
    expect(find.text('GAMES'), findsOneWidget);
  });

  testWidgets('a lone type filter opens that type instead of results', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillChip, 'Games'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).isActive, isFalse);
    expect(container.read(homeTypeProvider), MediaType.games);
  });

  group('the filter sheet and the home stay in sync', () {
    Finder sheetChip(String label) => find.descendant(
      of: find.byType(FilterSheet),
      matching: find.widgetWithText(PillChip, label),
    );
    bool selected(WidgetTester tester, String label) =>
        tester.widget<PillChip>(sheetChip(label)).selected;

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
    }

    Future<void> show(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(FilterSheet),
          matching: find.textContaining('Show '),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('it opens with the picked type chosen, and none on All', (
      tester,
    ) async {
      await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Movies');
      await openSheet(tester);
      expect(selected(tester, 'Movies'), isTrue);
      expect(selected(tester, 'Music'), isFalse);
      // Movies are never in progress, so the sheet does not offer it.
      expect(sheetChip('In progress'), findsNothing);
      expect(sheetChip('DNF'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20)); // Dismiss.
      await tester.pumpAndSettle();

      await pickChip(tester, 'Home');
      await openSheet(tester);
      for (final type in MediaType.values) {
        expect(selected(tester, type.label), isFalse);
      }
      expect(sheetChip('In progress'), findsOneWidget);
    });

    testWidgets('a tag in several categories is chosen per category', (
      tester,
    ) async {
      await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Movies');
      await openSheet(tester);
      Finder inGroup(String group, String tag) => find.descendant(
        of: find.widgetWithText(TagGroup, group),
        matching: find.widgetWithText(PillChip, tag),
      );
      await tester.scrollUntilVisible(
        find.text('Directors'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(FilterSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Directors'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inGroup('Directors', '#clint-eastwood'));
      await tester.pumpAndSettle();
      await tester.tap(inGroup('Directors', '#clint-eastwood'));
      await tester.pumpAndSettle();
      expect(find.text('Show 1 entry'), findsOneWidget); // Not a type view.
      // Ticked as the director only: the Actors group does not show it.
      await tester.ensureVisible(find.text('Actors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actors'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inGroup('Actors', '#clint-eastwood'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PillChip>(inGroup('Actors', '#clint-eastwood')).selected,
        isFalse,
      );
      await show(tester);
      expect(find.text('Million Dollar Baby'), findsOneWidget);
      expect(find.text('The Good, the Bad and the Ugly'), findsNothing);
      expect(
        find.bySemanticsLabel('Remove #clint-eastwood · Director'),
        findsOneWidget,
      );
    });

    testWidgets('it opens with the picked status segment chosen too', (
      tester,
    ) async {
      await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Movies');
      await tester.tap(inSegments('Done'));
      await tester.pumpAndSettle();
      await openSheet(tester);
      expect(selected(tester, 'Movies'), isTrue);
      expect(selected(tester, 'Done'), isTrue);
      expect(selected(tester, 'Want'), isFalse);
      final done = fixture
          .entriesOfType(MediaType.movies)
          .where((e) => !e.seasonalOnly && e.status == EntryStatus.done)
          .length;
      expect(find.text('Show ${countLabel(MediaType.movies, done)}'), findsOne);
    });

    testWidgets('one type and one status is the type view, not results', (
      tester,
    ) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      await openSheet(tester);
      await tester.tap(sheetChip('Books'));
      await tester.tap(sheetChip('Done'));
      await tester.pumpAndSettle();
      await show(tester);
      expect(container.read(libraryFilterProvider).isActive, isFalse);
      expect(container.read(homeTypeProvider), MediaType.books);
      expect(container.read(homeStatusProvider), EntryStatus.done);
      expect(
        tester
            .widget<StatusSegmentedControl>(find.byType(StatusSegmentedControl))
            .selected,
        EntryStatus.done,
      );
    });

    testWidgets('removing the extra filter returns to the type view', (
      tester,
    ) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Books');
      // Five segments scroll sideways at 360 dp.
      await tester.ensureVisible(inSegments('Done'));
      await tester.tap(inSegments('Done'));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.tap(sheetChip('Want'));
      await tester.pumpAndSettle();
      await show(tester);
      expect(container.read(libraryFilterProvider).statuses, {
        EntryStatus.want,
        EntryStatus.done,
      });

      // Removing Want leaves Books + Done: the books view, Done picked.
      await tester.tap(find.bySemanticsLabel('Remove Want'));
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider).isActive, isFalse);
      expect(container.read(homeTypeProvider), MediaType.books);
      expect(container.read(homeStatusProvider), EntryStatus.done);
    });

    Future<void> pickMusicTab(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedControl<MusicTab>),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Kind shows only with Music chosen', (tester) async {
      await pumpApp(tester, const LibraryHomeScreen());
      await openSheet(tester);
      expect(find.text('KIND'), findsNothing);
      await tester.tap(sheetChip('Music'));
      await tester.pumpAndSettle();
      expect(find.text('KIND'), findsOneWidget);
      await tester.tap(sheetChip('Songs'));
      await tester.tap(sheetChip('Music'));
      await tester.pumpAndSettle();
      expect(find.text('KIND'), findsNothing);
      // Unticking Music drops Songs too: nothing is chosen.
      final all = fixture.entries.where((e) => !e.seasonalOnly).length;
      expect(find.text('Show $all entries'), findsOneWidget);
    });

    testWidgets('the music tab and the kind follow each other', (tester) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Music');

      // Artists: Music only, no kind.
      await openSheet(tester);
      expect(selected(tester, 'Music'), isTrue);
      expect(selected(tester, 'Albums'), isFalse);
      expect(selected(tester, 'Songs'), isFalse);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Songs: Music + Songs, and back again lands on Songs (Library › Music:
      // songs (filter result)).
      await pickMusicTab(tester, 'Songs');
      await openSheet(tester);
      expect(selected(tester, 'Songs'), isTrue);
      expect(selected(tester, 'Albums'), isFalse);
      expect(find.text('Show 2 songs'), findsOneWidget);
      await tester.tap(sheetChip('Songs'));
      await tester.tap(sheetChip('Albums'));
      await tester.pumpAndSettle();
      await show(tester);

      // Music + Albums is the Albums tab, not results (Library › Music: albums
      // (filter result)).
      expect(container.read(libraryFilterProvider).isActive, isFalse);
      expect(container.read(homeTypeProvider), MediaType.music);
      expect(container.read(homeMusicTabProvider), MusicTab.albums);

      // Music alone goes to Artists.
      container
          .read(libraryFilterProvider.notifier)
          .set(const LibraryFilter(types: {MediaType.music}));
      await tester.pumpAndSettle();
      expect(container.read(homeMusicTabProvider), MusicTab.artists);
    });

    testWidgets('Music with both kinds is results', (tester) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      container
          .read(libraryFilterProvider.notifier)
          .set(
            const LibraryFilter(
              types: {MediaType.music},
              kinds: {EntryKind.album, EntryKind.song},
            ),
          );
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider).isActive, isTrue);
      expect(find.text('Albums'), findsOneWidget); // Its removable chip.
    });

    testWidgets('music with a status is results: music has no segments', (
      tester,
    ) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      container
          .read(libraryFilterProvider.notifier)
          .set(
            const LibraryFilter(
              types: {MediaType.music},
              statuses: {EntryStatus.done},
            ),
          );
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider).isActive, isTrue);
      expect(container.read(homeTypeProvider), MediaType.music);
    });

    testWidgets('dropping the type in the sheet takes the home to All', (
      tester,
    ) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Movies');
      await openSheet(tester);
      await tester.tap(sheetChip('Movies'));
      await tester.tap(sheetChip('Want'));
      await tester.pumpAndSettle();
      await show(tester);
      expect(container.read(homeTypeProvider), isNull);
      container.read(libraryFilterProvider.notifier).clear();
      await tester.pumpAndSettle();
      expect(find.text('Search titles and tags'), findsOneWidget);
    });

    testWidgets('Clear all clears the type and the status too', (tester) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      await pickChip(tester, 'Shows');
      // Five segments scroll sideways at 360 dp.
      await tester.ensureVisible(inSegments('Done'));
      await tester.tap(inSegments('Done'));
      await tester.pumpAndSettle();
      await openSheet(tester);
      await tester.tap(sheetChip('Want'));
      await tester.pumpAndSettle();
      await show(tester);
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider).isActive, isFalse);
      expect(container.read(homeTypeProvider), isNull);
      expect(container.read(homeStatusProvider), isNull);
    });
  });

  testWidgets('a filter with no matches spells itself out', (tester) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    container
        .read(libraryFilterProvider.notifier)
        .set(
          const LibraryFilter(
            types: {MediaType.books},
            statuses: {EntryStatus.inProgress},
            tags: {'christmas'},
          ),
        );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No books are both in progress and tagged #christmas. '
        'Remove a filter to see more.',
      ),
      findsOneWidget,
    );
    expect(find.text('Clear all'), findsNothing);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).isActive, isFalse);
  });

  testWidgets('search can pick a tag, which filters the home', (tester) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await tester.tap(find.text('Search titles and tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ghib');
    await tester.pumpAndSettle();
    expect(find.text('#studio-ghibli'), findsOneWidget);
    expect(find.text('Tagged #studio-ghibli'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('#studio-ghibli'));
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).tags, {'studio-ghibli'});
    expect(find.text('ANIME'), findsOneWidget);
  });

  testWidgets('with a type picked, search covers only that type', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await pickChip(tester, 'Movies');
    await tester.tap(find.text('Search movies'));
    await tester.pumpAndSettle();
    expect(find.text('Search movies'), findsOneWidget); // The field's hint.
    await tester.enterText(find.byType(TextField), 'ghib');
    await tester.pumpAndSettle();
    expect(find.text('#studio-ghibli'), findsNothing); // Only anime has it.
    expect(find.text('No results for "ghib"'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hallow');
    await tester.pumpAndSettle();
    expect(find.text('#halloween'), findsOneWidget);
    await tester.tap(find.text('#halloween'));
    await tester.pumpAndSettle();
    expect(
      container.read(libraryFilterProvider),
      const LibraryFilter(types: {MediaType.movies}, tags: {'halloween'}),
    );
    expect(find.text('MOVIES'), findsOneWidget);
    expect(find.text('SHOWS'), findsNothing);
  });

  testWidgets('search shows an empty state for no results', (tester) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await tester.tap(find.text('Search titles and tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zelda');
    await tester.pumpAndSettle();
    expect(find.text('No results for "zelda"'), findsOneWidget);
    expect(find.text('Add "zelda"'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryHomeScreen), findsOneWidget);
  });

  testWidgets('an empty library shows an empty state', (tester) async {
    await pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: fixture.copyWith(entries: [], plans: []),
    );
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('seasonal-only entries appear only when included', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await pickChip(tester, 'Shows');
    expect(find.text('Over the Garden Wall'), findsNothing);
    container
        .read(libraryFilterProvider.notifier)
        .set(
          const LibraryFilter(
            types: {MediaType.shows},
            includeSeasonalOnly: true,
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('Over the Garden Wall'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Remove Seasonal-only included'),
      findsOneWidget,
    );
  });

  group('long filtered results', () {
    final long = padForLongLists(fixture);

    testWidgets('several types: type sections and a rail of dots', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        const LibraryHomeScreen(),
        library: long,
      );
      container
          .read(libraryFilterProvider.notifier)
          .set(const LibraryFilter(types: {MediaType.movies, MediaType.shows}));
      await tester.pumpAndSettle();
      expect(find.text('MOVIES'), findsOneWidget);
      expect(find.byKey(EntryListBody.railKey), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-dot-Movies')), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-dot-Shows')), findsOneWidget);
      expect(find.text('20s'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('rail-dot-Shows')));
      await tester.pumpAndSettle();
      expect(find.text('SHOWS'), findsOneWidget);
      expect(tester.getTopLeft(find.text('SHOWS')).dy, lessThan(400));
    });

    testWidgets('one type: sections follow the sort, rail of labels', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        const LibraryHomeScreen(),
        library: long,
      );
      container
          .read(libraryFilterProvider.notifier)
          .set(
            // A lone type filter would be the type view, so add one more.
            const LibraryFilter(
              types: {MediaType.movies},
              includeSeasonalOnly: true,
            ),
          );
      container
          .read(displayPreferencesProvider.notifier)
          .setFilteredSort(LibrarySort.yearNewest);
      await tester.pumpAndSettle();
      expect(find.text('MOVIES'), findsNothing);
      expect(find.text('2020s'), findsOneWidget);
      expect(find.text('20s'), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-dot-Movies')), findsNothing);
      // With the chip row hidden, search is not scoped to a chip.
      container.read(homeTypeProvider.notifier).set(MediaType.books);
      await tester.pumpAndSettle();
      expect(find.text('Search titles and tags'), findsOneWidget);
    });

    testWidgets('a short filtered list keeps type headings and no rail', (
      tester,
    ) async {
      final container = await pumpApp(tester, const LibraryHomeScreen());
      container
          .read(libraryFilterProvider.notifier)
          .set(
            // A lone type filter would be the type view, so add one more.
            const LibraryFilter(
              types: {MediaType.movies},
              includeSeasonalOnly: true,
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('MOVIES'), findsOneWidget);
      expect(find.byKey(EntryListBody.railKey), findsNothing);
    });
  });

  testWidgets(
    'Coming soon lists a part of a followed series not in the library, and opens its series page',
    (tester) async {
      fixHomeDay();
      const gollum = UpcomingPart(
        type: MediaType.movies,
        seriesName: 'The Lord of the Rings',
        entryId: 'movies/the-lord-of-the-rings-the-fellowship-of-the-ring-2001',
        title: 'The Lord of the Rings: The Hunt for Gollum',
        released: Released(2027, 12, 17),
        number: 4,
        source: 'fake:the-lord-of-the-rings-the-hunt-for-gollum',
      );
      await pumpApp(
        tester,
        const LibraryHomeScreen(),
        lookupOverrides: fakeLookupOverrides(
          upcomingParts: MemoryUpcomingPartsStore(const [gollum]),
        ),
      );
      final row = find.byKey(
        const ValueKey(
          'home-comingSoon-part:fake:the-lord-of-the-rings-the-hunt-for-gollum',
        ),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('The Hunt for Gollum')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('Movie · The Lord of the Rings'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Dec 17, 2027')),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(AllSeriesScreen), findsOneWidget);
      expect(find.text('4 movies · 2 in your library'), findsOneWidget);
    },
  );
}
