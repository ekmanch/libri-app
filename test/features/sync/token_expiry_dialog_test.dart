import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/storage/connection_store.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/features/sync/token_expiry_dialog.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets(
    'the expiry warning says when the token stops working, with three ways out',
    (tester) async {
      TokenExpiryChoice? choice;
      var opened = false;
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = true;
                choice = await showTokenExpiryDialog(
                  context,
                  repository: 'ekmanch/library',
                  expires: DateTime(2026, 10, 24, 16, 20),
                  now: DateTime(2026, 10, 18, 10),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(find.text('Your GitHub token expires in 6 days'), findsOneWidget);
      expect(
        find.text(
          'The access token for ekmanch/library stops working on October 24. '
          "After that, Libri can't sync until you add a new one.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('regenerate the token'), findsOneWidget);
      expect(find.text('Replace token'), findsOneWidget);
      expect(find.text('Open GitHub'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Open token settings on GitHub, opens website'),
        findsOneWidget,
      );
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(choice, TokenExpiryChoice.later);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace token'));
      await tester.pumpAndSettle();
      expect(choice, TokenExpiryChoice.replace);
    },
  );

  group('the shell shows the expiry warning on open', () {
    late MemoryConnectionStore store;

    Future<void> pumpShell(WidgetTester tester, LibraryConnection connection) {
      store = MemoryConnectionStore(connection.toJson());
      // Wider than a phone: the test font is wide and the nav row is not
      // meant to shrink.
      return pumpApp(
        tester,
        const AppShell(),
        size: const Size(480, 844),
        overrides: [
          initialConnectionProvider.overrideWithValue(connection),
          connectionStoreProvider.overrideWithValue(store),
        ],
      );
    }

    testWidgets('in the last week; Later records the day', (tester) async {
      final now = DateTime.now();
      await pumpShell(
        tester,
        LibraryConnection(
          connected: true,
          tokenExpires: now.add(const Duration(days: 3)),
        ),
      );
      expect(find.textContaining('Your GitHub token expires'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      expect(store.saved?['tokenWarnedOn'], today);
    });

    testWidgets('not again the same day', (tester) async {
      final now = DateTime.now();
      await pumpShell(
        tester,
        LibraryConnection(
          connected: true,
          tokenExpires: now.add(const Duration(days: 3)),
          tokenWarnedOn: DateTime(now.year, now.month, now.day),
        ),
      );
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('not with more than a week left', (tester) async {
      await pumpShell(
        tester,
        LibraryConnection(
          connected: true,
          tokenExpires: DateTime.now().add(const Duration(days: 9)),
        ),
      );
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('not past the date (the banner says it then)', (tester) async {
      await pumpShell(
        tester,
        LibraryConnection(
          connected: true,
          tokenExpires: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Replace token opens the token step with the repo kept', (
      tester,
    ) async {
      await pumpShell(
        tester,
        LibraryConnection(
          connected: true,
          repository: 'me/books',
          tokenExpires: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await tester.tap(find.text('Replace token'));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunFlow), findsOneWidget);
      expect(find.text('Save token'), findsOneWidget);
      expect(find.text('me/books'), findsOneWidget);
    });
  });
}
