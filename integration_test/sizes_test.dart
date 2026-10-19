// The phase 1g screen sizes pass: a representative walk through the app at
// the four widths of TODO.md 1g (360 Galaxy S25, 402 iPhone 17, 412 Galaxy
// Ultra and Plus, 440 iPhone 17 Pro Max), each at text scale 1.0 and 1.3.
// Writes screenshots/sizes/<w>x<h>-s<scale>/<screen>.png. A step that fails
// is recorded and the walk goes on, so one broken screen does not hide the
// rest; the failures are printed at the end and the test then fails.
//
//   flutter test integration_test/sizes_test.dart -d linux
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/features/shell/floating_nav_bar.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/features/library/filter_sheet.dart';
import 'package:library_app/main.dart';
import 'package:library_app/widgets/chips.dart';

final _root = GlobalKey();

/// Width, height in dp and what the size stands for.
const _sizes = [
  (360, 780, 'Galaxy S25'),
  (402, 874, 'iPhone 17'),
  (412, 915, 'Galaxy Ultra and Plus'),
  (440, 956, 'iPhone 17 Pro Max'),
];
const _scales = [1.0, 1.3];

class _Walk {
  _Walk(this.tester, this.dir);

  final WidgetTester tester;
  final String dir;
  final failures = <String>[];

  Future<void> shot(String name) async {
    final boundary =
        _root.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('screenshots/sizes/$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  }

  /// Runs one step; a failure is noted and the walk continues.
  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, stack) {
      final line = e.toString().split('\n').first;
      // The walk's own frame, so the failing line can be found.
      final frame = stack
          .toString()
          .split('\n')
          .where((f) => f.contains('sizes_test.dart'))
          .map((f) => f.replaceAll(RegExp(r'\s+'), ' '))
          .join(' <- ');
      failures.add('$dir: $name: $line $frame');
      debugPrint('SIZES FAIL $dir: $name: $line $frame');
      // What the screen looked like when the step failed.
      await shot('FAIL-${name.replaceAll(' ', '-')}');
      await recover();
    }
  }

  /// After a failed step: close sheets, dialogs and pushed screens and go
  /// back to the Library home, so one failure does not cascade.
  Future<void> recover() async {
    final shell = find.byType(AppShell);
    if (shell.evaluate().isEmpty) return;
    Navigator.of(
      tester.element(shell),
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    // Back only while a navigator has something to pop: on the Library
    // root, back leaves the app (the shell calls SystemNavigator.pop), which
    // on Linux ends the whole run.
    for (var i = 0; i < 4; i++) {
      final canPop = find
          .byType(Navigator)
          .evaluate()
          .any(
            (e) => ((e as StatefulElement).state as NavigatorState).canPop(),
          );
      if (!canPop) break;
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
      Offset(label == 'All' ? 80 : -80, 0),
    );
    await tester.pumpAndSettle();
    await tap(chip);
  }

  Future<void> pickView(String label) async {
    await tap(find.byTooltip('Change view'));
    await tapText(label);
  }

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(LibraryApp)));
}

Future<void> _walk(_Walk w) async {
  final tester = w.tester;
  await w.step('a1-home', () => w.shot('a1-home'));
  await w.step('a4 and a21', () async {
    await w.pickChip('Movies');
    await w.shot('a4-movies-text');
    await w.pickView('Grid with covers');
    await w.shot('a21-movies-grid');
    await w.pickView('Text');
  });
  await w.step('a2 and a3', () async {
    await revealHeader(tester);
    await w.tap(find.byTooltip('Filters'));
    final horror = find.widgetWithText(PillChip, '#horror');
    await tester.scrollUntilVisible(
      horror,
      80,
      scrollable: find
          .descendant(
            of: find.byType(FilterSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await w.tap(horror);
    await w.shot('a2-filter-sheet');
    await w.tap(find.textContaining('Show '));
    await w.shot('l5-filtered-short');
    await w.tapText('Clear all');
  });
  await w.step('a5 search', () async {
    await w.pickChip('All');
    await revealHeader(tester);
    await w.tapText('Search titles and tags');
    await tester.enterText(find.byType(TextField), 'hal');
    await tester.pumpAndSettle();
    await w.shot('a5-search');
    await w.tapText('Cancel');
  });
  await w.step('a6, d11, a7, a9, a8-edit', () async {
    await w.pickChip('Movies');

    await w.tapText('The Mummy');
    await w.shot('a6-entry-details');
    await w.tapText('9 / 10');
    await w.shot('d11-rating');
    await w.tap(find.widgetWithText(FilledButton, 'Done'));
    await w.tapText('Add to plan');
    await w.shot('a7-add-to-plan');
    await w.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.ensureVisible(find.text('Delete'));
    await w.tapText('Delete');
    await w.shot('a9-delete');
    await w.tapText('Cancel');
    await w.tapText('Edit');
    await w.shot('a8-edit-entry');
    await w.back();
    await w.closeSheet();
    await w.pickChip('All');
  });
  await w.step('a13 and a8-new', () async {
    await revealHeader(tester);
    await w.tap(find.byType(AddButton));
    await tester.enterText(find.byType(TextField), 'The Last of Us');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
    await w.shot('a13-new-entry');
    await w.tapText('GAME · 2013');
    await w.shot('a8-new-entry');
    await tester.scrollUntilVisible(
      find.text('Suggested · tap to add'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await w.shot('a8-new-entry-tags');
    await w.back();
    await w.back();
  });
  await w.step('a14, a15, a22', () async {
    await w.pickChip('Music');
    await w.shot('a14-music-artists');
    await w.tapText('Alice in Chains');
    await w.shot('a15-artist');
    await w.tapText('Dirt');
    await w.shot('a22-album-details');
    await w.closeSheet();
    await w.back();
    await w.pickChip('All');
  });
  await w.step('plans', () async {
    await w.navTab('Plans');
    await w.shot('s5-plans');
    await w.tapText('Halloween 2026');
    await w.shot('s2-s11-halloween-timeline');
    await w.tapText('All Halloween');
    await w.shot('s4-pool');
    await w.tapText('This plan');
    await w.tapText('The Mummy');
    await w.shot('s7-plan-entry');
    await w.closeSheet();
    await w.tap(find.byTooltip('Plan options'));
    await w.shot('d3-plan-menu');
    await w.tapText('Edit plan');
    await w.shot('s9-edit-plan');
    await w.back();
    await w.navTab('Plans');
    await w.tapText('Christmas 2026');
    await w.shot('s1-s12-christmas-checklist');
    await w.navTab('Plans');
    await revealHeader(tester);
    await w.tap(find.byType(AddButton));
    await w.shot('s10-new-plan');
    await w.back();
  });
  await w.step('settings and connection', () async {
    await revealHeader(tester);
    await w.tap(find.byTooltip('Settings'));
    await w.shot('s6-settings');
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    await tester.pumpAndSettle();
    await w.shot('s6-settings-bottom');
    await w.tapText('Library source');
    await w.shot('d6-connection');
    await w.tapText('Disconnect');
    await w.shot('d6-disconnect-confirm');
    await w.tapText('Cancel');
    await w.back();
    await w.back();
  });
  await w.step('a12 banner', () async {
    final banners = w.container.read(syncBannerProvider.notifier);
    banners.show(SyncBanner.couldNotSave);
    await tester.pumpAndSettle();
    await w.shot('a12-could-not-save');
    banners.clear();
    await tester.pumpAndSettle();
  });
  await w.step('first run', () async {
    // Deleting the library from the phone (Settings › Disconnect: keep or
    // delete) starts the first run at the welcome screen.
    w.container
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: false);
    await tester.pumpAndSettle();
    await w.shot('f2-welcome');
    await w.tapText('Get started');
    await tester.enterText(find.byType(TextField).last, 'github_pat_example');
    await tester.pumpAndSettle();
    await w.shot('f3-connect');
    await w.tapText('Connect');
    await w.shot('f4-branch');
    await w.tapText('Continue');
    await w.shot('f5-file');
    await w.tapText('Continue');
    await w.shot('f6-create');
    await w.back();
    await w.tapText('Use a file I already have');
    await w.tapText('Continue');
    await w.shot('f7-existing');
    await w.tapText('Use this file');
    await w.shot('f8-done');
    await w.tapText('Open Libri');
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final (width, height, phone) in _sizes) {
    for (final scale in _scales) {
      final dir = '${width}x$height-s$scale';
      testWidgets('$dir ($phone)', (tester) async {
        final dpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = Size(width * dpr, height * dpr);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              ...fakeLookupOverrides(),
              libraryRepositoryProvider.overrideWithValue(
                FixtureLibraryRepository(),
              ),
              gitHubApiFactoryProvider.overrideWithValue(
                ({required token, required repository}) => FakeGitHubApi.demo(
                  File(FixtureLibraryRepository.assetPath).readAsStringSync(),
                ),
              ),
            ],
            child: RepaintBoundary(key: _root, child: const LibraryApp()),
          ),
        );
        await tester.pumpAndSettle();
        final walk = _Walk(tester, dir);
        await _walk(walk);
        expect(
          walk.failures,
          isEmpty,
          reason: 'Steps that failed:\n${walk.failures.join('\n')}',
        );
      });
    }
  }
}
