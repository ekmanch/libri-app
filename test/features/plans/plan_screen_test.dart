import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/plans/plan_entry_sheet.dart';
import 'package:library_app/features/plans/plan_progress.dart';
import 'package:library_app/features/plans/plan_screen.dart';
import 'package:library_app/features/plans/plan_timeline.dart';
import 'package:library_app/features/plans/seasonal_art.dart';
import 'package:library_app/features/plans/when_sheet.dart';
import 'package:library_app/features/shell/fab_action.dart';
import 'package:library_app/features/shell/floating_nav_bar.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/app_buttons.dart';
import 'package:library_app/widgets/chips.dart';

import '../../helpers/fonts.dart';
import '../../helpers/pump_app.dart';

void main() {
  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Future<ProviderContainer> open(WidgetTester tester, String planId) =>
      pumpApp(tester, PlanScreen(planId: planId, tab: ShellTab.plans));

  Finder check(String title) =>
      find.byWidgetPredicate((w) => w is PlanCheck && w.title == title);

  group('checklist', () {
    testWidgets('groups by type, with progress, tabs and the year chip', (
      tester,
    ) async {
      final container = await open(tester, 'christmas-2026');
      expect(find.text('Christmas'), findsOneWidget);
      expect(find.bySemanticsLabel('Choose year'), findsOneWidget);
      expect(find.text('0 of 6 done'), findsOneWidget);
      expect(find.text('This plan'), findsOneWidget);
      expect(find.text('All Christmas'), findsOneWidget);
      expect(find.text('MOVIES'), findsOneWidget);
      expect(find.text('BOOKS'), findsOneWidget);
      expect(find.text('Die Hard'), findsOneWidget);
      expect(find.textContaining('Rewatch'), findsWidgets);
      expect(find.byKey(const Key('timeline-today')), findsNothing);
      // The "+" button is claimed for the pool.
      expect(
        container.read(fabActionProvider)?.label,
        'Add from All Christmas',
      );
    });

    testWidgets('the check marks the item and the entry done', (tester) async {
      final container = await open(tester, 'christmas-2026');
      await tester.tap(check('Klaus'));
      await tester.pumpAndSettle();
      final library = repo(container).current!;
      final plan = library.planById('christmas-2026')!;
      expect(plan.itemFor('movies/klaus-2019')!.done, isTrue);
      expect(library.entryById('movies/klaus-2019')!.status, EntryStatus.done);
      expect(find.text('1 of 6 done'), findsOneWidget);
      await tester.tap(check('Klaus'));
      await tester.pumpAndSettle();
      expect(
        repo(container).current!
            .planById('christmas-2026')!
            .itemFor('movies/klaus-2019')!
            .done,
        isFalse,
      );
    });

    testWidgets('ticking a show marks its aired seasons; unticking undoes', (
      tester,
    ) async {
      const id = 'shows/over-the-garden-wall-2014';
      final fixture = loadFixture();
      const seasons = [
        Season(season: 1, released: Released(2014), status: EntryStatus.done),
        Season(season: 2, released: Released(2015)),
        Season(season: 3, released: Released(2099), status: EntryStatus.want),
      ];
      final show = fixture
          .entryById(id)!
          .copyWith(status: EntryStatus.done, seasons: seasons);
      final container = await pumpApp(
        tester,
        PlanScreen(planId: 'halloween-2026', tab: ShellTab.plans),
        library: fixture.copyWith(
          entries: [for (final e in fixture.entries) e.id == id ? show : e],
        ),
      );
      await tester.ensureVisible(check('Over the Garden Wall'));
      await tester.pumpAndSettle();
      await tester.tap(check('Over the Garden Wall'));
      await tester.pumpAndSettle();
      // Already Done by its seasons: ticking leaves it as it is.
      expect(repo(container).current!.entryById(id)!.seasons, seasons);
      await tester.tap(check('Over the Garden Wall'));
      await tester.pumpAndSettle();

      final watching = show.copyWith(
        status: EntryStatus.inProgress,
        seasons: [
          seasons[0],
          seasons[1].copyWith(status: EntryStatus.inProgress),
          seasons[2],
        ],
      );
      await repo(container).apply(UpdateEntry(watching));
      await tester.pumpAndSettle();
      await tester.tap(check('Over the Garden Wall'));
      await tester.pumpAndSettle();
      final ticked = repo(container).current!.entryById(id)!;
      expect(
        [for (final s in ticked.seasons!) s.status],
        [EntryStatus.done, EntryStatus.done, EntryStatus.want],
      );
      expect(ticked.status, EntryStatus.done);
      await tester.tap(check('Over the Garden Wall'));
      await tester.pumpAndSettle();
      final unticked = repo(container).current!.entryById(id)!;
      expect(unticked.seasons, watching.seasons);
      expect(unticked.status, EntryStatus.inProgress);
    });

    testWidgets('a row opens the entry in the plan', (tester) async {
      await open(tester, 'christmas-2026');
      await tester.tap(find.text('Die Hard'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanEntrySheet), findsOneWidget);
      expect(find.text('Mark as done'), findsOneWidget);
      expect(find.text('When'), findsNothing); // No timeline on this plan.
    });
  });

  for (final (planId, name) in const [
    ('halloween-2026', 'Halloween'),
    ('christmas-2026', 'Christmas'),
  ]) {
    testWidgets('$name fits in full on a narrow phone', (tester) async {
      // Real glyph widths: the test font's square glyphs would never fit.
      await loadAppFonts();
      await pumpApp(
        tester,
        PlanScreen(planId: planId, tab: ShellTab.plans),
        size: const Size(360, 780),
      );
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isFalse);
      // Short names keep the full size now that the year chip has moved.
      expect(tester.widget<Text>(find.text(name)).style!.fontSize, 32);
    });
  }

  testWidgets('at text scale 1.3 the name still fits on one line', (
    tester,
  ) async {
    await loadAppFonts();
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester,
      const PlanScreen(planId: 'halloween-2026', tab: ShellTab.plans),
      size: const Size(360, 780),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Halloween'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.widget<Text>(find.text('Halloween')).maxLines, 1);
  });

  testWidgets('a longer name steps down, the longest is cut off', (
    tester,
  ) async {
    await loadAppFonts();
    final fixture = loadFixture();
    Future<Text> titled(String name) async {
      await pumpApp(
        tester,
        const PlanScreen(planId: 'christmas-2026', tab: ShellTab.plans),
        size: const Size(360, 780),
        library: fixture.copyWith(
          plans: [
            for (final p in fixture.plans)
              p.id == 'christmas-2026' ? p.copyWith(name: name) : p,
          ],
        ),
      );
      return tester.widget<Text>(find.text(name));
    }

    final medium = await titled('Christmas classics');
    expect(medium.style!.fontSize, anyOf(28, 24));
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Christmas classics'))
          .didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('the longest names are cut off at the smallest size', (
    tester,
  ) async {
    await loadAppFonts();
    final fixture = loadFixture();
    const name = 'Christmas movies, books and albums for the whole family';
    await pumpApp(
      tester,
      const PlanScreen(planId: 'christmas-2026', tab: ShellTab.plans),
      size: const Size(360, 780),
      library: fixture.copyWith(
        plans: [
          for (final p in fixture.plans)
            p.id == 'christmas-2026' ? p.copyWith(name: name) : p,
        ],
      ),
    );
    final text = tester.widget<Text>(find.text(name));
    expect(text.style!.fontSize, 24);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      tester.renderObject<RenderParagraph>(find.text(name)).didExceedMaxLines,
      isTrue,
    );
  });

  testWidgets('ticking the last entry finishes the plan, with Undo', (
    tester,
  ) async {
    final fixture = loadFixture();
    final halloween = fixture.planById('halloween-2026')!;
    final one = halloween.copyWith(
      id: 'one',
      name: 'Movie night',
      year: null,
      started: false,
      timeline: false,
      seasonalTheme: false,
      tags: [],
      items: [halloween.items.firstWhere((i) => !i.done)],
    );
    final container = await pumpApp(
      tester,
      Scaffold(
        body: PlanScreen(planId: 'one', tab: ShellTab.plans),
      ),
      library: fixture.copyWith(plans: [one]),
    );
    final title = fixture.entryById(one.items.single.entry)!.title;
    await tester.tap(check(title));
    await tester.pumpAndSettle();
    final ticked = repo(container).current!.planById('one')!;
    expect(ticked.started, isTrue);
    expect(planState(ticked), PlanState.finished);
    expect(find.text('Movie night finished'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final undone = repo(container).current!.planById('one')!;
    expect(undone.items.single.done, isFalse);
    // Unticking leaves it active, not back to not started.
    expect(planState(undone), PlanState.active);
  });

  group('timeline', () {
    testWidgets('dated groups with the rail and today, then Whenever', (
      tester,
    ) async {
      await open(tester, 'halloween-2026');
      expect(find.text('Halloween'), findsOneWidget);
      expect(find.text('MOVIE'), findsWidgets);
      // The buckets depend on today's date; the widget shows what the
      // grouping (tested on its own in plan_logic_test) returns.
      final plan = loadFixture().planById('halloween-2026')!;
      final groups = timelineGroups(plan);
      expect(find.text(groups.first.title), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Whenever'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No date'), findsOneWidget);
      expect(find.text('Hereditary'), findsOneWidget);
      expect(
        find.byKey(const Key('timeline-today')),
        groups.any((g) => g.state == TimelineState.current)
            ? findsOneWidget
            : findsNothing,
      );
    });

    testWidgets('the rail is one continuous line through the gaps', (
      tester,
    ) async {
      await open(tester, 'halloween-2026');
      final rails = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_RailPainter',
      );
      expect(rails, findsAtLeastNWidgets(3));
      final rects = [for (var i = 0; i < 3; i++) tester.getRect(rails.at(i))];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, closeTo(rects[i - 1].bottom, 0.01));
        expect(rects[i].left, rects[i - 1].left);
      }
    });

    testWidgets('the entry sheet has a When row that opens the picker', (
      tester,
    ) async {
      final container = await open(tester, 'halloween-2026');
      await tester.scrollUntilVisible(
        find.text('Hereditary'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hereditary'));
      await tester.pumpAndSettle();
      expect(find.text('When'), findsOneWidget);
      await tester.tap(find.text('When'));
      await tester.pumpAndSettle();
      expect(find.text('Selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(PillChip, 'No date'));
      await tester.pump();
      expect(find.text('No date (Whenever)'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Sat Oct 17'));
      await tester.tap(find.bySemanticsLabel('Sat Oct 31'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(WhenSheet),
          matching: find.text('Oct 17–31'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      final item = repo(container).current!
          .planById('halloween-2026')!
          .itemFor('movies/hereditary-2018')!;
      expect(item.when!.from, DateTime(2026, 10, 17));
      expect(item.when!.to, DateTime(2026, 10, 31));
      expect(
        find.descendant(
          of: find.byType(PlanEntrySheet),
          matching: find.text('Oct 17–31'),
        ),
        findsOneWidget,
      );
    });
  });

  group('seasonal theme', () {
    testWidgets('Halloween: orange accent, strip, web, icon and marker', (
      tester,
    ) async {
      await open(tester, 'halloween-2026');
      final context = tester.element(find.text('Halloween'));
      expect(
        Theme.of(context).colorScheme.primaryContainer,
        SeasonalAccents.halloween,
      );
      expect(find.byType(SeasonalArtView), findsNWidgets(4));
    });

    testWidgets('Christmas: green accent, strip, icon and marker', (
      tester,
    ) async {
      await open(tester, 'christmas-2026');
      final xmas = tester.element(find.text('Christmas'));
      expect(
        Theme.of(xmas).colorScheme.primaryContainer,
        SeasonalAccents.christmas,
      );
      expect(find.byType(SeasonalArtView), findsNWidgets(3));
    });

    testWidgets('with the theme off the plan looks like any other', (
      tester,
    ) async {
      final fixture = loadFixture();
      await pumpApp(
        tester,
        const PlanScreen(planId: 'halloween-2026', tab: ShellTab.plans),
        library: fixture.copyWith(
          plans: [
            for (final p in fixture.plans)
              p.id == 'halloween-2026' ? p.copyWith(seasonalTheme: false) : p,
          ],
        ),
      );
      expect(find.byType(SeasonalArtView), findsNothing);
      final context = tester.element(find.text('Halloween'));
      expect(
        Theme.of(context).colorScheme.primaryContainer,
        Accents.defaultAccent.fill,
      );
    });
  });

  group('pool', () {
    testWidgets('lists everything with the tag, adds and removes', (
      tester,
    ) async {
      final container = await open(tester, 'christmas-2026');
      await tester.tap(find.text('All Christmas'));
      await tester.pumpAndSettle();
      expect(container.read(fabActionProvider)?.label, 'New Christmas entry');
      // The progress row stays on the pool tab too.
      expect(find.text('0 of 6 done'), findsOneWidget);
      expect(find.text('The Nightmare Before Christmas'), findsOneWidget);
      expect(find.textContaining('only in Christmas'), findsWidgets);
      expect(
        find.bySemanticsLabel('Add to plan: The Nightmare Before Christmas'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Remove from plan: Die Hard'),
        findsOneWidget,
      );
      expect(find.text('In 2026'), findsWidgets);

      await tester.tap(
        find.bySemanticsLabel('Add to plan: The Nightmare Before Christmas'),
      );
      await tester.pumpAndSettle();
      var plan = repo(container).current!.planById('christmas-2026')!;
      expect(
        plan.itemFor('movies/the-nightmare-before-christmas-1993')!.repeat,
        isTrue,
      );
      await tester.tap(find.bySemanticsLabel('Remove from plan: Die Hard'));
      await tester.pumpAndSettle();
      plan = repo(container).current!.planById('christmas-2026')!;
      expect(plan.itemFor('movies/die-hard-1988'), isNull);
    });

    testWidgets('the row actions edit, untag or delete the entry', (
      tester,
    ) async {
      final container = await open(tester, 'christmas-2026');
      await tester.tap(find.text('All Christmas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions: Klaus'));
      await tester.pumpAndSettle();
      expect(find.text('Edit entry'), findsOneWidget);
      expect(find.text('Remove #christmas'), findsOneWidget);
      await tester.tap(find.text('Remove #christmas'));
      await tester.pumpAndSettle();
      expect(
        repo(container).current!.entryById('movies/klaus-2019')!.tags,
        isNot(contains('christmas')),
      );
      expect(find.text('Klaus'), findsNothing);

      await tester.tap(find.byTooltip('More actions: Die Hard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Die Hard?'), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
      );
      await tester.pumpAndSettle();
      expect(
        repo(container).current!.entryById('movies/die-hard-1988'),
        isNull,
      );
    });
  });

  group('header menus', () {
    testWidgets('the year chip switches to a sibling plan', (tester) async {
      await open(tester, 'halloween-2026');
      await tester.tap(find.bySemanticsLabel('Choose year'));
      await tester.pumpAndSettle();
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('New year…'), findsOneWidget);
      await tester.tap(find.text('2025'));
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 done'), findsOneWidget);
      expect(find.text('Hill House'), findsNothing);
      expect(find.text('The Haunting of Hill House'), findsOneWidget);
    });

    testWidgets('"New year…" opens a copy for the next year', (tester) async {
      final container = await open(tester, 'halloween-2026');
      await tester.tap(find.bySemanticsLabel('Choose year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New year…'));
      await tester.pumpAndSettle();
      expect(find.text('New plan'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Halloween'), findsWidgets);
      expect(find.widgetWithText(TextField, '2027'), findsWidgets);
      expect(find.text('Copy from Halloween 2026'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      final plan = repo(container).current!.planById('halloween-2027')!;
      expect(plan.items.length, 6); // The unfinished ones, without dates.
      expect(plan.items.every((i) => !i.done && i.when == null), isTrue);
      expect(plan.timeline, isTrue);
      expect(find.text('0 of 6 done'), findsOneWidget); // Switched to it.
    });

    testWidgets('the plan menu deletes the plan', (tester) async {
      final container = await open(tester, 'christmas-2026');
      await tester.tap(find.byTooltip('Plan options'));
      await tester.pumpAndSettle();
      expect(find.text('Edit plan'), findsOneWidget);
      expect(find.text('Copy to a new year'), findsOneWidget);
      await tester.tap(find.text('Delete plan'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Christmas 2026?'), findsOneWidget);
      expect(find.text('Its 6 entries stay in your library.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.planById('christmas-2026'), isNotNull);
      await tester.tap(find.byTooltip('Plan options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete plan').last);
      await tester.pumpAndSettle();
      expect(repo(container).current!.planById('christmas-2026'), isNull);
      expect(find.byType(PlanScreen), findsNothing);
    });
  });
}
