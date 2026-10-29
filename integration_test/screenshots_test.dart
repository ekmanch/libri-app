// Captures the app for a visual check against the design canvas. Writes
// screenshots/<name>.png (git-ignored) from the app process. The Linux
// window is the phone's 360 x 780 dp (Galaxy S25), so a capture is
// 720 x 1560 px. Run on the Linux dev target:
//
//   flutter test integration_test/screenshots_test.dart -d linux
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:library_app/features/library/home_sections.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/dev/long_lists.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/data/storage/connection_store.dart';
import 'package:library_app/features/entry/dropped_season_dialog.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/platform_picker_sheet.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/features/library/filter_sheet.dart';
import 'package:library_app/features/library/library_filter.dart';
import 'package:library_app/features/library/library_filter_provider.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/plans/plan_entry_sheet.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/shell/floating_nav_bar.dart';
import 'package:library_app/data/sync/sync_status.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/main.dart';
import 'package:library_app/widgets/segmented_control.dart';
import 'package:library_app/widgets/app_dialog.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/entry_row.dart';
import 'package:library_app/features/entry/tag_picker_sheet.dart';
import 'package:library_app/widgets/tag_group.dart';

/// Wraps the whole app, including sheets, dialogs and menus in the root
/// overlay, so a capture shows what the user sees.
final _root = GlobalKey();

/// The repo the first run talks to: the canvas's three files, in memory.
/// [latency] lets a walk capture the "Connecting…" and "Creating…" states.
Override _demoGitHub({Duration latency = Duration.zero}) {
  final fixture = File(FixtureLibraryRepository.assetPath).readAsStringSync();
  final github = FakeGitHubApi.demo(fixture, latency: latency);
  return gitHubApiFactoryProvider.overrideWithValue(
    ({required token, required repository}) => github,
  );
}

const _demoLatency = Duration(milliseconds: 300);

/// Settings › Library connection as the artboard draws it: synced a few minutes
/// ago. The fixture has no sync of its own.
final _syncedRecently = syncStatusProvider.overrideWithValue(
  AsyncValue.data(
    SyncStatus(lastSynced: DateTime.now().subtract(const Duration(minutes: 3))),
  ),
);

/// A status segment of the type view.
Finder segment(String label) => find.descendant(
  of: find.byType(StatusSegmentedControl),
  matching: find.text(label),
);

/// Scrolls Add / edit entry down until [finder] is built and in view: the
/// form is a lazy list, so a row far down is not there to ensureVisible.
Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byType(EntryFormScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// The day the home captures look from: the fixture's newest entry is six
/// days old then, so Recently added has rows (Library › Home).
final homeDay = DateTime(2026, 10, 11);

Future<void> capture(WidgetTester tester, String name) async {
  final boundary =
      _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('screenshots/$name.png');
  await file.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  debugPrint('Wrote ${file.absolute.path}');
}

/// The home's header is part of its scroll (Library › Home), so after a list
/// has been scrolled the search box or the chips may be off screen and not
/// built: jump every vertical list back to the top first.
Future<void> revealHeader(WidgetTester tester) async {
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  var moved = false;
  for (final element in vertical.evaluate()) {
    final position =
        ((element as StatefulElement).state as ScrollableState).position;
    if (position.pixels > 0) {
      position.jumpTo(0);
      moved = true;
    }
  }
  if (moved) await tester.pumpAndSettle();
}

/// The home's vertical list (the header scrolls with it), for scrolling to
/// a row.
Finder homeList() => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

/// The filter sheet's own scroll view, not the Released row inside it.
Finder sheetList() => find
    .descendant(of: find.byType(FilterSheet), matching: find.byType(Scrollable))
    .first;

/// Scrolls the chip row (lazy, so a far chip is not built yet) and taps.
Future<void> pickChip(WidgetTester tester, String label) async {
  await revealHeader(tester);
  final chip = find.widgetWithText(PillChip, label);
  final row = find.byWidgetPredicate(
    (w) => w is ListView && w.scrollDirection == Axis.horizontal,
  );
  await tester.dragUntilVisible(
    chip,
    row,
    Offset(label == 'All' ? 80 : -80, 0),
  );
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Taps a tag chip in the filter sheet, scrolling the sheet until the chip
/// is clear of the pinned footer (the groups are A to Z, so #horror is
/// not at the top).
Future<void> tapSheetChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(PillChip, label);
  await tester.scrollUntilVisible(
    chip,
    80,
    scrollable: find
        .descendant(
          of: find.byType(FilterSheet),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Closes the open sheet with the system back, like the phone's gesture. A tall
/// sheet (Music › Album with track ratings) can leave no scrim to tap on a 780
/// dp screen.
Future<void> closeSheet(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Waits (up to 3 s) until at least [count] images are on screen: covers
/// come from the fake fetcher through the file system, off the frame
/// clock, so settling alone can capture the placeholders.
Future<void> waitForImages(WidgetTester tester, {int count = 1}) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(Image).evaluate().length >= count) break;
  }
  await tester.pumpAndSettle();
}

/// A tag chip inside one group of the tag picker or the filter sheet.
Finder pickerChip(String group, String tag) => find.descendant(
  of: find.widgetWithText(TagGroup, group),
  matching: find.widgetWithText(PillChip, tag),
);

/// A category chip in a dialog (Add / edit entry › New tag: confirm and
/// pick a category; the tag categories dialog).
Finder dialogChip(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.widgetWithText(PillChip, label),
);

Finder dialogText(String text) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(text));

Future<void> pickView(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Change view'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Show & seasons at [scale]: the show rows with a new season,
/// the Seasons section with few and many seasons, all seasons, the status
/// sheet with catch-up, and a season's episodes out and airing. Severance
/// gets a new season 3 (the daily check's work, applied directly).
/// Captures are prefixed "large-text-" above 1.
Future<void> walkSeasons(WidgetTester tester, {double scale = 1}) async {
  final prefix = scale == 1 ? '' : 'large-text-';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeLookupOverrides(),
        libraryRepositoryProvider.overrideWithValue(FixtureLibraryRepository()),
      ],
      child: RepaintBoundary(
        key: _root,
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: const LibraryApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.text('Library').first),
  );
  final today = DateTime.now();
  await container
      .read(libraryRepositoryProvider)
      .apply(
        AddSeasons('shows/severance-2022', [
          Season(
            season: 3,
            released: Released(today.year, today.month, today.day),
            fresh: true,
          ),
        ]),
      );
  await tester.pumpAndSettle();

  Future<void> openShow(String title) async {
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  Future<void> toSeasons() async {
    await tester.ensureVisible(find.text('SEASONS'));
    await tester.pumpAndSettle();
  }

  await pickChip(tester, 'Shows');
  await capture(tester, '${prefix}a1-shows-new-season');

  // Show & seasons › New season just out.
  await openShow('Severance');
  await capture(tester, '${prefix}a30-show-new-season');
  await toSeasons();
  await capture(tester, '${prefix}a30-show-new-season-seasons');
  await closeSheet(tester);

  // Show & seasons › Show with seasons: a few seasons, all listed.
  await revealHeader(tester);
  await openShow('Twin Peaks');
  await toSeasons();
  await capture(tester, '${prefix}a29-show-seasons');
  // Add / edit entry › Edit a show: a show's seasons in the form.
  await tester.ensureVisible(find.text('Edit'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Seasons'),
    100,
    scrollable: find
        .descendant(
          of: find.byType(EntryFormScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Seasons'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a8-edit-show-seasons');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);

  // Show & seasons › Many seasons, then All seasons.
  await revealHeader(tester);
  await openShow('What We Do in the Shadows');
  await tester.ensureVisible(find.text('All 6 seasons'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a31-show-many-seasons');
  await tester.tap(find.text('All 6 seasons'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a32-all-seasons');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);

  // Show & seasons › One season: its status in the Status row's pill, the sheet
  // titled with the show; Episodes of a one-season show: its season; Season 2
  // announced: a second season appears.
  await revealHeader(tester);
  await openShow('The Haunting of Hill House');
  await capture(tester, '${prefix}a34-show-one-season');
  await tester.tap(find.bySemanticsLabel(RegExp('^Status: ')));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a34-show-one-season-status');
  await closeSheet(tester);
  final onlySeason = find.bySemanticsLabel(RegExp(r'^Season 1, .*Episodes$'));
  await tester.ensureVisible(onlySeason);
  await tester.pumpAndSettle();
  await tester.tap(onlySeason);
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a41-season-one-season-show');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);
  await container
      .read(libraryRepositoryProvider)
      .apply(
        AddSeasons('shows/the-haunting-of-hill-house-2018', [
          Season(season: 2, released: Released(today.year + 1), fresh: true),
        ]),
      );
  await tester.pumpAndSettle();
  await revealHeader(tester);
  await openShow('The Haunting of Hill House');
  await tester.ensureVisible(find.text('SEASONS'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a35-show-season-announced');
  await closeSheet(tester);

  // Show & seasons › Announced season dropped: a dropped season the user had
  // given a status.
  final hillHouse = (await container.read(libraryRepositoryProvider).load())
      .entryById('shows/the-haunting-of-hill-house-2018')!;
  unawaited(
    showDroppedSeasonDialog(
      tester.element(find.text('Library').first),
      show: hillHouse,
      season: 2,
      status: EntryStatus.want,
    ),
  );
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a36-season-dropped');
  await tester.tap(find.text('Keep it'));
  await tester.pumpAndSettle();

  // Show & seasons › All seasons, just added: catch up: the status sheet with
  // catch-up.
  await revealHeader(tester);
  await openShow('Stranger Things');
  final pill = find.bySemanticsLabel(RegExp('^Season 5 status: '));
  await tester.ensureVisible(pill);
  await tester.pumpAndSettle();
  await tester.tap(pill);
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a33-season-status-catch-up');
  await closeSheet(tester);

  // Show & seasons › Season episodes (all out): a season out on one day; Season
  // episodes (airing weekly): one airing weekly (the fake's Severance season 3,
  // from today).
  Future<void> openSeasonRow(int season) async {
    final row = find.bySemanticsLabel(RegExp('^Season $season, .*Episodes\$'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  await openSeasonRow(1);
  await capture(tester, '${prefix}a39-season-episodes');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);
  await revealHeader(tester);
  await openShow('Severance');
  await openSeasonRow(3);
  await capture(tester, '${prefix}a40-season-airing');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);

  // Show & seasons › Anime with seasons (Frieren): an anime series, laid out
  // like a show in the anime color; Anime season episodes: its season 2.
  await revealHeader(tester);
  await pickChip(tester, 'Anime');
  await capture(tester, '${prefix}a1-anime-with-seasons');
  await openShow("Frieren: Beyond Journey's End");
  await toSeasons();
  await capture(tester, '${prefix}a43-anime-seasons');
  await openSeasonRow(2);
  await capture(tester, '${prefix}a44-anime-season-episodes');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);
}

/// A series as one row of a long type list (Library › Movies, text view;
/// list and grid with covers), the series page it opens (Library › Series
/// page (from a series row)), its menu, Series cover and Choose what to show
/// sheets, a hidden part (Library › Series page: hidden parts) and a list
/// the lookup could not update (Library › Series page: couldn't update), at
/// [scale]. The
/// movies are padded to three screens, so The Lord of the Rings' two parts
/// group. Captures are prefixed "large-text-" above 1.
Future<void> walkSeriesRows(WidgetTester tester, {double scale = 1}) async {
  final prefix = scale == 1 ? '' : 'large-text-';
  final source = _FlakySeries();
  final long = padForLongLists(
    decodeLibrary(
      await File(FixtureLibraryRepository.assetPath).readAsString(),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeLookupOverrides(source: source),
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(loadJson: () async => encodeLibrary(long)),
        ),
      ],
      child: RepaintBoundary(
        key: _root,
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: const LibraryApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final row = find.text('The Lord of the Rings');
  Future<void> toRow() async {
    await tester.scrollUntilVisible(row, 200, scrollable: homeList());
    await tester.pumpAndSettle();
  }

  // Title order: the row sits where its first part would, among the T's.
  await pickChip(tester, 'Movies');
  await tester.tap(find.text('Newest added'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Title, A to Z'));
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
  await toRow();
  await capture(tester, '${prefix}l4-series-row-text');
  await revealHeader(tester);
  await pickView(tester, 'List with covers');
  await toRow();
  await waitForImages(tester, count: 3);
  await capture(tester, '${prefix}l4-series-row-list');
  await revealHeader(tester);
  await pickView(tester, 'Grid with covers');
  await toRow();
  // The scroll stops with the tile's title in view; bring its cover and
  // badge down too, and let the fast-scroll thumb fade.
  await tester.drag(homeList(), const Offset(0, 260));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await waitForImages(tester, count: 3);
  await capture(tester, '${prefix}l4-series-row-grid');

  // Library › Series page (from a series row), then its cover sheet.
  await tester.tap(row);
  await tester.pumpAndSettle();
  await waitForImages(tester, count: 0);
  await capture(tester, '${prefix}l5-series-page');
  Future<void> menu(String item) async {
    await tester.tap(find.byTooltip('Series options'));
    await tester.pumpAndSettle();
    if (item == 'Series cover') {
      await capture(tester, '${prefix}l5-series-menu');
    }
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  await menu('Series cover');
  await waitForImages(tester, count: 2);
  await capture(tester, '${prefix}l5-series-cover');
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
  // Library › Series page: choose what to show, then hidden parts.
  await menu('Choose what to show');
  final returnOfTheKing = find.bySemanticsLabel('The Return of the King');
  await tester.tap(returnOfTheKing);
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}l5-series-show');
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}l5-series-hidden');
  await menu('Choose what to show');
  await tester.tap(returnOfTheKing);
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
  // Library › Series page: couldn't update. A week on, the lookup does not
  // answer, so the stored list shows with the line.
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  source.failing = true;
  final later = DateTime.now().add(const Duration(days: 8));
  seasonClock = () => later;
  addTearDown(() => seasonClock = DateTime.now);
  await tester.tap(row);
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}l5-series-not-updated');
  source.failing = false;
  seasonClock = DateTime.now;
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await revealHeader(tester);
  await pickView(tester, 'Text');
  await tester.tap(find.text('Title, A to Z'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Newest added'));
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
}

/// Library › Movie in a series (The Lord of the Rings), Book in a long series
/// (Berserk 43) and All volumes in a series at [scale], with the Series and
/// Number fields of Add / edit entry and an anime's kind control. Captures
/// are prefixed "large-text-" above 1.
Future<void> walkSeries(WidgetTester tester, {double scale = 1}) async {
  final prefix = scale == 1 ? '' : 'large-text-';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeLookupOverrides(),
        libraryRepositoryProvider.overrideWithValue(FixtureLibraryRepository()),
      ],
      child: RepaintBoundary(
        key: _root,
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: const LibraryApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  Future<void> openRow(String title) async {
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  Future<void> toSeries() async {
    await tester.ensureVisible(find.text('SERIES'));
    await tester.pumpAndSettle();
  }

  Future<void> openEdit() async {
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  // Library › Movie in a series: three parts, all listed, this one marked.
  await pickChip(tester, 'Movies');
  await pickView(tester, 'List with covers');
  await openRow('The Lord of the Rings: The Fellowship of the Ring');
  await toSeries();
  await capture(tester, '${prefix}a45-movie-in-series');
  // Add / edit entry: the Series and Number fields under the director.
  await openEdit();
  await capture(tester, '${prefix}a45-edit-movie-series');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);

  // Library › Book in a long series: a window of three and "All 43 volumes";
  // All volumes in a series: the full list, scrolled to this one.
  await revealHeader(tester);
  await pickChip(tester, 'Books');
  await pickView(tester, 'List with covers');
  await openRow('Berserk, Vol. 43');
  await toSeries();
  await capture(tester, '${prefix}a46-book-long-series');
  await tester.ensureVisible(find.text('All 43 volumes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('All 43 volumes'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a47-all-volumes');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);

  // Add / edit entry for an anime from before kinds: Series or movie, unpicked.
  await revealHeader(tester);
  await pickChip(tester, 'Anime');
  await openRow('Spirited Away');
  await openEdit();
  await capture(tester, '${prefix}a48-edit-anime-kind');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);
}

/// Library › Book details (page count) at [scale]: a book's details with its
/// page count under the author, in a photo view as drawn, and the Pages field
/// in Add / edit entry. Captures are prefixed "large-text-" above 1.
Future<void> walkBook(WidgetTester tester, {double scale = 1}) async {
  final prefix = scale == 1 ? '' : 'large-text-';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeLookupOverrides(),
        libraryRepositoryProvider.overrideWithValue(FixtureLibraryRepository()),
      ],
      child: RepaintBoundary(
        key: _root,
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: const LibraryApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await pickChip(tester, 'Books');
  await pickView(tester, 'List with covers');
  await tester.tap(find.text('The Shining').last);
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a38-book-details');
  await tester.ensureVisible(find.text('Edit'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  // Author, Released and Pages at the top, as drawn.
  await tester.scrollUntilVisible(
    find.text('Author'),
    100,
    scrollable: find
        .descendant(
          of: find.byType(EntryFormScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(find.text('Author')));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a38-edit-book-pages');
  // Add / edit entry › Pick a cover, then Cover from another match.
  await tester.scrollUntilVisible(
    find.text('From the match · tap to change'),
    -100,
    scrollable: find
        .descendant(
          of: find.byType(EntryFormScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await tester.ensureVisible(find.bySemanticsLabel('Cover. Tap to change'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Cover. Tap to change'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('The Shining, 2009 ·\u00a0Paperback'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a49-pick-a-cover');
  await tester.tap(find.widgetWithText(FilledButton, 'Done'));
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a49-edit-cover-from-another-match');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await closeSheet(tester);
  // Add / edit entry › Book: year from the ebook edition: an Apple Books
  // pick with no Open Library year.
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const EntryFormScreen.create(
              match: LookupMatch(
                type: MediaType.books,
                title: 'Leave the Lights On',
                source: 'itunes:6756269989',
                released: Released(2026, 9, 29),
                releasedFromEbook: true,
                creator: 'Riley Sager',
              ),
            ),
          ),
        ),
  );
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a42-add-book-ebook-year');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
}

/// Add / edit entry › Platform picker and Game search on a platform: a
/// game search for "Street Fighter II", the picker over it, then the
/// search narrowed to the Super Nintendo.
Future<void> walkGamePlatform(WidgetTester tester, {double scale = 1}) async {
  final prefix = scale == 1 ? '' : 'large-text-';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...fakeLookupOverrides(),
        libraryRepositoryProvider.overrideWithValue(FixtureLibraryRepository()),
      ],
      child: RepaintBoundary(
        key: _root,
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: const LibraryApp(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(AddButton));
  await tester.pumpAndSettle();
  final games = find.widgetWithText(PillChip, 'Games');
  await tester.dragUntilVisible(
    games,
    find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    ),
    const Offset(-80, 0),
  );
  await tester.pumpAndSettle();
  await tester.tap(games);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Street Fighter II');
  await tester.pump(NewEntryScreen.debounce);
  await waitForImages(tester, count: 4);
  await tester.tap(
    find
        .descendant(
          of: find.byType(PlatformChip),
          matching: find.byType(InkWell),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a50-platform-picker');
  await tester.enterText(find.byType(TextField).last, 'snes');
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a50-platform-picker-search');
  await tester.tap(find.text('Super Nintendo'));
  await tester.pumpAndSettle();
  await waitForImages(tester, count: 2);
  await capture(tester, '${prefix}a50-game-search-on-platform');
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('game search on a platform', (tester) async {
    await walkGamePlatform(tester);
  });

  testWidgets('game search on a platform at a larger text size', (
    tester,
  ) async {
    await walkGamePlatform(tester, scale: 1.3);
  });

  testWidgets('book page count', (tester) async {
    await walkBook(tester);
  });

  testWidgets('book page count at a larger text size', (tester) async {
    await walkBook(tester, scale: 1.3);
  });

  testWidgets('show seasons', (tester) async {
    await walkSeasons(tester);
  });

  testWidgets('show seasons at a larger text size', (tester) async {
    await walkSeasons(tester, scale: 1.3);
  });

  testWidgets('series', (tester) async {
    await walkSeries(tester);
  });

  testWidgets('series at a larger text size', (tester) async {
    await walkSeries(tester, scale: 1.3);
  });

  testWidgets('series rows', (tester) async {
    await walkSeriesRows(tester);
  });

  testWidgets('series rows at a larger text size', (tester) async {
    await walkSeriesRows(tester, scale: 1.3);
  });

  testWidgets('library screens in dark and light', (tester) async {
    // The home's Recently added looks back 30 days from the app clock, so
    // the capture is taken from a day the fixture was fresh (Library › Home).
    seasonClock = () => homeDay;
    addTearDown(() => seasonClock = DateTime.now);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a1-home-dark');
    // Scrolled to the end, for Recently added.
    await tester.drag(find.byType(HomeRow).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await capture(tester, 'a1a-home-scrolled');
    await revealHeader(tester);

    // Library › In progress, all types (See all): the filter result with
    // just that status.
    await tester.tap(find.textContaining('See all '));
    await tester.pumpAndSettle();
    await capture(tester, 'a1b-home-see-all');
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    seasonClock = DateTime.now;

    // Library › Movies, text view and grid with covers.
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    await capture(tester, 'a4-movies-text');

    // The filter sheet opened from Movies with Done picked, and its result:
    // the type view with Done picked, not a results screen.
    await tester.tap(segment('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await capture(tester, 'a3-filter-from-movies-done');
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a11-movies-done');
    await tester.tap(segment('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    await capture(tester, 'a16-view-menu');
    await tester.tap(find.text('Grid with covers'));
    await tester.pumpAndSettle();
    await capture(tester, 'a21-movies-grid');
    await tester.tap(find.text('Newest added'));
    await tester.pumpAndSettle();
    await capture(tester, 'd1-sort');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await pickChip(tester, 'All');

    // Library › Filter sheet and Filtered results, one type: filter to shows
    // tagged horror.
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.widgetWithText(PillChip, 'Shows'),
      ),
    );
    await tapSheetChip(tester, '#horror');
    await capture(tester, 'a2-filter-sheet');
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'l5-filtered-short');
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    // Library › Search.
    await tester.tap(find.text('Search titles and tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hal');
    await tester.pumpAndSettle();
    await capture(tester, 'a5-search');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Library › Entry details and what opens from it: Rating picker, Add to
    // plan, Delete confirmation.
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    // Movies is still in the grid view, so the sheet shows the cover spot.
    // A tile carries the title twice: on the placeholder and as the caption.
    // Lazy grid: scroll until the tile is built, then tap its caption.
    await tester.scrollUntilVisible(
      find.text('The Mummy'),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Mummy').last);
    await tester.pumpAndSettle();
    await capture(tester, 'a6-entry-details');
    await tester.tap(find.text('9 / 10'));
    await tester.pumpAndSettle();
    await capture(tester, 'd11-rating');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to plan'));
    await tester.pumpAndSettle();
    await capture(tester, 'a7-add-to-plan');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await capture(tester, 'a9-delete');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Add / edit entry: editing, the tag picker, New tag: a similar one
    // exists and New tag: confirm and pick a category.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-edit-entry');
    await scrollFormTo(tester, find.text('#adventure'));
    await tester.tap(find.text('#adventure'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-tag-picker');
    await tester.enterText(find.byType(TextField).last, 'sci-fi');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Create #sci-fi'));
    await tester.pumpAndSettle();
    await capture(tester, 'd9-similar-tag');
    await tester.tap(find.text('Create #sci-fi anyway'));
    await tester.pumpAndSettle();
    await capture(tester, 'd10-new-tag');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await closeSheet(tester);

    // Library › Entry details: tag in two categories, Add / edit entry › Tag
    // in two categories: entry form and tag picker, the categories dialog
    // (a long press), the "Add to" rows of a search, and New tag with two
    // categories.
    await tester.scrollUntilVisible(
      find.text('Million Dollar Baby'),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Million Dollar Baby').last);
    await tester.pumpAndSettle();
    await capture(tester, 'a6-entry-details-two-cat');
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    // The form's list is lazy: scroll until the Tags box is built.
    await tester.scrollUntilVisible(
      find.text('#clint-eastwood · Director'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a8-edit-entry-two-cat');
    await tester.tap(find.text('#clint-eastwood · Director'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-tag-picker-two-cat');
    await tester.ensureVisible(pickerChip('Directors', '#clint-eastwood'));
    await tester.pumpAndSettle();
    await tester.longPress(pickerChip('Directors', '#clint-eastwood'));
    await tester.pumpAndSettle();
    await capture(tester, 'd16-tag-categories');
    await tester.tap(dialogText('Cancel'));
    await tester.pumpAndSettle();
    // A one-category tag's long press moves it to another such group.
    final otherGroup = find.descendant(
      of: find.byType(TagPickerSheet),
      matching: find.text('Other'),
    );
    await tester.ensureVisible(otherGroup);
    await tester.pumpAndSettle();
    await tester.tap(otherGroup);
    await tester.pumpAndSettle();
    await tester.ensureVisible(pickerChip('Other', '#favorite'));
    await tester.pumpAndSettle();
    await tester.longPress(pickerChip('Other', '#favorite'));
    await tester.pumpAndSettle();
    await capture(tester, 'd16-tag-move');
    await tester.tap(dialogText('Cancel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hilary');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add to Directors'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-tag-picker-add-to');
    await tester.enterText(find.byType(TextField).last, 'sergio-leone');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Create #sergio-leone'));
    await tester.pumpAndSettle();
    await tester.tap(dialogChip('Directors'));
    await tester.pumpAndSettle();
    await tester.tap(dialogChip('Actors'));
    await tester.pumpAndSettle();
    await capture(tester, 'd10-new-tag-two-cat');
    await tester.tap(dialogText('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    await pickChip(tester, 'All');

    // Add / edit entry › New entry: pick a match.
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The Last of Us');
    await tester.pump(NewEntryScreen.debounce);
    await waitForImages(tester, count: 4);
    await capture(tester, 'a13-new-entry');
    await tester.tap(find.text('GAME · 2013'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-new-entry');
    await tester.tap(find.text('Jun 14, 2013'));
    await tester.pumpAndSettle();
    await capture(tester, 'a25-released-picker');
    await tester.tap(find.text('2013'));
    await tester.pumpAndSettle();
    await capture(tester, 'a26-released-type');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Suggested · tap to add'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a8-new-entry-tags');
    await tester.tap(find.widgetWithText(TagChip, '#horror'));
    await tester.pumpAndSettle();
    await capture(tester, 'd14-tag-picker');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Add / edit entry from a movie match (Back lands on New entry: pick a
    // match again): the billed cast as actor suggestions, New tag: confirm
    // and pick a category starting on Actors, and the picker's "New on this
    // entry" group.
    // The field lost focus on the way back, so typing needs a tap first.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Soul');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MOVIE · 2020'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Suggested · tap to add'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a8-new-entry-actors');
    await tester.tap(find.bySemanticsLabel('Add #tina-fey'));
    await tester.pumpAndSettle();
    await capture(tester, 'd10-new-actor-tag');
    await tester.ensureVisible(find.text('Create tag'));
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TagChip, '#tina-fey'));
    await tester.pumpAndSettle();
    await capture(tester, 'd14-tag-picker-new-tag');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Library › Music: artists, text view, list with photos and grid with
    // photos: the music tabs in the three views.
    await pickChip(tester, 'Music');
    await capture(tester, 'a14-music-artists');
    await pickView(tester, 'List with photos');
    await capture(tester, 'a17-music-list-photos');
    await pickView(tester, 'Grid with photos');
    await capture(tester, 'a18-music-grid');
    await pickView(tester, 'Text');

    // Music › Artist, text view; Music › Album with track ratings.
    await tester.tap(find.text('Alice in Chains'));
    await tester.pumpAndSettle();
    await capture(tester, 'a15-artist');
    await tester.tap(find.text('Dirt'));
    await tester.pumpAndSettle();
    await capture(tester, 'a22-album-details');
    await closeSheet(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await capture(tester, 'a14-music-albums');
    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();
    await capture(tester, 'a14-music-songs');

    // Library › Filter sheet from a type view, for music: opened from Songs,
    // the sheet has Music + Songs; Albums instead comes back as the Albums tab
    // (Library › Music: albums (filter result)).
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await capture(tester, 'a3-filter-from-music-songs');
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a23-music-songs');
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    final kind = find.descendant(
      of: find.byType(FilterSheet),
      matching: find.widgetWithText(PillChip, 'Songs'),
    );
    await tester.tap(kind);
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.widgetWithText(PillChip, 'Albums'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a24-music-albums');
    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();

    // Add / edit entry › Saving an album: songs already saved.
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill in the details myself'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Title',
      ),
      'Green River',
    );
    await tester.enterText(
      find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == 'Optional',
          )
          .first,
      'Creedence Clearwater Revival',
    );
    await tester.pumpAndSettle();
    await capture(tester, 'a8-new-album');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await capture(tester, 'd12-replace-songs');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await pickChip(tester, 'All');

    // Library › Home, light theme.
    final container = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );
    container
        .read(displayPreferencesProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    await capture(tester, 'd8-home-light');
  });

  testWidgets('the screens the first pass skips', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );

    // Library › Empty states: a filter nothing matches.
    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(tags: {'horror', 'cozy', 'jazz'}));
    await tester.pumpAndSettle();
    await capture(tester, 'a10-empty-filter');
    container.read(libraryFilterProvider.notifier).clear();
    await tester.pumpAndSettle();

    // Add / edit entry with "Look up again", and New entry: pick a match as
    // the picker it opens (phase 5).
    await pickChip(tester, 'Movies');
    await tester.ensureVisible(find.text('Dune: Part Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dune: Part Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-look-up-again');
    await tester.tap(find.text('Look up again'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Dune');
    await tester.pump(NewEntryScreen.debounce);
    await waitForImages(tester, count: 2);
    await capture(tester, 'a13-look-up-again');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    await pickChip(tester, 'All');

    // Library › Movies, list with covers.
    await pickChip(tester, 'Movies');
    await pickView(tester, 'List with covers');
    await capture(tester, 'a20-movies-list-covers');
    await pickView(tester, 'Text');

    // Music › Artist, with photos.
    await pickChip(tester, 'Music');
    await pickView(tester, 'List with photos');
    await tester.tap(find.text('Alice in Chains'));
    await tester.pumpAndSettle();
    await capture(tester, 'a19-artist-photos');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await pickView(tester, 'Text');

    // Add / edit entry › Saving a song: album already saved.
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill in the details myself'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Title',
      ),
      'Rooster',
    );
    final optional = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Optional',
    );
    await tester.enterText(optional.at(0), 'Alice in Chains');
    await tester.enterText(optional.at(1), 'Dirt');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await capture(tester, 'd13-replace-album');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await pickChip(tester, 'All');

    // Plans › Entry details (timeline off) and the plan note; the linked tags
    // and copy-from sheets.
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Christmas 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Die Hard'));
    await tester.pumpAndSettle();
    await capture(tester, 's8-plan-entry-no-timeline');
    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    await capture(tester, 'plan-note-sheet');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#christmas'));
    await tester.pumpAndSettle();
    await capture(tester, 's9-linked-tags-sheet');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('Plans'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy a plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Copy from'));
    await tester.pumpAndSettle();
    await capture(tester, 's10-copy-from-sheet');
  });

  testWidgets('the phone at a larger text size', (tester) async {
    // 1.3 is a common font setting. The window is already the phone's
    // 360 x 780 dp (see linux/runner/my_application.cc).
    seasonClock = () => homeDay;
    addTearDown(() => seasonClock = DateTime.now);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
          _demoGitHub(),
        ],
        child: RepaintBoundary(
          key: _root,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: const LibraryApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a1-home');
    await tester.drag(find.byType(HomeRow).first, const Offset(0, -1600));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a1a-home-scrolled');
    await revealHeader(tester);
    await tester.tap(find.textContaining('See all '));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a1b-home-see-all');
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    seasonClock = DateTime.now;
    await pickChip(tester, 'Movies');
    await capture(tester, 'large-text-a4-movies');
    await tester.ensureVisible(segment('Done'));
    await tester.tap(segment('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a3-filter-from-movies-done');
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a11-movies-done');
    await revealHeader(tester);
    await tester.ensureVisible(segment('All'));
    await tester.tap(segment('All'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('The Mummy'),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Mummy').last);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a6-details');
    await closeSheet(tester);
    // Tag in two categories at the larger size: details, the form, the
    // picker and the categories dialog.
    await tester.scrollUntilVisible(
      find.text('Million Dollar Baby'),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Million Dollar Baby').last);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a6-details-two-cat');
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    // The form's list is lazy: scroll until the Tags box is built.
    await tester.scrollUntilVisible(
      find.text('#clint-eastwood · Director'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a8-edit-entry-two-cat');
    await tester.tap(find.text('#clint-eastwood · Director'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a8-tag-picker-two-cat');
    await tester.ensureVisible(pickerChip('Directors', '#clint-eastwood'));
    await tester.pumpAndSettle();
    await tester.longPress(pickerChip('Directors', '#clint-eastwood'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-d16-tag-categories');
    await tester.tap(dialogText('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    await pickChip(tester, 'All');
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Halloween 2026'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-s2-halloween');
    await tester.tap(find.text('All Halloween'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-s4-pool');
    await tester.tap(find.text('This plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Mummy'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-s7-plan-entry');
    await closeSheet(tester);
    // Back on the Library tab the "+" starts a new entry.
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('Library'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The Last of Us');
    await tester.pump(NewEntryScreen.debounce);
    await waitForImages(tester, count: 4);
    await capture(tester, 'large-text-a13-new-entry');
    await tester.tap(find.text('GAME · 2013'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a8-form');
    await tester.tap(find.text('Jun 14, 2013'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a25-released-picker');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    // Add / edit entry › New tag: confirm and pick a category, with its ten
    // category chips: a new suggested tag opens it.
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Add #stealth'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add #stealth'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-d10-new-tag');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Settings, Settings › Library connection, First run › Connect GitHub and
    // Library › Sync and errors at the larger text size.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-s6-settings');
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-s6-settings-bottom');
    await tester.ensureVisible(find.text('Libri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libri'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-d19-about');
    await tester.scrollUntilVisible(find.text('AniList'), 300);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-d19-about-bottom');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-d6-connection');
    await tester.tap(find.text('Replace token'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-f3-connect');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    final largeTextContainer = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );
    largeTextContainer
        .read(syncBannerProvider.notifier)
        .show(SyncBanner.couldNotSave);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a12-could-not-save');
    largeTextContainer
        .read(syncBannerProvider.notifier)
        .show(SyncBanner.notFound);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a12-not-found');
    largeTextContainer.read(syncBannerProvider.notifier).clear();
    await tester.pumpAndSettle();

    // First run › Pick a branch at the larger text size: the first run after
    // the library is deleted from the phone (Settings › Disconnect: keep or
    // delete), up to the branch list.
    largeTextContainer
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-f4-branch');
  });

  testWidgets('settings, connection, first run, banners and first load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
          _syncedRecently,
          _demoGitHub(latency: _demoLatency),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );

    // Library › Sync and errors: the four banners on the home.
    final banners = container.read(syncBannerProvider.notifier);
    for (final (banner, name) in [
      (SyncBanner.saving, 'a12-saving'),
      (SyncBanner.offline, 'a12-offline'),
      (SyncBanner.couldNotSave, 'a12-could-not-save'),
      (SyncBanner.tokenProblem, 'a12-token-problem'),
      (SyncBanner.tokenExpired, 'a12-token-expired'),
      (SyncBanner.notFound, 'a12-not-found'),
      (SyncBanner.conflict, 'a27-conflict'),
    ]) {
      banners.show(banner);
      await tester.pumpAndSettle();
      await capture(tester, name);
    }
    // Library › Conflict: keep which copy?, from the conflict banner's Choose.
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await capture(tester, 'd17-conflict');
    await tester.tap(find.text('Decide later'));
    await tester.pumpAndSettle();
    banners.clear();
    await tester.pumpAndSettle();

    // Settings top and bottom, Settings › Library connection.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await capture(tester, 's6-settings');
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    await tester.pumpAndSettle();
    await capture(tester, 's6-settings-bottom');
    await tester.ensureVisible(find.text('Libri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libri'));
    await tester.pumpAndSettle();
    await capture(tester, 'd19-about');
    await tester.scrollUntilVisible(find.text('AniList'), 300);
    await tester.pumpAndSettle();
    await capture(tester, 'd19-about-bottom');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    await capture(tester, 'd6-connection');

    // Disconnect is two steps (Settings › Disconnect: confirm, then keep or
    // delete); deleting the library from the phone starts the first run at the
    // welcome screen (First run › Welcome).
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await capture(tester, 'd15-disconnect-confirm');
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Disconnect'),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'd16-disconnect-keep');
    await tester.tap(find.text('Delete it from this phone'));
    await tester.pumpAndSettle();
    await capture(tester, 'f2-welcome');
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await capture(tester, 'f3-connect');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await capture(tester, 'f3-connecting');
    // The repo call has answered, the branches are still loading.
    await tester.pump(_demoLatency + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await capture(tester, 'f4-branch-looking');
    await tester.pump(_demoLatency * 2);
    await tester.pumpAndSettle();
    await capture(tester, 'f4-branch');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await capture(tester, 'f5-file');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await capture(tester, 'f6-create');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a file I already have'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await capture(tester, 'f7-looking');
    // The listing, three files and two commit lookups, each with latency.
    await tester.pump(_demoLatency * 8);
    await tester.pumpAndSettle();
    await capture(tester, 'f7-existing');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a new library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'libri.json');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create library'));
    await tester.pump();
    await capture(tester, 'f6-creating');
    await tester.pump(_demoLatency * 2);
    await tester.pumpAndSettle();
    await capture(tester, 'f8-done');
    await tester.tap(find.text('Open Libri'));
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsWidgets);

    // Settings › Library connection with the library kept on this phone
    // (Settings › Disconnect: keep or delete, "Keep it on this phone").
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
          initialConnectionProvider.overrideWithValue(
            const LibraryConnection(connected: false, keptLocally: true),
          ),
          _demoGitHub(latency: _demoLatency),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Library source'), 300);
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    await capture(tester, 'd6-connection-local');

    // First run › Different file: which library?: connecting again and picking
    // another file than the kept one.
    await tester.tap(find.text('Connect to GitHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pump(_demoLatency * 2);
    await tester.pumpAndSettle();
    await tester.pump(_demoLatency * 2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a file I already have'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump(_demoLatency * 8);
    await tester.pumpAndSettle();
    await tester.tap(find.text('backup/library-2025.json'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this file'));
    await tester.pumpAndSettle();
    await capture(tester, 'd18-which-library');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // First run › Pick an existing file, Library file: new or existing, Pick a
    // branch, Connect GitHub; then Connect GitHub pops back to Settings ›
    // Library connection.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    // The navigator outlives the scope swap (the root key), so leave Settings ›
    // Library connection and Settings before the next one.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // First run › Splash, on a cold start without a connection.
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...fakeLookupOverrides(),
          initialConnectionProvider.overrideWithValue(
            LibraryConnection.disconnected,
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pump();
    await capture(tester, 'f1-splash');
    await tester.pump(FirstRunFlow.splashDuration);
    await tester.pumpAndSettle();

    // Settings › Library connection with changes that could not be saved, and
    // its Disconnect dialog.
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
          syncStatusProvider.overrideWithValue(
            AsyncValue.data(
              SyncStatus(
                phase: SyncPhase.failed,
                pendingCount: 2,
                lastSynced: DateTime.now().subtract(const Duration(hours: 3)),
              ),
            ),
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Library source'), 300);
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    await capture(tester, 'd6-connection-failed');
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await capture(tester, 'd6-disconnect-confirm-pending');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // First run › First load: a library that never finishes loading.
    final never = Completer<String>();
    await tester.pumpWidget(
      ProviderScope(
        // A new key, or the first ProviderScope's container is kept.
        key: UniqueKey(),
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(loadJson: () => never.future),
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'd7-first-load');
  });

  /// The app with a connection whose token expires at [tokenExpires], for
  /// Library › Token expires soon and the "Token expired" state.
  Future<ProviderContainer> pumpWithToken(
    WidgetTester tester, {
    required DateTime tokenExpires,
    double textScale = 1,
    Override? syncStatus,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
          syncStatus ?? _syncedRecently,
          _demoGitHub(),
          initialConnectionProvider.overrideWithValue(
            LibraryConnection(connected: true, tokenExpires: tokenExpires),
          ),
          connectionStoreProvider.overrideWithValue(MemoryConnectionStore()),
        ],
        child: RepaintBoundary(
          key: _root,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: const LibraryApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );
  }

  testWidgets('token expires soon warning in dark and light', (tester) async {
    // Six days left, as the artboard's default variant.
    final container = await pumpWithToken(
      tester,
      tokenExpires: DateTime.now().add(const Duration(days: 6)),
    );
    await capture(tester, 'd20-token-expiry');
    container
        .read(displayPreferencesProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    await capture(tester, 'light-d20-token-expiry');
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
  });

  testWidgets('token expires soon at a larger text size', (tester) async {
    await pumpWithToken(
      tester,
      tokenExpires: DateTime.now().add(const Duration(days: 1)),
      textScale: 1.3,
    );
    await capture(tester, 'large-text-d20-token-expiry');
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
  });

  testWidgets('an expired token on the home and in the library connection', (
    tester,
  ) async {
    await pumpWithToken(
      tester,
      tokenExpires: DateTime.now().subtract(const Duration(days: 1)),
      syncStatus: syncStatusProvider.overrideWithValue(
        AsyncValue.data(
          SyncStatus(
            phase: SyncPhase.tokenProblem,
            pendingCount: 2,
            lastSynced: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Library source'), 300);
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    await capture(tester, 'd6-connection-expired');
  });

  testWidgets('light theme pass over every screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
          _syncedRecently,
          _demoGitHub(),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );
    container
        .read(displayPreferencesProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    Future<void> shot(String name) => capture(tester, 'light-$name');
    Future<void> tapText(String text) async {
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }

    await shot('a1-home');
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    await shot('a4-movies-text');
    await tester.tap(segment('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await shot('a3-filter-from-movies-done');
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await shot('a11-movies-done');
    await tester.tap(segment('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    await shot('a16-view-menu');
    await tapText('Grid with covers');
    await shot('a21-movies-grid');
    await tapText('Newest added');
    await shot('d1-sort');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await pickView(tester, 'List with covers');
    await shot('a20-movies-list-covers');
    await pickView(tester, 'Text');
    await pickChip(tester, 'All');
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tapSheetChip(tester, '#horror');
    await shot('a2-filter-sheet');
    await tester.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await tester.pumpAndSettle();
    await shot('l5-filtered-short');
    await tapText('Clear all');
    await tapText('Search titles and tags');
    await tester.enterText(find.byType(TextField), 'hal');
    await tester.pumpAndSettle();
    await shot('a5-search');
    await tapText('Cancel');
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('The Mummy'),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tapText('The Mummy');
    await shot('a6-entry-details');
    await tapText('9 / 10');
    await shot('d11-rating');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tapText('Add to plan');
    await shot('a7-add-to-plan');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tapText('Delete');
    await shot('a9-delete');
    await tapText('Cancel');
    await tapText('Edit');
    await shot('a8-edit-entry');
    await scrollFormTo(tester, find.text('#adventure'));
    await tapText('#adventure');
    await shot('d14-tag-picker');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await back();
    await closeSheet(tester);
    // Tag in two categories in the light theme.
    await tester.scrollUntilVisible(
      find.text('Million Dollar Baby'),
      200,
      scrollable: homeList(),
    );
    await tester.pumpAndSettle();
    await tapText('Million Dollar Baby');
    await shot('a6-entry-details-two-cat');
    await tester.ensureVisible(find.text('Edit'));
    await tapText('Edit');
    // The form's list is lazy: scroll until the Tags box is built.
    await tester.scrollUntilVisible(
      find.text('#clint-eastwood · Director'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shot('a8-edit-entry-two-cat');
    await tapText('#clint-eastwood · Director');
    await shot('a8-tag-picker-two-cat');
    await tester.ensureVisible(pickerChip('Directors', '#clint-eastwood'));
    await tester.pumpAndSettle();
    await tester.longPress(pickerChip('Directors', '#clint-eastwood'));
    await tester.pumpAndSettle();
    await shot('d16-tag-categories');
    await tester.tap(dialogText('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await back();
    await closeSheet(tester);
    await pickChip(tester, 'All');
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The Last of Us');
    await tester.pumpAndSettle();
    await shot('a13-new-entry');
    await tapText('GAME · 2013');
    await shot('a8-new-entry');
    await tapText('Jun 14, 2013');
    await shot('a25-released-picker');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await back();
    await back();
    await pickChip(tester, 'Music');
    await shot('a14-music-artists');
    await pickView(tester, 'List with photos');
    await shot('a17-music-list-photos');
    await pickView(tester, 'Grid with photos');
    await shot('a18-music-grid');
    await pickView(tester, 'Text');
    await tapText('Alice in Chains');
    await shot('a15-artist');
    await tapText('Dirt');
    await shot('a22-album-details');
    await closeSheet(tester);
    await back();
    await pickChip(tester, 'All');

    // Plans.
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await shot('s5-plans');
    await tapText('Halloween 2026');
    await shot('s2-s11-halloween-timeline');
    await tester.tap(find.bySemanticsLabel('Choose year'));
    await tester.pumpAndSettle();
    await shot('s1-year-menu');
    await tapText('2026');
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await shot('d3-plan-menu');
    await tapText('Delete plan');
    await shot('d5-delete-plan');
    await tapText('Cancel');
    await tapText('All Halloween');
    await shot('s4-pool');
    await tapText('This plan');
    await tapText('The Mummy');
    await shot('s7-plan-entry');
    await tester.tap(
      find.descendant(
        of: find.byType(PlanEntrySheet),
        matching: find.text('Oct 19–31'),
      ),
    );
    await tester.pumpAndSettle();
    await shot('d2-when');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove'));
    await tapText('Remove');
    await shot('d4-remove');
    await tapText('Cancel');
    await closeSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('Plans'),
      ),
    );
    await tester.pumpAndSettle();
    await tapText('Christmas 2026');
    await shot('s1-s12-christmas-checklist');
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tapText('Edit plan');
    await shot('s9-edit-plan');
    await back();
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('Plans'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await shot('s10-new-plan');
    await back();

    // Settings, connection, banners and the first run.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await shot('s6-settings');
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    await tester.pumpAndSettle();
    await shot('s6-settings-bottom');
    await tester.ensureVisible(find.text('Libri'));
    await tester.pumpAndSettle();
    await tapText('Libri');
    await shot('d19-about');
    await tester.scrollUntilVisible(find.text('AniList'), 300);
    await tester.pumpAndSettle();
    await shot('d19-about-bottom');
    await back();
    await tapText('Library source');
    await shot('d6-connection');
    await back();
    await back();
    final banners = container.read(syncBannerProvider.notifier);
    banners.show(SyncBanner.couldNotSave);
    await tester.pumpAndSettle();
    await shot('a12-could-not-save');
    banners.show(SyncBanner.offline);
    await tester.pumpAndSettle();
    await shot('a12-offline');
    banners.show(SyncBanner.conflict);
    await tester.pumpAndSettle();
    await shot('a27-conflict');
    banners.show(SyncBanner.notFound);
    await tester.pumpAndSettle();
    await shot('a12-not-found');
    banners.show(SyncBanner.tokenExpired);
    await tester.pumpAndSettle();
    await shot('a12-token-expired');
    banners.clear();
    await tester.pumpAndSettle();
    container
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: false);
    await tester.pumpAndSettle();
    await shot('f2-welcome');
    await tapText('Get started');
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await shot('f3-connect');
    await tapText('Connect');
    await shot('f4-branch');
    await tapText('Continue');
    await shot('f5-file');
    await tapText('Continue');
    await shot('f6-create');
    await back();
    await tapText('Use a file I already have');
    await tapText('Continue');
    await shot('f7-existing');
    await tapText('Use this file');
    await shot('f8-done');
    await tapText('Open Libri');

    // First run › Splash, on a cold start without a connection.
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...fakeLookupOverrides(),
          initialConnectionProvider.overrideWithValue(
            LibraryConnection.disconnected,
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pump();
    ProviderScope.containerOf(tester.element(find.byType(LibraryApp)))
        .read(displayPreferencesProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pump();
    await shot('f1-splash');
    await tester.pump(FirstRunFlow.splashDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('plans: overview, checklist, timeline, pool, dialogs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(),
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await capture(tester, 's5-plans');

    // Plans › Plans with the sync conflict banner.
    final plansBanners = ProviderScope.containerOf(
      tester.element(find.byType(LibraryApp)),
    ).read(syncBannerProvider.notifier);
    plansBanners.show(SyncBanner.conflict);
    await tester.pumpAndSettle();
    await capture(tester, 's15-plans-conflict');
    plansBanners.clear();
    await tester.pumpAndSettle();

    // Plans › Halloween touches and Plan with timing on: the Halloween plan has
    // the timeline on.
    await tester.tap(find.text('Halloween 2026'));
    await tester.pumpAndSettle();
    await capture(tester, 's2-s11-halloween-timeline');
    await tester.tap(find.bySemanticsLabel('Choose year'));
    await tester.pumpAndSettle();
    await capture(tester, 's1-year-menu');
    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();
    await capture(tester, 's1-s11-halloween-checklist');
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await capture(tester, 'd3-plan-menu');
    await tester.tap(find.text('Delete plan'));
    await tester.pumpAndSettle();
    await capture(tester, 'd5-delete-plan');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Halloween'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions: Hereditary'));
    await tester.pumpAndSettle();
    await capture(tester, 's4-pool');
    await tester.tap(find.text('This plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Choose year'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();

    // Plans › Entry details (timeline on), When: a day or a period, and Remove
    // from plan, or everywhere, from an item on the timeline.
    await tester.tap(find.text('The Mummy'));
    await tester.pumpAndSettle();
    await capture(tester, 's7-plan-entry');
    await tester.tap(
      find.descendant(
        of: find.byType(PlanEntrySheet),
        matching: find.text('Oct 19–31'),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'd2-when');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await capture(tester, 'd4-remove');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await closeSheet(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('Plans'),
      ),
    );
    await tester.pumpAndSettle();

    // Plans › Christmas touches and Plan checklist: the Christmas checklist;
    // then Edit plan and New plan.
    await tester.tap(find.text('Christmas 2026'));
    await tester.pumpAndSettle();
    await capture(tester, 's1-s12-christmas-checklist');
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit plan'));
    await tester.pumpAndSettle();
    await capture(tester, 's9-edit-plan');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('Plans'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AddButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy a plan'));
    await tester.pumpAndSettle();
    await capture(tester, 's10-new-plan');
  });

  testWidgets('the home with nothing to show', (tester) async {
    // Library › Home: nothing to show. No release ahead, nothing In progress
    // and nothing added in the last 30 days; the plan card stays.
    final fixture = decodeLibrary(
      await File(FixtureLibraryRepository.assetPath).readAsString(),
    );
    final quiet = fixture.copyWith(
      entries: [
        for (final e in fixture.entries)
          if (e.status != EntryStatus.inProgress &&
              upcomingRelease(e, homeDay) == null)
            e.copyWith(added: DateTime(2025, 1, 1)),
      ],
    );
    seasonClock = () => homeDay;
    addTearDown(() => seasonClock = DateTime.now);
    for (final scale in [1.0, 1.3]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(scale),
          overrides: [
            ...fakeLookupOverrides(),
            libraryRepositoryProvider.overrideWithValue(
              FixtureLibraryRepository(
                loadJson: () async => encodeLibrary(quiet),
              ),
            ),
          ],
          child: RepaintBoundary(
            key: _root,
            child: MediaQuery(
              data: MediaQueryData.fromView(tester.view)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const LibraryApp(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(
        tester,
        scale == 1.0 ? 'a1c-home-nothing' : 'large-text-a1c-home-nothing',
      );
    }
  });

  testWidgets('long lists with the rail and the grid thumb', (tester) async {
    // Enough entries for three screens, spread over the decades.
    final long = padForLongLists(
      decodeLibrary(
        await File(FixtureLibraryRepository.assetPath).readAsString(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(loadJson: () async => encodeLibrary(long)),
          ),
        ],
        child: RepaintBoundary(key: _root, child: const LibraryApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    await capture(tester, 'l2-rail-newest-added');

    // The header scrolls away with the list; Library in the pill brings it back
    // (Library › Home, DESIGN.md section 3).
    await tester.drag(find.byType(EntryRow).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await capture(tester, 'a4-movies-scrolled');
    await tester.tap(find.widgetWithText(FloatingNavBar, 'Library'));
    await tester.pumpAndSettle();
    expect(find.text('Newest added'), findsOneWidget);

    // Library › Filter sheet with a long group as a row, and Filter: all
    // Authors behind it. From All: the authors are on books, so Movies alone
    // would hide the group (Library › Filter sheet).
    await pickChip(tester, 'All');
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    final authorsRow = find.widgetWithText(TagGroupRow, 'Authors');
    await tester.scrollUntilVisible(authorsRow, 200, scrollable: sheetList());
    await tester.pumpAndSettle();
    await capture(tester, 'a2-filter-long-group');
    await tester.tap(authorsRow);
    await tester.pumpAndSettle();
    await capture(tester, 'a28-tag-list');
    await tester.tap(find.text('Agatha Christie'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'le');
    await tester.pumpAndSettle();
    await capture(tester, 'a28-tag-list-search');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await capture(tester, 'a2-filter-long-group-picked');
    await closeSheet(tester);
    await pickChip(tester, 'Movies');

    await revealHeader(tester);
    await tester.tap(find.text('Newest added'));
    await tester.pumpAndSettle();
    await revealHeader(tester);
    await tester.tap(find.text('Year, newest first'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90s'));
    await tester.pumpAndSettle();
    await capture(tester, 'l1-rail-year');

    await revealHeader(tester);
    await tester.tap(find.text('Year, newest first'));
    await tester.pumpAndSettle();
    await revealHeader(tester);
    await tester.tap(find.text('Rating, highest first'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await capture(tester, 'l1-rail-rating');
    await revealHeader(tester);
    await tester.tap(find.text('Rating, highest first'));
    await tester.pumpAndSettle();
    await revealHeader(tester);
    await tester.tap(find.text('Year, newest first'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    await revealHeader(tester);
    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid with covers'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(342, 330));
    await tester.pump();
    await gesture.moveTo(const Offset(342, 520));
    await tester.pump(const Duration(milliseconds: 250));
    await capture(tester, 'l4-grid-thumb');
    await gesture.up();
    await tester.pumpAndSettle();

    // Library › Filtered results, one type and several types.
    final container = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );
    container
        .read(libraryFilterProvider.notifier)
        .set(
          // A lone type filter is the type view; one more filter makes Library
          // › Filtered results, one type.
          const LibraryFilter(
            types: {MediaType.movies},
            includeSeasonalOnly: true,
          ),
        );
    container
        .read(displayPreferencesProvider.notifier)
        .setFilteredSort(LibrarySort.yearNewest);
    await tester.pumpAndSettle();
    await tester.tap(find.text('00s'));
    await tester.pumpAndSettle();
    await capture(tester, 'l5-filtered-one-type');
    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(tags: {'halloween'}, types: {}));
    await tester.pumpAndSettle();
    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(types: {MediaType.movies, MediaType.shows}));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rail-dot-Shows')));
    await tester.pumpAndSettle();
    await capture(tester, 'l6-filtered-several-types');

    // Library › Long list: music artists A–Z: the alphabet rail on a long
    // artist list.
    container.read(libraryFilterProvider.notifier).clear();
    await tester.pumpAndSettle();
    await pickChip(tester, 'Music');
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();
    await capture(tester, 'l3-rail-artists');
  });

  testWidgets('the long tag group and all Authors at a larger text size', (
    tester,
  ) async {
    final long = padForLongLists(
      decodeLibrary(
        await File(FixtureLibraryRepository.assetPath).readAsString(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(loadJson: () async => encodeLibrary(long)),
          ),
        ],
        child: RepaintBoundary(
          key: _root,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: const LibraryApp(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    final authorsRow = find.widgetWithText(TagGroupRow, 'Authors');
    await tester.scrollUntilVisible(authorsRow, 200, scrollable: sheetList());
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a2-filter-long-group');
    await tester.tap(authorsRow);
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a28-tag-list');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await closeSheet(tester);
  });

  testWidgets('pick a match lookup states: looking up, offline, not set up', (
    tester,
  ) async {
    for (final (name, overrides) in [
      (
        'a13-looking-up',
        fakeLookupOverrides(latency: const Duration(seconds: 30)),
      ),
      ('a13-offline', fakeLookupOverrides(failure: LookupFailure.offline)),
      ('a13-not-set-up', fakeLookupOverrides(configured: false)),
    ]) {
      // The root key would carry the last state's open screen over into
      // the next scope; tear the tree down between them.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            libraryRepositoryProvider.overrideWithValue(
              FixtureLibraryRepository(),
            ),
            ...overrides,
          ],
          child: RepaintBoundary(key: _root, child: const LibraryApp()),
        ),
      );
      // The fixture loads off the frame clock, so settling is not enough.
      for (
        var i = 0;
        i < 50 && find.byType(AddButton).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AddButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Carrie');
      // Plain pumps: the spinner of the first state never settles.
      await tester.pump(NewEntryScreen.debounce);
      await tester.pump(const Duration(milliseconds: 200));
      await capture(tester, name);
    }
  });
}

/// The fake lookup, whose series lists fail while [failing] is set.
class _FlakySeries extends FakeLookupSource {
  bool failing = false;

  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    if (failing) throw const LookupException(LookupFailure.offline);
    return super.seriesParts(source, name: name);
  }
}
