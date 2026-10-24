import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_providers.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/widgets/chips.dart';

import '../../helpers/pump_app.dart';

class _Opener extends StatelessWidget {
  const _Opener({this.type, this.title});
  final MediaType? type;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final saved = await openNewEntryScreen(
              context,
              type: type,
              title: title,
            );
            if (saved != null && context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Added ${saved.title}')));
            }
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  /// Rows titled [title]; the search field's own text does not count.
  Finder rowTitled(String title) =>
      find.byWidgetPredicate((w) => w is Text && w.data == title);

  /// Scrolls the chip row (lazy, so a far chip is not built yet) and taps.
  Future<void> pickChip(WidgetTester tester, String label) async {
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

  /// Types, waits out the debounce and settles.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('typing a title lists matches, filtered by the type chips', (
    tester,
  ) async {
    await pumpApp(tester, const _Opener());
    await open(tester);
    expect(find.text('New entry'), findsOneWidget);
    expect(find.text('IS IT ONE OF THESE?'), findsNothing);
    expect(find.text('Fill in the details myself'), findsOneWidget);

    await type(tester, 'Carrie');
    // One outline around the whole field, none on the text field itself.
    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(find.text('IS IT ONE OF THESE?'), findsOneWidget);
    expect(rowTitled('Carrie'), findsNWidgets(4));
    expect(find.text('MOVIE · 1976'), findsOneWidget);
    expect(find.text('Brian De Palma'), findsOneWidget);
    expect(find.text('Not listed?'), findsOneWidget);

    await type(tester, 'The Last of Us');
    expect(
      find.text(
        'Naughty Dog · PlayStation 3, PlayStation 4, PlayStation 5, PC',
      ),
      findsOneWidget,
    );

    await type(tester, 'Carrie');
    await pickChip(tester, 'Books');
    expect(rowTitled('Carrie'), findsOneWidget);
    expect(find.text('BOOK · 1974'), findsOneWidget);

    await pickChip(tester, 'Games');
    expect(find.text('No matches among games.'), findsOneWidget);
    expect(find.text('Not listed?'), findsNothing);
    expect(find.text('Fill in the details myself'), findsOneWidget);

    await pickChip(tester, 'All');
    await type(tester, 'Zelda');
    expect(find.text('No matches for "Zelda".'), findsOneWidget);
  });

  testWidgets(
    'the lookup waits for a pause in typing and drops stale answers',
    (tester) async {
      const latency = Duration(milliseconds: 300);
      final container = await pumpApp(
        tester,
        const _Opener(),
        lookupOverrides: fakeLookupOverrides(latency: latency),
      );
      final fake =
          container.read(lookupSourcesProvider).single as FakeLookupSource;
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Car');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'Carrie');
      await tester.pump(const Duration(milliseconds: 100));
      // Nothing asked yet: typing has not paused.
      expect(fake.calls, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Looking up "Carrie"…'), findsOneWidget);

      await tester.pump(NewEntryScreen.debounce);
      expect(fake.calls, hasLength(MediaType.values.length));
      expect(fake.calls.first, 'search:carrie:movies');
      // Still waiting for the answer.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // A new query before the answer lands: the old answer is thrown away.
      await tester.enterText(find.byType(TextField), 'Dune');
      await tester.pump(NewEntryScreen.debounce);
      await tester.pump(latency);
      await tester.pumpAndSettle();
      expect(rowTitled('Carrie'), findsNothing);
      expect(rowTitled('Dune'), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // Refining keeps the rows on screen while the next answer comes.
      await tester.enterText(find.byType(TextField), 'Dune:');
      await tester.pump(NewEntryScreen.debounce);
      expect(rowTitled('Dune'), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(latency);
      await tester.pumpAndSettle();
      expect(rowTitled('Dune: Awakening'), findsOneWidget);
      expect(rowTitled('Dune'), findsNothing);

      // Clearing the field clears everything.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('IS IT ONE OF THESE?'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('the rows show the fetched covers', (tester) async {
    await pumpApp(tester, const _Opener());
    await open(tester);
    await type(tester, 'Dune');
    // The fake fetcher writes the cover off the frame clock.
    for (var i = 0; i < 40 && find.byType(Image).evaluate().length < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(Image), findsNWidgets(4));
  });

  testWidgets('a title passed in is looked up at once', (tester) async {
    await pumpApp(tester, const _Opener(type: MediaType.anime, title: 'Akira'));
    await open(tester);
    expect(find.text('ANIME · 1988'), findsOneWidget);
    expect(rowTitled('Akira'), findsOneWidget);
  });

  testWidgets('a source answering in steps shows its first matches while '
      'the rest load', (tester) async {
    final books = _TwoSteps();
    await pumpApp(
      tester,
      const _Opener(type: MediaType.books),
      lookupOverrides: fakeLookupOverrides(source: books),
    );
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Dune');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pump();
    await tester.pump();
    expect(rowTitled('Dune (early)'), findsOneWidget);
    expect(rowTitled('Dune (full)'), findsNothing);
    expect(find.bySemanticsLabel('Looking up'), findsOneWidget);

    books.release.complete();
    await tester.pumpAndSettle();
    expect(rowTitled('Dune (full)'), findsOneWidget);
    expect(rowTitled('Dune (early)'), findsOneWidget);
    expect(find.bySemanticsLabel('Looking up'), findsNothing);
  });

  testWidgets('a match picked before the search is done waits for it and '
      'opens with what the rest brought, asking nothing again', (tester) async {
    final books = _TwoSteps();
    await pumpApp(
      tester,
      const _Opener(type: MediaType.books),
      lookupOverrides: fakeLookupOverrides(source: books),
    );
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Dune');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pump();
    await tester.pump();
    await tester.tap(rowTitled('Dune (early)'));
    await tester.pump();
    expect(books.calls.where((c) => c.startsWith('details:')), isEmpty);

    books.release.complete();
    await tester.pumpAndSettle();
    expect(books.calls.where((c) => c.startsWith('details:')), [
      'details:fake:early',
    ]);
    expect(find.text('1965'), findsWidgets);
  });

  group('states', () {
    Future<void> pumpWith(
      WidgetTester tester, {
      LookupFailure? failure,
      bool configured = true,
      MediaType? mediaType,
    }) async {
      await pumpApp(
        tester,
        _Opener(type: mediaType),
        lookupOverrides: fakeLookupOverrides(
          failure: failure,
          configured: configured,
        ),
      );
      await open(tester);
      await type(tester, 'Carrie');
    }

    testWidgets('offline says so and offers to try again', (tester) async {
      await pumpWith(tester, failure: LookupFailure.offline);
      expect(
        find.text(
          'Could not reach the lookup. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Fill in the details myself'), findsOneWidget);
      expect(find.text('Not listed?'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a provider that did not answer', (tester) async {
      await pumpWith(tester, failure: LookupFailure.rateLimited);
      expect(
        find.text('The lookup did not answer. Try again in a moment.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a source that answered only in part, with nothing, is not '
        '"no matches"', (tester) async {
      await pumpApp(
        tester,
        const _Opener(type: MediaType.books),
        lookupOverrides: fakeLookupOverrides(source: _HalfAnswering()),
      );
      await open(tester);
      await type(tester, 'The Weight of Angels John Boyne');
      expect(
        find.text(
          'Some lookups could not be reached, so a match may be missing. '
          'Try again in a moment.',
        ),
        findsOneWidget,
      );
      expect(find.text('No matches among books.'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a missing key is "not set up", for the type or at all', (
      tester,
    ) async {
      await pumpWith(tester, configured: false, mediaType: MediaType.games);
      expect(
        find.text(
          'Lookups for games are not set up on this build (no API key).',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      await pickChip(tester, 'All');
      expect(
        find.text('Lookups are not set up on this build (no API keys).'),
        findsOneWidget,
      );
      expect(find.text('Fill in the details myself'), findsOneWidget);
    });
  });

  testWidgets('a match is fetched in full, opens the form and saves', (
    tester,
  ) async {
    final container = await pumpApp(tester, const _Opener());
    final fake =
        container.read(lookupSourcesProvider).single as FakeLookupSource;
    await open(tester);
    await type(tester, 'akira');
    await tester.tap(find.text('ANIME · 1988'));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'details:anilist:47');
    expect(find.text('New entry'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Akira'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Katsuhiro Otomo'), findsOneWidget);
    expect(find.text('1988'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('New entry'), findsNothing);
    expect(find.text('Added Akira'), findsOneWidget);
    final repo =
        container.read(libraryRepositoryProvider) as FixtureLibraryRepository;
    final added = repo.current!.entries.last;
    expect(added.id, 'anime/akira-1988');
    expect(added.source, 'anilist:47');
  });

  testWidgets('a match whose details fail still opens the form', (
    tester,
  ) async {
    // The search answers; only the details call fails. The fake fails every
    // call, so the search is served first with a working fake, then the
    // details run against a failing one through the service's cache.
    final container = await pumpApp(
      tester,
      const _Opener(),
      lookupOverrides: fakeLookupOverrides(
        latency: const Duration(milliseconds: 50),
      ),
    );
    final fake =
        container.read(lookupSourcesProvider).single as FakeLookupSource;
    await open(tester);
    await type(tester, 'akira');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ANIME · 1988'));
    await tester.pump();
    // While the details are fetched the row shows a spinner and nothing
    // else can be tapped.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Fill in the details myself'),
          )
          .onPressed,
      isNull,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Akira'), findsOneWidget);
    expect(fake.calls.last, 'details:anilist:47');
  });

  testWidgets('"Fill in the details myself" keeps the title and type', (
    tester,
  ) async {
    await pumpApp(tester, const _Opener(type: MediaType.games, title: 'Zelda'));
    await open(tester);
    expect(find.text('No matches among games.'), findsOneWidget);
    await tester.tap(find.text('Fill in the details myself'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Zelda'), findsOneWidget);
    expect(find.text('Platforms'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Fill in the details myself'), findsOneWidget);
  });
}

/// Books from two providers, one of which did not answer and the other
/// found nothing.
class _HalfAnswering extends FakeLookupSource {
  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async => throw const PartialLookupException([], LookupFailure.other);
}

/// The fake lookup, whose book searches answer in two steps: an early hit,
/// then the full list once [release] is completed.
class _TwoSteps extends FakeLookupSource {
  final release = Completer<void>();

  @override
  Stream<List<LookupMatch>> searchSteps(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async* {
    LookupMatch hit(String title, String id, [int? year]) => LookupMatch(
      type: type,
      title: title,
      source: 'fake:$id',
      released: year == null ? null : Released(year),
    );
    yield [hit('$query (early)', 'early')];
    await release.future;
    // The rest brings the early hit's year, as Open Library does for an
    // Apple hit.
    yield [hit('$query (full)', 'full'), hit('$query (early)', 'early', 1965)];
  }
}
