import 'dart:async';

// Phase 1g accessibility audit. Walks the app at the phone size in dark,
// light and at text scale 1.3 and runs Flutter's accessibility guidelines
// (48 dp tap targets, labels on tappables, text contrast) at every stop.
// Findings are written to a report file and printed; this is an audit, so
// the test itself passes. The fixes turn the findings into assertions.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/dev/long_lists.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/platform_picker_sheet.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/features/shell/floating_nav_bar.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/features/sync/token_expiry_dialog.dart';
import 'package:library_app/main.dart';
import 'package:library_app/widgets/app_dialog.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/features/entry/tag_picker_sheet.dart';
import 'package:library_app/widgets/tag_group.dart';
import 'package:library_app/features/library/filter_sheet.dart';

import '../helpers/fonts.dart';
import '../helpers/package_info.dart';
import '../helpers/pump_app.dart';

const _reportPath = String.fromEnvironment(
  'A11Y_REPORT',
  defaultValue: 'build/a11y_report.txt',
);

class _Audit {
  _Audit(this.tester, this.label);

  final WidgetTester tester;
  final String label;
  final findings = <String>[];
  final failures = <String>[];

  static final _guidelines = [
    androidTapTargetGuideline,
    labeledTapTargetGuideline,
    textContrastGuideline,
  ];

  Future<void> check(String screen) async {
    for (final g in _guidelines) {
      final result = await g.evaluate(tester);
      if (!result.passed) {
        findings.add('[$label] $screen · ${g.description}:\n${result.reason}');
      }
      // The audit runs on failure only; nothing is asserted here.
    }
  }

  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, stack) {
      final where = stack
          .toString()
          .split('\n')
          .where((l) => l.contains('a11y_audit_test.dart'))
          .take(2)
          .join(' <- ');
      failures.add(
        '[$label] $name: ${e.toString().split('\n').first} at $where',
      );
      await recover();
    }
  }

  /// After a failed step: close sheets, dialogs and pushed screens, and go
  /// back to the Library home, so the next step starts where it expects.
  Future<void> recover() async {
    final shell = find.byType(AppShell);
    if (shell.evaluate().isEmpty) return;
    Navigator.of(
      tester.element(shell),
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  }

  /// Scrolls the screen's vertical lists until [finder] is built: at a
  /// large text size a row may be off screen and not built yet.
  Future<void> reveal(Finder finder) async {
    bool missing() {
      try {
        return finder.evaluate().isEmpty;
      } on StateError {
        return true;
      }
    }

    for (var i = 0; i < 12 && missing(); i++) {
      final lists = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      if (lists.evaluate().isEmpty) return;
      await tester.drag(lists.last, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(Finder finder) async {
    // At a large text size a target may sit below the fold of a sheet.
    await reveal(finder);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(String text) async {
    await reveal(find.text(text));
    await tap(find.text(text).last);
  }

  Future<void> back() => tap(find.byTooltip('Back'));

  Future<void> closeSheet() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> navTab(String label) => tap(
    find.descendant(
      of: find.byType(FloatingNavBar),
      matching: find.text(label),
    ),
  );

  Future<void> pickChip(String label) async {
    await revealHeader(tester);
    final chip = find.widgetWithText(PillChip, label);
    final row = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    await tester.dragUntilVisible(
      chip,
      row,
      Offset(label == 'Home' ? 80 : -80, 0),
    );
    await tester.pumpAndSettle();
    await tap(chip);
  }

  Future<void> pickView(String label) async {
    await tap(find.byTooltip('Change view'));
    await tapText(label);
  }
}

Future<void> _walk(_Audit a, ProviderContainer container) async {
  final tester = a.tester;
  await a.step('home', () => a.check('Library › Home'));
  await a.step('movies', () async {
    await a.pickChip('Movies');
    await a.check('Library › Movies, text view');
    await a.pickView('Grid with covers');
    await a.check('Library › Movies, grid with covers');
    await a.tap(find.byTooltip('Change view'));
    await a.check('Library › View menu open');
    await a.tapText('Text');
    await a.tapText('Newest added');
    await a.check('Library › Sort menu');
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
  });
  await a.step('filter', () async {
    await a.tap(find.byTooltip('Filters'));
    await a.tap(find.widgetWithText(PillChip, '#horror'));
    await a.check('Library › Filter sheet');
    await a.tap(
      find.descendant(
        of: find.byType(FilterSheet),
        matching: find.textContaining('Show '),
      ),
    );
    await a.check('Library › Filtered results, one type');
    await a.tapText('Clear all');
  });
  await a.step('search', () async {
    await a.pickChip('Home');
    await a.tapText('Search titles and tags');
    await tester.enterText(find.byType(TextField), 'hal');
    await tester.pumpAndSettle();
    await a.check('Library › Search');
    await a.tapText('Cancel');
  });
  await a.step('details', () async {
    await a.pickChip('Movies');

    await a.tapText('The Mummy');
    await a.check('Library › Entry details');
    await a.tapText('9 / 10');
    await a.check('Library › Rating picker');
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
    await a.tapText('Add to plan');
    await a.check('Library › Add to plan');
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.ensureVisible(find.text('Delete'));
    await a.tapText('Delete');
    await a.check('Library › Delete confirmation');
    await a.tapText('Cancel');
    await a.tapText('Edit');
    await a.check('Add / edit entry');
    await a.tap(find.bySemanticsLabel('Cover. Tap to change'));
    await a.check('Add / edit entry › Pick a cover');
    await a.tap(find.bySemanticsLabel(RegExp(r', 2009\b')).first);
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
    await a.check('Add / edit entry › Cover from another match');
    await a.reveal(find.text('#adventure'));
    await a.tapText('#adventure');
    await a.check('Add / edit entry › Tag picker');
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
    await a.back();
    await a.closeSheet();
    await a.pickChip('Home');
  });
  await a.step('two categories', () async {
    await a.pickChip('Movies');
    await a.tapText('Million Dollar Baby');
    await a.check('Library › Entry details: tag in two categories');
    await a.tapText('Edit');
    await a.check('Add / edit entry › Tag in two categories: entry form');
    await a.tapText('#clint-eastwood · Director');
    await a.check('Add / edit entry › Tag in two categories: tag picker');
    final chip = find.descendant(
      of: find.widgetWithText(TagGroup, 'Directors'),
      matching: find.widgetWithText(PillChip, '#clint-eastwood'),
    );
    await a.reveal(chip);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.longPress(chip);
    await tester.pumpAndSettle();
    await a.check('Add / edit entry › Tag categories (long press)');
    await a.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('Cancel'),
      ),
    );
    // A one-category tag's long press offers the other such groups.
    await a.tap(
      find.descendant(
        of: find.byType(TagPickerSheet),
        matching: find.text('Other'),
      ),
    );
    final favorite = find.descendant(
      of: find.widgetWithText(TagGroup, 'Other'),
      matching: find.widgetWithText(PillChip, '#favorite'),
    );
    await a.reveal(favorite);
    await tester.ensureVisible(favorite);
    await tester.pumpAndSettle();
    await tester.longPress(favorite);
    await tester.pumpAndSettle();
    await a.check('Add / edit entry › Move a one-category tag (long press)');
    await a.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('Cancel'),
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'sergio-leone');
    await tester.pumpAndSettle();
    await a.tap(find.bySemanticsLabel('Create #sergio-leone'));
    await a.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(PillChip, 'Directors'),
      ),
    );
    await a.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(PillChip, 'Actors'),
      ),
    );
    await a.check('Add / edit entry › New tag: two categories');
    await a.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text('Cancel'),
      ),
    );
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
    await a.back();
    await a.closeSheet();
    await a.pickChip('Home');
  });
  await a.step('seasons', () async {
    await a.pickChip('Shows');
    await a.tapText('What We Do in the Shadows');
    await a.reveal(find.text('All 6 seasons'));
    await tester.ensureVisible(find.text('All 6 seasons'));
    await tester.pumpAndSettle();
    await a.check('Show & seasons › Many seasons');
    await a.tapText('All 6 seasons');
    await a.check('Show & seasons › All seasons');
    await a.back();
    await a.closeSheet();
    await a.tapText('Stranger Things');
    await a.tap(find.bySemanticsLabel(RegExp('^Season 5 status: ')));
    await a.check('Show & seasons › season status with catch-up');
    await a.closeSheet();
    await a.tap(find.bySemanticsLabel(RegExp(r'^Season 1, .*Episodes$')));
    await a.check('Show & seasons › Season episodes');
    await a.back();
    await a.tapText('Edit');
    await a.check('Add / edit entry › Edit a show');
    await a.back();
    await a.closeSheet();
    await a.tapText('The Haunting of Hill House');
    await a.check('Show & seasons › One season');
    await a.closeSheet();
    await a.pickChip('Home');
  });
  await a.step('series', () async {
    await a.pickChip('Movies');
    await a.tapText('The Lord of the Rings: The Fellowship of the Ring');
    await a.reveal(find.text('SERIES'));
    await tester.ensureVisible(find.text('SERIES'));
    await tester.pumpAndSettle();
    await a.check('Library › Movie in a series');
    await a.closeSheet();
    await a.pickChip('Books');
    await a.tapText('Berserk, Vol. 43');
    await a.reveal(find.text('All 43 volumes'));
    await tester.ensureVisible(find.text('All 43 volumes'));
    await tester.pumpAndSettle();
    await a.check('Library › Book in a long series');
    await a.tapText('All 43 volumes');
    await a.check('Library › All volumes in a series');
    await a.back();
    await a.closeSheet();
    await a.pickChip('Anime');
    await a.tapText("Frieren: Beyond Journey's End");
    await a.check('Show & seasons › Anime with seasons');
    await a.tap(find.bySemanticsLabel(RegExp(r'^Season 2, .*Episodes$')));
    await a.check('Show & seasons › Anime season episodes');
    await a.back();
    await a.closeSheet();
    await a.pickChip('Home');
  });
  await a.step('new entry', () async {
    await a.tap(find.byType(AddButton));
    await tester.enterText(find.byType(TextField), 'The Last of Us');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
    await a.check('Add / edit entry › New entry: pick a match');
    await a.tapText('GAME · 2013');
    await a.check('Add / edit entry › New game from a match');
    await a.back();
    await a.back();
  });
  await a.step('game search on a platform', () async {
    await a.tap(find.byType(AddButton));
    final games = find.widgetWithText(PillChip, 'Games');
    await tester.dragUntilVisible(
      games,
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await a.tap(games);
    await tester.enterText(find.byType(TextField), 'Street Fighter II');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
    await a.tap(
      find
          .descendant(
            of: find.byType(PlatformChip),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await a.check('Add / edit entry › Platform picker');
    await tester.enterText(find.byType(TextField).last, 'snes');
    await tester.pumpAndSettle();
    await a.tapText('Super Nintendo');
    await a.check('Add / edit entry › Game search on a platform');
    await a.back();
  });
  await a.step('music', () async {
    await a.pickChip('Music');
    await a.check('Library › Music: artists, text view');
    await a.pickView('List with photos');
    await a.check('Library › Music: artists, list with photos');
    await a.pickView('Text');
    await a.tapText('Alice in Chains');
    await a.check('Music › Artist, text view');
    await a.tapText('Dirt');
    await a.check('Music › Album with track ratings');
    await a.closeSheet();
    await a.back();
    await a.tapText('Albums');
    await a.check('Library › Music: albums tab');
    await a.tapText('Songs');
    await a.check('Library › Music: songs tab');
    await a.pickChip('Home');
  });
  await a.step('plans', () async {
    await a.navTab('Plans');
    await a.check('Plans › Plans overview');
    await a.tapText('Halloween 2026');
    await a.check('Plans › Plan with timing on, Halloween touches');
    await a.tap(find.bySemanticsLabel('Choose year'));
    await a.check('year menu');
    await a.tapText('2026');
    await a.tapText('All Halloween');
    await a.check('Plans › All Halloween: add, edit, remove');
    await a.tapText('This plan');
    await a.tapText('The Mummy');
    await a.check('Plans › Entry details (timeline on)');
    await a.tapText('Oct 19–31');
    await a.check('Plans › When: a day or a period');
    await a.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.ensureVisible(find.text('Remove'));
    await a.tapText('Remove');
    await a.check('Plans › Remove from plan, or everywhere');
    await a.tapText('Cancel');
    await a.closeSheet();
    await a.tap(find.byTooltip('Plan options'));
    await a.check('Plans › Plan menu');
    await a.tapText('Delete plan');
    await a.check('Plans › Delete plan');
    await a.tapText('Cancel');
    await a.tap(find.byTooltip('Plan options'));
    await a.tapText('Edit plan');
    await a.check('Plans › Edit plan');
    await a.back();
    await a.navTab('Plans');
    await a.tapText('Christmas 2026');
    await a.check('Plans › Plan checklist, Christmas touches');
    await a.tapText('Die Hard');
    await a.check('Plans › Entry details (timeline off)');
    await a.closeSheet();
    await a.navTab('Plans');
    await a.tap(find.byType(AddButton));
    await a.check('Plans › New plan');
    await a.back();
  });
  await a.step('settings', () async {
    await a.tap(find.byTooltip('Settings'));
    await a.check('Settings, top');
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    await tester.pumpAndSettle();
    await a.check('Settings, bottom');
    await tester.ensureVisible(find.text('Libri'));
    await tester.pumpAndSettle();
    await a.tapText('Libri');
    await a.check('Settings › About Libri');
    await a.back();
    await a.tapText('Library source');
    await a.check('Settings › Library connection');
    await a.tapText('Disconnect');
    await a.check('Settings › Disconnect: confirm');
    await a.tapText('Cancel');
    await a.back();
    await a.back();
  });
  await a.step('banner', () async {
    final banners = container.read(syncBannerProvider.notifier);
    banners.show(SyncBanner.couldNotSave);
    await tester.pumpAndSettle();
    await a.check('Library › Sync and errors: could not save');
    banners.show(SyncBanner.offline);
    await tester.pumpAndSettle();
    await a.check('Library › Sync and errors: offline');
    banners.show(SyncBanner.notFound);
    await tester.pumpAndSettle();
    await a.check('Library › Sync and errors: not found');
    banners.show(SyncBanner.tokenExpired);
    await tester.pumpAndSettle();
    await a.check('Library › Sync and errors: token expired');
    banners.clear();
    await tester.pumpAndSettle();
    // Library › Token expires soon, as the shell shows it in the token's last
    // week.
    unawaited(
      showTokenExpiryDialog(
        tester.element(find.text('Library').first),
        repository: 'ekmanch/library',
        expires: DateTime.now().add(const Duration(days: 6)),
      ),
    );
    await tester.pumpAndSettle();
    await a.check('Library › Token expires soon');
    await a.tapText('Later');
  });
  await a.step('first run', () async {
    // Deleting the library from the phone (Settings › Disconnect: keep or
    // delete) starts the first run at the welcome screen.
    container
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: false);
    await tester.pumpAndSettle();
    await a.check('First run › Welcome');
    await a.tapText('Get started');
    await a.check('First run › Connect GitHub');
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await a.tapText('Connect');
    await a.check('First run › Pick a branch');
    await a.tapText('Continue');
    await a.check('First run › Library file: new or existing');
    await a.tapText('Continue');
    await a.check('First run › Create a new library');
    await a.back();
    await a.tapText('Use a file I already have');
    await a.tapText('Continue');
    await a.check('First run › Pick an existing file');
    await a.tapText('Use this file');
    await a.check('First run › All set');
    await a.tapText('Open Libri');
  });
  await a.step('cold start', () async {
    // First run › Splash, on a cold start without a connection.
    final mode = container.read(displayPreferencesProvider).themeMode;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeLookupOverrides(),
          initialConnectionProvider.overrideWithValue(
            LibraryConnection.disconnected,
          ),
        ],
        child: const LibraryApp(),
      ),
    );
    await tester.pump();
    ProviderScope.containerOf(tester.element(find.byType(LibraryApp)))
        .read(displayPreferencesProvider.notifier)
        .setThemeMode(mode);
    await tester.pump();
    await a.check('First run › Splash');
    await tester.pump(FirstRunFlow.splashDuration);
    await tester.pumpAndSettle();
  });
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

void main() {
  setUpAll(loadAppFonts);
  setUpAll(mockPackageInfo);

  final report = <String>[];
  final failures = <String>[];

  for (final (label, mode, scale) in [
    ('dark', ThemeMode.dark, 1.0),
    ('light', ThemeMode.light, 1.0),
    ('dark x1.3', ThemeMode.dark, 1.3),
  ]) {
    testWidgets('audit $label', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final handle = tester.ensureSemantics();
      final container = ProviderContainer(
        overrides: [
          ...fakeLookupOverrides(),
          libraryRepositoryProvider.overrideWithValue(
            FixtureLibraryRepository(
              loadJson: () async => encodeLibrary(loadFixture()),
            ),
          ),
          gitHubApiFactoryProvider.overrideWithValue(
            ({required token, required repository}) =>
                FakeGitHubApi.demo(encodeLibrary(loadFixture())),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(displayPreferencesProvider.notifier).setThemeMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LibraryApp(),
        ),
      );
      await tester.pumpAndSettle();
      final audit = _Audit(tester, label);
      await _walk(audit, container);
      handle.dispose();
      report.addAll(audit.findings);
      failures.addAll(audit.failures);
    });
  }

  // Library › Filter: all Authors needs a long tag group, which the fixture has
  // not; the dev padding gives Authors thirty tags.
  testWidgets('audit Library › Filter: all Authors', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final handle = tester.ensureSemantics();
    final long = padForLongLists(loadFixture());
    final container = ProviderContainer(
      overrides: [
        ...fakeLookupOverrides(),
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(loadJson: () async => encodeLibrary(long)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    final audit = _Audit(tester, 'dark');
    await audit.step(
      'Library › Filter sheet long group and all Authors',
      () async {
        await audit.tap(find.byTooltip('Filters'));
        final row = find.widgetWithText(TagGroupRow, 'Authors');
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find
              .descendant(
                of: find.byType(FilterSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await audit.check('Library › Filter sheet with a long group');
        await audit.tap(row);
        await audit.check('Library › Filter: all Authors');
        await audit.tapText('Stephen King');
        await tester.enterText(find.byType(TextField).last, 'le');
        await tester.pumpAndSettle();
        await audit.check('Library › Filter: all Authors, searching');
        await audit.back();
        await audit.closeSheet();
      },
    );
    // A long movie list groups The Lord of the Rings' two parts as one row,
    // which opens the series page, its menu and its two sheets.
    await audit.step('Library › Series row, series page and cover', () async {
      await audit.pickChip('Movies');
      // The row sits where its newest part would, well down the list.
      final row = find.text('The Lord of the Rings');
      await tester.scrollUntilVisible(
        row,
        300,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await audit.check('Library › Movies, text view with a series row');
      await audit.tap(row);
      await audit.check('Library › Series page (from a series row)');
      await audit.tap(find.byTooltip('Series options'));
      await audit.check('Library › Series page menu');
      await audit.tapText('Series cover');
      await audit.check('Library › Series cover');
      await audit.tap(find.widgetWithText(FilledButton, 'Done'));
      await audit.tap(find.byTooltip('Series options'));
      await audit.tapText('Choose what to show');
      await audit.check('Library › Series page: choose what to show');
      await audit.tap(find.bySemanticsLabel('The Return of the King'));
      await audit.tap(find.widgetWithText(FilledButton, 'Done'));
      await audit.check('Library › Series page: hidden parts');
      await audit.back();
    });
    handle.dispose();
    report.addAll(audit.findings);
    failures.addAll(audit.failures);
  });

  tearDownAll(() {
    final text = [
      '== Accessibility audit (${report.length} findings)',
      ...report,
      '',
      '== Steps that could not run (${failures.length})',
      ...failures,
    ].join('\n\n');
    File(_reportPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    // ignore: avoid_print
    print(text);
  });
}
