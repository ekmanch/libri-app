import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/github/token_store.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/storage/connection_store.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/main.dart';

import 'helpers/package_info.dart';
import 'helpers/pump_app.dart';

/// The app as it runs on the phone: `bootstrap` with files in a folder,
/// the GitHub repository (on a fake API) and the real disconnect path.
void main() {
  late Directory dir;
  late FakeGitHubApi github;

  setUp(() {
    mockPackageInfo();
    dir = Directory.systemTemp.createTempSync('libri-app');
    github = FakeGitHubApi(
      files: {'library.json': encodeLibrary(loadFixture())},
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Pumps until [finder] matches, since the real I/O under runAsync
  /// completes between frames rather than inside pumpAndSettle.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(finder, findsOneWidget);
  }

  /// Starts the connected app and opens Settings › Library connection. Real
  /// file I/O only completes under [WidgetTester.runAsync], so the whole test
  /// runs there.
  Future<void> openConnection(WidgetTester tester) async {
    await FileConnectionStore(File('${dir.path}/connection.json'))
        .save(const LibraryConnection(connected: true).toJson());
    final app = await bootstrap(
      dir,
      tokenStore: MemoryTokenStore()..token = 'github_pat_x',
      api: ({required token, required repository}) => github,
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    await waitFor(tester, find.text('ACTIVE PLAN'));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Library source'), 300);
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Disconnect'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep your library on this phone?'), findsOneWidget);
  }

  testWidgets('deleting the library from the phone opens the first run', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openConnection(tester);
      await tester.tap(find.text('Delete it from this phone'));
      await tester.pumpAndSettle();
      await waitFor(tester, find.byType(FirstRunFlow));
      expect(find.text('Get started'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      // The files are gone once the disconnect has run through.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File('${dir.path}/library.json').existsSync(), isFalse);
      expect(File('${dir.path}/connection.json').existsSync(), isFalse);
      expect(File('${dir.path}/pending.json').existsSync(), isFalse);
      expect(File('${dir.path}/sync.json').existsSync(), isFalse);
    });
  });

  testWidgets('keeping the library on the phone keeps showing it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openConnection(tester);
      await tester.tap(find.text('Keep it on this phone'));
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('ACTIVE PLAN'));
      expect(find.byType(AppShell), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File('${dir.path}/library.json').existsSync(), isTrue);
      expect(File('${dir.path}/pending.json').existsSync(), isFalse);
      final stored = await FileConnectionStore(
        File('${dir.path}/connection.json'),
      ).load();
      expect(stored?['local'], isTrue);
    });
  });
}
