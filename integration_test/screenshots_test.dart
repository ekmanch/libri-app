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
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/dev/long_lists.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/data/storage/connection_store.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
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
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/entry_row.dart';
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

/// D6 as the artboard draws it: synced a few minutes ago. The fixture has
/// no sync of its own.
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

/// The home's header is part of its scroll (A1), so after a list has been
/// scrolled the search box or the chips may be off screen and not built:
/// jump every vertical list back to the top first.
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

/// Closes the open sheet with the system back, like the phone's gesture.
/// A tall sheet (A22) can leave no scrim to tap on a 780 dp screen.
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

Future<void> pickView(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Change view'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// A29 to A33 at [scale]: the show rows with a new season, the Seasons
/// section with few and many seasons, all seasons, and the status sheet
/// with catch-up. Severance gets a new season 3 (the daily check's work,
/// applied directly). Captures are prefixed "large-text-" above 1.
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

  // A30: a new season just out.
  await openShow('Severance');
  await capture(tester, '${prefix}a30-show-new-season');
  await toSeasons();
  await capture(tester, '${prefix}a30-show-new-season-seasons');
  await closeSheet(tester);

  // A29: a few seasons, all listed.
  await revealHeader(tester);
  await openShow('Twin Peaks');
  await toSeasons();
  await capture(tester, '${prefix}a29-show-seasons');
  await closeSheet(tester);

  // A31 and A32: many seasons.
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

  // A33: the status sheet with catch-up.
  await revealHeader(tester);
  await openShow('Stranger Things');
  final pill = find.bySemanticsLabel(RegExp('^Season 5 status: '));
  await tester.ensureVisible(pill);
  await tester.pumpAndSettle();
  await tester.tap(pill);
  await tester.pumpAndSettle();
  await capture(tester, '${prefix}a33-season-status-catch-up');
  await closeSheet(tester);
  await closeSheet(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('show seasons', (tester) async {
    await walkSeasons(tester);
  });

  testWidgets('show seasons at a larger text size', (tester) async {
    await walkSeasons(tester, scale: 1.3);
  });

  testWidgets('library screens in dark and light', (tester) async {
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

    // A4 and A21: Movies picked, text and grid.
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
    await tester.tap(find.textContaining('Show '));
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

    // A2 and L5: filter to shows tagged horror.
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
    await tester.tap(find.textContaining('Show '));
    await tester.pumpAndSettle();
    await capture(tester, 'l5-filtered-short');
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    // A5: search.
    await tester.tap(find.text('Search titles and tags'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hal');
    await tester.pumpAndSettle();
    await capture(tester, 'a5-search');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A6, D11, A7, A9: the details sheet and what opens from it.
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    // Movies is still in the grid view, so the sheet shows the cover spot.
    // A tile carries the title twice: on the placeholder and as the caption.
    await tester.ensureVisible(find.text('The Mummy').last);
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

    // A8 edit, the tag picker, D9 and D10.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await capture(tester, 'a8-edit-entry');
    await tester.ensureVisible(find.text('#adventure'));
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
    await pickChip(tester, 'All');

    // A13: a new entry, picking a match.
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

    // A8 from a movie match (Back lands on A13 again): the billed cast as
    // actor suggestions, D10 starting on Actors, and the picker's "New on
    // this entry" group.
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

    // A14, A17, A18: the music tabs in the three views.
    await pickChip(tester, 'Music');
    await capture(tester, 'a14-music-artists');
    await pickView(tester, 'List with photos');
    await capture(tester, 'a17-music-list-photos');
    await pickView(tester, 'Grid with photos');
    await capture(tester, 'a18-music-grid');
    await pickView(tester, 'Text');

    // A15: one artist; A22: an album with its tracks.
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

    // A3 for music: opened from Songs, the sheet has Music + Songs; Albums
    // instead comes back as the Albums tab (A24).
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await capture(tester, 'a3-filter-from-music-songs');
    await tester.tap(find.textContaining('Show '));
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
    await tester.tap(find.textContaining('Show '));
    await tester.pumpAndSettle();
    await capture(tester, 'a24-music-albums');
    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();

    // D12: saving an album whose song is already saved.
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

    // D8: home in light.
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

    // A10: a filter nothing matches.
    container
        .read(libraryFilterProvider.notifier)
        .set(const LibraryFilter(tags: {'horror', 'cozy', 'jazz'}));
    await tester.pumpAndSettle();
    await capture(tester, 'a10-empty-filter');
    container.read(libraryFilterProvider.notifier).clear();
    await tester.pumpAndSettle();

    // A8 with "Look up again", and A13 as the picker it opens (phase 5).
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

    // A20: Movies as a list with covers.
    await pickChip(tester, 'Movies');
    await pickView(tester, 'List with covers');
    await capture(tester, 'a20-movies-list-covers');
    await pickView(tester, 'Text');

    // A19: an artist with photos.
    await pickChip(tester, 'Music');
    await pickView(tester, 'List with photos');
    await tester.tap(find.text('Alice in Chains'));
    await tester.pumpAndSettle();
    await capture(tester, 'a19-artist-photos');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await pickView(tester, 'Text');

    // D13: a song whose album is saved.
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

    // S8 and the plan note; the linked tags and copy-from sheets.
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
    await pickChip(tester, 'Movies');
    await capture(tester, 'large-text-a4-movies');
    await tester.ensureVisible(segment('Done'));
    await tester.tap(segment('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await capture(tester, 'large-text-a3-filter-from-movies-done');
    await tester.tap(find.textContaining('Show '));
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
    // D10 with its ten category chips: a new suggested tag opens it.
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

    // S6, D6, F3 and A12 at the larger text size.
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

    // F4 at the larger text size: the first run after the library is
    // deleted from the phone (D16), up to the branch list.
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

    // A12: the four banners on the home.
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
    // D17 from the conflict banner's Choose.
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await capture(tester, 'd17-conflict');
    await tester.tap(find.text('Decide later'));
    await tester.pumpAndSettle();
    banners.clear();
    await tester.pumpAndSettle();

    // S6 top and bottom, D6.
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

    // Disconnect is two steps (D15, D16); deleting the library from the
    // phone starts the first run at the welcome screen (F2).
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

    // D6 with the library kept on this phone (D16, "Keep it on this phone").
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

    // D18: connecting again and picking another file than the kept one.
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
    // F7 to F5 to F4 to F3, then F3 pops back to D6.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    // The navigator outlives the scope swap (the root key), so leave D6
    // and Settings before the next one.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // F1: the splash, on a cold start without a connection.
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

    // D6 with changes that could not be saved, and its Disconnect dialog.
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

    // D7: a library that never finishes loading.
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
  /// D20 and the "Token expired" state.
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

  testWidgets('D20 token expiry warning in dark and light', (tester) async {
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

  testWidgets('D20 at a larger text size', (tester) async {
    await pumpWithToken(
      tester,
      tokenExpires: DateTime.now().add(const Duration(days: 1)),
      textScale: 1.3,
    );
    await capture(tester, 'large-text-d20-token-expiry');
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
  });

  testWidgets('an expired token on the home and in D6', (tester) async {
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
    await tester.tap(find.textContaining('Show '));
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
    await tester.tap(find.textContaining('Show '));
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
    await tester.ensureVisible(find.text('The Mummy').last);
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
    await tester.ensureVisible(find.text('#adventure'));
    await tapText('#adventure');
    await shot('d14-tag-picker');
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

    // F1: the splash, on a cold start without a connection.
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

    // S15: the conflict banner on the plans overview.
    final plansBanners = ProviderScope.containerOf(
      tester.element(find.byType(LibraryApp)),
    ).read(syncBannerProvider.notifier);
    plansBanners.show(SyncBanner.conflict);
    await tester.pumpAndSettle();
    await capture(tester, 's15-plans-conflict');
    plansBanners.clear();
    await tester.pumpAndSettle();

    // S11 and S2: the Halloween plan has the timeline on.
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

    // S7, D2, D4 from an item on the timeline.
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

    // S12 and S1: the Christmas checklist; S9 and S10.
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

    // The header scrolls away with the list; Library in the pill brings
    // it back (A1, DESIGN.md section 3).
    await tester.drag(find.byType(EntryRow).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await capture(tester, 'a4-movies-scrolled');
    await tester.tap(find.widgetWithText(FloatingNavBar, 'Library'));
    await tester.pumpAndSettle();
    expect(find.text('Newest added'), findsOneWidget);

    // A2 with a long group as a row, and A28 behind it. From All: the
    // authors are on books, so Movies alone would hide the group (A2).
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

    // L5 and L6: filtered results, one type and several types.
    final container = ProviderScope.containerOf(
      tester.element(find.text('Library').first),
    );
    container
        .read(libraryFilterProvider.notifier)
        .set(
          // A lone type filter is the type view; one more filter makes L5.
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

    // L3: the alphabet rail on a long artist list.
    container.read(libraryFilterProvider.notifier).clear();
    await tester.pumpAndSettle();
    await pickChip(tester, 'Music');
    await tester.tap(find.text('M'));
    await tester.pumpAndSettle();
    await capture(tester, 'l3-rail-artists');
  });

  testWidgets('the long tag group and A28 at a larger text size', (
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

  testWidgets('A13 lookup states: looking up, offline, not set up', (
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
