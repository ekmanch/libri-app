import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/data/sync/sync_status.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/sync/sync_state.dart';

import '../../helpers/fake_library_sync.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('shows the connection details', (tester) async {
    await pumpApp(tester, const ConnectionScreen());
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('ekmanch/library'), findsOneWidget);
    expect(find.text('Branch'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('library.json'), findsOneWidget);
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(
      find.text('When you open Libri, then every 5 minutes'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the GitHub values share a left edge after a 120 dp label column',
    (tester) async {
      await pumpApp(tester, const ConnectionScreen());
      final repository = tester.getTopLeft(find.text('ekmanch/library'));
      final branch = tester.getTopLeft(find.text('main'));
      final file = tester.getTopLeft(find.text('library.json'));
      final token = tester.getTopLeft(find.text('Saved on this phone'));
      expect(branch.dx, repository.dx);
      expect(file.dx, repository.dx);
      expect(token.dx, repository.dx);
      final label = tester.getTopLeft(find.text('Repository'));
      expect(repository.dx - label.dx, 120 + 12);
    },
  );

  test('the last synced line reads from the sync state', () {
    final now = DateTime(2026, 10, 13, 20, 30);
    expect(ConnectionScreen.lastSyncedLabel(null, now: now), 'Not synced yet');
    expect(
      ConnectionScreen.lastSyncedLabel(
        now.subtract(const Duration(minutes: 3)),
        now: now,
      ),
      'Last synced 3 minutes ago',
    );
  });

  testWidgets('Replace token opens the connect step on its own', (
    tester,
  ) async {
    final github = FakeGitHubApi.demo(encodeLibrary(loadFixture()));
    final container = await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [
        gitHubApiFactoryProvider.overrideWithValue(
          ({required token, required repository}) => github,
        ),
      ],
    );
    await tester.tap(find.text('Replace token'));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunFlow), findsOneWidget);
    expect(find.text('Connect GitHub'), findsOneWidget);
    expect(find.text('STEP 1 OF 4'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'github_pat_x');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();
    expect(github.requests, ['GET repo']);
    expect(container.read(tokenProvider), 'github_pat_x');
    expect(find.byType(FirstRunFlow), findsNothing);
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  Future<void> toSecondStep(WidgetTester tester) async {
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Disconnect'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Disconnect is two steps, and Cancel on either keeps all', (
    tester,
  ) async {
    final sync = FakeLibrarySync();
    final container = await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    // D15.
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect from GitHub?'), findsOneWidget);
    expect(
      find.text('Libri stops syncing with ekmanch/library.'),
      findsOneWidget,
    );
    expect(find.text('Nothing on GitHub changes.'), findsOneWidget);
    expect(find.textContaining('lost'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(libraryConnectionProvider).connected, isTrue);
    expect(find.byType(ConnectionScreen), findsOneWidget);

    // D16.
    await toSecondStep(tester);
    expect(find.text('Keep your library on this phone?'), findsOneWidget);
    expect(find.text('Keep it on this phone'), findsOneWidget);
    expect(find.text('Delete it from this phone'), findsOneWidget);
    expect(
      find.textContaining('Your library on GitHub is not affected.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(libraryConnectionProvider).connected, isTrue);
    expect(sync.discards + sync.keeps, 0);
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  testWidgets('"Keep it on this phone" disconnects and keeps the library', (
    tester,
  ) async {
    final sync = FakeLibrarySync();
    final container = await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    await toSecondStep(tester);
    await tester.tap(find.text('Keep it on this phone'));
    await tester.pumpAndSettle();
    final connection = container.read(libraryConnectionProvider);
    expect(connection.connected, isFalse);
    expect(connection.keptLocally, isTrue);
    expect(sync.keeps, 1);
    expect(sync.discards, 0);
    expect(container.read(tokenProvider), isNull);
    expect(container.read(startOverProvider), isFalse);
  });

  testWidgets('"Delete it from this phone" disconnects and starts over', (
    tester,
  ) async {
    final sync = FakeLibrarySync();
    final container = await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    await toSecondStep(tester);
    await tester.tap(find.text('Delete it from this phone'));
    await tester.pumpAndSettle();
    final connection = container.read(libraryConnectionProvider);
    expect(connection.connected, isFalse);
    expect(connection.keptLocally, isFalse);
    expect(sync.discards, 1);
    expect(sync.keeps, 0);
    expect(container.read(startOverProvider), isTrue);
  });

  testWidgets('kept on this phone, D6 says so and offers to connect', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [
        initialConnectionProvider.overrideWithValue(
          const LibraryConnection(connected: false, keptLocally: true),
        ),
      ],
    );
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Your library is kept on this phone'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
    expect(find.text('Replace token'), findsNothing);
    expect(find.text('ekmanch/library'), findsNothing);
    await tester.tap(find.text('Connect to GitHub'));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunFlow), findsOneWidget);
    expect(find.text('Connect GitHub'), findsOneWidget);
    expect(find.text('STEP 1 OF 4'), findsOneWidget);
    // Back from F3 returns to D6.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunFlow), findsNothing);
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  testWidgets('with unsaved changes the dialog says so', (tester) async {
    final sync = FakeLibrarySync(
      const SyncStatus(phase: SyncPhase.offline, pendingCount: 2),
    );
    await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('2 changes waiting to be saved'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '2 changes have not been saved to GitHub yet. They are lost unless '
        'you keep the library on this phone. Nothing on GitHub changes.',
      ),
      findsOneWidget,
    );
    expect(find.text('Disconnect anyway'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sync.discards + sync.keeps, 0);
  });

  testWidgets('an expired token shows in the status card, with Replace token', (
    tester,
  ) async {
    final sync = FakeLibrarySync(
      const SyncStatus(phase: SyncPhase.tokenProblem, pendingCount: 2),
    );
    await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [
        librarySyncProvider.overrideWithValue(sync),
        initialConnectionProvider.overrideWithValue(
          LibraryConnection(
            connected: true,
            tokenExpires: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ),
      ],
    );
    expect(find.text('Token expired'), findsOneWidget);
    expect(
      find.text("Libri can't sync until you add a new one"),
      findsOneWidget,
    );
    expect(find.text('Sync now'), findsNothing);
    // The card's button and the one at the bottom.
    expect(find.text('Replace token'), findsNWidgets(2));
    await tester.tap(find.text('Replace token').first);
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunFlow), findsOneWidget);
    expect(find.text('Save token'), findsOneWidget);
  });

  testWidgets('a conflict shows in the status card, and Choose opens D17', (
    tester,
  ) async {
    final sync = FakeLibrarySync(
      const SyncStatus(phase: SyncPhase.conflict, pendingCount: 2),
    );
    await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    expect(find.text('Changed here and on GitHub'), findsOneWidget);
    expect(find.text('Pick which copy to keep'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Keep which copy?'), findsOneWidget);
    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();
    expect(sync.resolutions, [true]);
  });

  testWidgets('a deleted file shows as not found, with what is gone', (
    tester,
  ) async {
    final sync = FakeLibrarySync(
      const SyncStatus(
        phase: SyncPhase.notFound,
        missing: MissingPart.file,
        pendingCount: 2,
      ),
    );
    await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    expect(find.text('Library not found on GitHub'), findsOneWidget);
    expect(
      find.text('library.json is gone from ekmanch/library on main.'),
      findsOneWidget,
    );
    expect(find.text('Sync now'), findsOneWidget);
  });

  testWidgets('Sync now and the status card follow the sync', (tester) async {
    final sync = FakeLibrarySync();
    await pumpApp(
      tester,
      const ConnectionScreen(),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();
    expect(sync.syncNows, 1);
    sync.emit(const SyncStatus(phase: SyncPhase.saving, pendingCount: 1));
    await tester.pumpAndSettle();
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.text('1 change waiting to be saved'), findsOneWidget);
    sync.emit(SyncStatus(lastSynced: DateTime.now()));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Last synced just now'), findsOneWidget);
  });
}
