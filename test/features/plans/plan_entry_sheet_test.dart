import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/plans/plan_entry_sheet.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/slow_save_repository.dart';

class _Opener extends StatelessWidget {
  const _Opener(this.planId, this.entryId);
  final String planId;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () =>
              showPlanEntrySheet(context, planId: planId, entryId: entryId),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Future<ProviderContainer> open(
    WidgetTester tester,
    String plan,
    String entry,
  ) async {
    final container = await pumpApp(tester, _Opener(plan, entry));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'entry in a plan: done button, rating, when, plan note, about, tags',
    (tester) async {
      final container = await open(
        tester,
        'halloween-2026',
        'movies/the-mummy-1999',
      );
      expect(find.text('The Mummy'), findsOneWidget);
      expect(find.text('Mark as done'), findsOneWidget);
      expect(find.text('9 / 10'), findsOneWidget);
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Oct 19–31'), findsOneWidget);
      expect(find.text('PLAN NOTE'), findsOneWidget);
      expect(find.text('Add a note'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('#halloween'), findsOneWidget);

      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      expect(find.text('Done. Tap to undo'), findsOneWidget);
      final plan = repo(container).current!.planById('halloween-2026')!;
      expect(plan.itemFor('movies/the-mummy-1999')!.done, isTrue);

      await tester.tap(find.text('Add a note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'With the kids');
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('With the kids'), findsOneWidget);
      expect(
        repo(container).current!
            .planById('halloween-2026')!
            .itemFor('movies/the-mummy-1999')!
            .note,
        'With the kids',
      );
    },
  );

  testWidgets('marking done also finishes a wanted entry', (tester) async {
    final container = await open(
      tester,
      'halloween-2026',
      'movies/hereditary-2018',
    );
    await tester.tap(find.text('Mark as done'));
    await tester.pumpAndSettle();
    expect(
      repo(container).current!.entryById('movies/hereditary-2018')!.status,
      EntryStatus.done,
    );
  });

  testWidgets('remove from this plan or delete everywhere', (tester) async {
    final container = await open(
      tester,
      'halloween-2026',
      'movies/the-mummy-1999',
    );
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove The Mummy?'), findsOneWidget);
    expect(
      find.text('It is in the plan Halloween 2026 and in your library.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove from this plan'));
    await tester.pumpAndSettle();
    var library = repo(container).current!;
    expect(
      library.planById('halloween-2026')!.itemFor('movies/the-mummy-1999'),
      isNull,
    );
    expect(library.entryById('movies/the-mummy-1999'), isNotNull);
    expect(find.byType(PlanEntrySheet), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Gone from the plan: the sheet closes itself.
    expect(find.byType(PlanEntrySheet), findsNothing);
  });

  testWidgets('remove from plan: a slow save closes only the sheet', (
    tester,
  ) async {
    final slow = SlowSaveRepository(
      FixtureLibraryRepository(
        loadJson: () async => encodeLibrary(loadFixture()),
      ),
    );
    await pumpApp(
      tester,
      const _Opener('christmas-2026', 'movies/klaus-2019'),
      repository: slow,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everywhere'));
    // The dialog closes and the change is published; the sheet sees the
    // entry gone in the next frame; the save completes while the sheet is
    // still closing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(slow.delay);
    await tester.pumpAndSettle();
    expect(find.text('Klaus'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(slow.inner.current!.entryById('movies/klaus-2019'), isNull);
  });

  testWidgets('remove from plan: delete everywhere removes the entry', (
    tester,
  ) async {
    final container = await open(tester, 'christmas-2026', 'movies/klaus-2019');
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete everywhere'));
    await tester.pumpAndSettle();
    expect(repo(container).current!.entryById('movies/klaus-2019'), isNull);
  });
}
