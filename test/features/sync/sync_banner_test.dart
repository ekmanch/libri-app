import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/sync/sync_status.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/sync/conflict_dialog.dart';
import 'package:library_app/features/sync/sync_banner.dart';
import 'package:library_app/features/sync/sync_state.dart';

import '../../helpers/fake_library_sync.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('nothing is shown without a banner', (tester) async {
    await pumpApp(tester, const Scaffold(body: SyncBannerCard()));
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('each banner has its text and button', (tester) async {
    final container = await pumpApp(
      tester,
      const Scaffold(body: SyncBannerCard()),
    );
    final notifier = container.read(syncBannerProvider.notifier);

    notifier.show(SyncBanner.saving);
    await tester.pumpAndSettle();
    expect(find.text('Saving your change'), findsOneWidget);
    expect(find.text('Sending it to GitHub.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    notifier.show(SyncBanner.offline);
    await tester.pumpAndSettle();
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    notifier.show(SyncBanner.couldNotSave);
    await tester.pumpAndSettle();
    expect(find.text('Could not save to GitHub'), findsOneWidget);
    expect(find.text('Your change is kept on this phone.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    notifier.show(SyncBanner.tokenProblem);
    await tester.pumpAndSettle();
    expect(find.text('GitHub refused the token'), findsOneWidget);
    expect(find.text('It may have expired.'), findsOneWidget);
    expect(find.text('Fix'), findsOneWidget);

    notifier.show(SyncBanner.tokenExpired);
    await tester.pumpAndSettle();
    expect(find.text('Token expired'), findsOneWidget);
    expect(
      find.text("Libri can't sync until you add a new one."),
      findsOneWidget,
    );
    expect(find.text('Replace token'), findsOneWidget);

    notifier.show(SyncBanner.conflict);
    await tester.pumpAndSettle();
    expect(find.text('Changed here and on GitHub'), findsOneWidget);
    expect(find.text('Pick which copy to keep.'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);

    // Forced by hand there is no sync state to say what is gone.
    notifier.show(SyncBanner.notFound);
    await tester.pumpAndSettle();
    expect(find.text('Library not found on GitHub'), findsOneWidget);
    expect(find.text('Nothing syncs until you reconnect.'), findsOneWidget);
    expect(find.text('Fix'), findsOneWidget);
  });

  testWidgets('not found says what is gone, and Fix opens the connection', (
    tester,
  ) async {
    final sync = FakeLibrarySync(
      const SyncStatus(
        phase: SyncPhase.notFound,
        missing: MissingPart.branch,
        pendingCount: 1,
      ),
    );
    await pumpApp(
      tester,
      const Scaffold(body: SyncBannerCard()),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    await tester.pumpAndSettle();
    expect(find.text('Library not found on GitHub'), findsOneWidget);
    expect(
      find.text(
        'The branch main is gone from ekmanch/library. Nothing syncs until '
        'you reconnect.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Fix'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(
      find.text('The branch main is gone from ekmanch/library.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a refused token past its date is "Token expired", with Replace token',
    (tester) async {
      final sync = FakeLibrarySync(
        const SyncStatus(phase: SyncPhase.tokenProblem),
      );
      await pumpApp(
        tester,
        const Scaffold(body: SyncBannerCard()),
        overrides: [
          librarySyncProvider.overrideWithValue(sync),
          initialConnectionProvider.overrideWithValue(
            LibraryConnection(
              connected: true,
              tokenExpires: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Token expired'), findsOneWidget);
      expect(find.text('GitHub refused the token'), findsNothing);
      await tester.tap(find.text('Replace token'));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunFlow), findsOneWidget);
      expect(find.text('Save token'), findsOneWidget);
    },
  );

  testWidgets('a refused token with time left is just refused', (tester) async {
    final sync = FakeLibrarySync(
      const SyncStatus(phase: SyncPhase.tokenProblem),
    );
    await pumpApp(
      tester,
      const Scaffold(body: SyncBannerCard()),
      overrides: [
        librarySyncProvider.overrideWithValue(sync),
        initialConnectionProvider.overrideWithValue(
          LibraryConnection(
            connected: true,
            tokenExpires: DateTime.now().add(const Duration(days: 20)),
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('GitHub refused the token'), findsOneWidget);
    expect(find.text('Fix'), findsOneWidget);
  });

  test('the detail names the part that is gone', () {
    const connection = LibraryConnection(connected: true);
    expect(
      missingDetail(MissingPart.repository, connection),
      'ekmanch/library is gone, or the token no longer sees it.',
    );
    expect(
      missingDetail(MissingPart.file, connection),
      'library.json is gone from ekmanch/library on main.',
    );
  });

  testWidgets(
    'Choose opens the conflict dialog, and a side resolves the conflict',
    (tester) async {
      final sync = FakeLibrarySync(
        SyncStatus(
          phase: SyncPhase.conflict,
          pendingCount: 3,
          remoteChangedAt: DateTime(2026, 10, 13, 20, 12),
        ),
      );
      final container = await pumpApp(
        tester,
        const Scaffold(body: SyncBannerCard()),
        overrides: [librarySyncProvider.overrideWithValue(sync)],
      );
      await tester.pumpAndSettle();
      expect(find.text('Changed here and on GitHub'), findsOneWidget);
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('Keep which copy?'), findsOneWidget);
      expect(find.text('This phone: 3 changes'), findsOneWidget);
      expect(find.text('GitHub: last commit Oct 13, 20:12'), findsOneWidget);
      expect(find.textContaining("Earlier versions stay"), findsOneWidget);

      // Decide later: nothing happens, the banner stays.
      await tester.tap(find.text('Decide later'));
      await tester.pumpAndSettle();
      expect(sync.resolutions, isEmpty);
      expect(find.text('Changed here and on GitHub'), findsOneWidget);

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Keep GitHub's"));
      await tester.pumpAndSettle();
      expect(sync.resolutions, [false]);

      container.read(syncBannerProvider.notifier).show(SyncBanner.conflict);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();
      expect(sync.resolutions, [false, true]);
    },
  );

  test('the dialog\'s lines for an unqueued edit and an unknown commit', () {
    const status = SyncStatus(phase: SyncPhase.conflict);
    expect(ConflictDialog.phoneLine(status), 'This phone: edited here');
    expect(
      ConflictDialog.phoneLine(status.copyWith(pendingCount: 1)),
      'This phone: 1 change',
    );
    expect(ConflictDialog.gitHubLine(status), 'GitHub: changed since');
  });

  testWidgets('Retry sends the queue again and Fix opens the connection', (
    tester,
  ) async {
    final sync = FakeLibrarySync();
    final container = await pumpApp(
      tester,
      const Scaffold(body: SyncBannerCard()),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    final notifier = container.read(syncBannerProvider.notifier);
    notifier.show(SyncBanner.couldNotSave);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(sync.syncNows, 1);
    // The banner follows the real state again, which is fine.
    expect(container.read(syncBannerProvider), isNull);
    expect(find.text('Could not save to GitHub'), findsNothing);

    notifier.show(SyncBanner.tokenProblem);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  test('the SYNC_BANNER dart-define names map to banners', () {
    expect(SyncBanner.fromDemo('saving'), SyncBanner.saving);
    expect(SyncBanner.fromDemo('offline'), SyncBanner.offline);
    expect(SyncBanner.fromDemo('failed'), SyncBanner.couldNotSave);
    expect(SyncBanner.fromDemo('token'), SyncBanner.tokenProblem);
    expect(SyncBanner.fromDemo('conflict'), SyncBanner.conflict);
    expect(SyncBanner.fromDemo('missing'), SyncBanner.notFound);
    expect(SyncBanner.fromDemo(''), isNull);
  });

  testWidgets('the banner follows the sync state', (tester) async {
    final sync = FakeLibrarySync();
    await pumpApp(
      tester,
      const Scaffold(body: SyncBannerCard()),
      overrides: [librarySyncProvider.overrideWithValue(sync)],
    );
    expect(find.byType(Container), findsNothing);
    sync.emit(const SyncStatus(phase: SyncPhase.saving, pendingCount: 1));
    await tester.pumpAndSettle();
    expect(find.text('Saving your change'), findsOneWidget);
    sync.emit(const SyncStatus(phase: SyncPhase.checking));
    await tester.pumpAndSettle();
    expect(find.byType(Container), findsNothing);
    sync.emit(const SyncStatus(phase: SyncPhase.tokenProblem, pendingCount: 1));
    await tester.pumpAndSettle();
    expect(find.text('GitHub refused the token'), findsOneWidget);
    sync.emit(const SyncStatus(phase: SyncPhase.offline, pendingCount: 1));
    await tester.pumpAndSettle();
    expect(find.text('You are offline'), findsOneWidget);
    sync.emit(const SyncStatus(phase: SyncPhase.failed, pendingCount: 1));
    await tester.pumpAndSettle();
    expect(find.text('Could not save to GitHub'), findsOneWidget);
    sync.emit(
      const SyncStatus(phase: SyncPhase.notFound, missing: MissingPart.file),
    );
    await tester.pumpAndSettle();
    expect(find.text('Library not found on GitHub'), findsOneWidget);
    expect(find.textContaining('library.json is gone'), findsOneWidget);
  });
}
