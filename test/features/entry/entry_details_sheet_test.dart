import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/widgets/cover_placeholder.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/widgets/segmented_control.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/slow_save_repository.dart';

const _mummy = 'movies/the-mummy-1999';

class _Opener extends StatelessWidget {
  const _Opener(this.entryId);
  final String entryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showEntryDetailsSheet(context, entryId),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  Future<ProviderContainer> open(
    WidgetTester tester, {
    String entryId = _mummy,
    List<Override>? lookupOverrides,
  }) async {
    final container = await pumpApp(
      tester,
      _Opener(entryId),
      lookupOverrides: lookupOverrides,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Finder inSegments(String label) => find.descendant(
    of: find.byType(StatusSegmentedControl),
    matching: find.text(label),
  );

  testWidgets('shows kind, title, creator, rating, note, about, tags, plans', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('MOVIE · 1999'), findsOneWidget);
    expect(find.text('The Mummy'), findsOneWidget);
    expect(find.text('Stephen Sommers'), findsOneWidget);
    expect(find.text('9 / 10'), findsOneWidget);
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.text('Perfect October comfort film.'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('#adventure'), findsOneWidget);
    expect(find.text('In plans'), findsOneWidget);
    expect(find.text('Halloween 2026'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(CoverPlaceholder), findsNothing);
  });

  testWidgets('empty note and about are left out; no plans says so', (
    tester,
  ) async {
    await open(tester, entryId: 'movies/dune-part-two-2024');
    expect(find.text('NOTE'), findsNothing);
    expect(find.text('ABOUT'), findsNothing);
    expect(find.text('Not in any plan'), findsOneWidget);
  });

  testWidgets('a book shows its page count under the author (A38)', (
    tester,
  ) async {
    await open(tester, entryId: 'books/dracula-1897');
    expect(find.text('Bram Stoker'), findsOneWidget);
    expect(find.text('418 pages'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('418 pages')).dy,
      greaterThan(tester.getBottomLeft(find.text('Bram Stoker')).dy),
    );
  });

  testWidgets('a book without a page count leaves the line out', (
    tester,
  ) async {
    await open(tester, entryId: 'books/a-christmas-carol-1843');
    expect(find.text('Charles Dickens'), findsOneWidget);
    expect(find.textContaining('pages'), findsNothing);
  });

  testWidgets('a photo view shows the cover spot', (tester) async {
    final container = await pumpApp(tester, const _Opener(_mummy));
    container
        .read(displayPreferencesProvider.notifier)
        .setView(MediaType.movies, EntryView.grid);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(CoverPlaceholder), findsOneWidget);
  });

  testWidgets('a song offers only Want and Done', (tester) async {
    await open(tester, entryId: 'music/human-fly-the-cramps');
    expect(find.text('SONG · 1981'), findsOneWidget);
    expect(find.text('The Cramps · Bad Music for Bad People'), findsOneWidget);
    expect(inSegments('Want'), findsOneWidget);
    expect(inSegments('Done'), findsOneWidget);
    expect(inSegments('In progress'), findsNothing);
    expect(inSegments('DNF'), findsNothing);
  });

  group('album tracks (A22)', () {
    const dirt = 'music/dirt-alice-in-chains';

    testWidgets('a cached track list is numbered, rated and collapsible', (
      tester,
    ) async {
      final container = await open(tester, entryId: dirt);
      expect(find.text('ALBUM · 1992'), findsOneWidget);
      expect(find.text('Album rating'), findsOneWidget);
      expect(find.text('TRACKS'), findsOneWidget);
      expect(find.text('3 of 13 rated'), findsOneWidget);
      expect(find.text('Them Bones'), findsOneWidget);
      expect(
        find.text('9 / 10'),
        findsNWidgets(2),
      ); // Them Bones, Down in a Hole.
      expect(find.text('Rate'), findsNWidgets(3));
      expect(find.text('Would?'), findsNothing);
      await tester.ensureVisible(find.text('Show all 13 tracks'));
      await tester.tap(find.text('Show all 13 tracks'));
      await tester.pumpAndSettle();
      expect(find.text('Would?'), findsOneWidget);
      expect(find.text('Show all 13 tracks'), findsNothing);

      await tester.ensureVisible(find.text('Dam That River'));
      await tester.tap(find.text('Dam That River'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('5 out of 10'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      final tracks = repo(container).current!.entryById(dirt)!.tracks!;
      expect(tracks.length, 4);
      expect(tracks.last.title, 'Dam That River');
      expect(tracks.last.id, 'deezer:track:1016551');
      expect(tracks.last.rating, 5);
      expect(find.text('4 of 13 rated'), findsOneWidget);

      await tester.ensureVisible(find.text('Rooster'));
      await tester.tap(find.text('Rooster'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear rating'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(
        repo(container).current!.entryById(dirt)!.tracks!.map((t) => t.title),
        ['Them Bones', 'Down in a Hole', 'Dam That River'],
      );
    });

    testWidgets('an album the source has no list for shows the rated ones', (
      tester,
    ) async {
      await open(tester, entryId: 'music/master-of-puppets-metallica');
      expect(find.text('1 rated'), findsOneWidget);
      expect(find.text('Master of Puppets'), findsNWidgets(2)); // Title, track.
      expect(
        find.text('No track list was found for this album.'),
        findsOneWidget,
      );
      expect(find.text('Rate'), findsNothing);
    });

    testWidgets('offline without a cached list says it needs a connection', (
      tester,
    ) async {
      await open(
        tester,
        entryId: 'music/master-of-puppets-metallica',
        lookupOverrides: fakeLookupOverrides(failure: LookupFailure.offline),
      );
      expect(
        find.text('The full track list needs a connection.'),
        findsOneWidget,
      );
      expect(find.text('1 rated'), findsOneWidget);
    });

    testWidgets('a rating stored under another id still shows, by title', (
      tester,
    ) async {
      // The fixture's Dirt ratings carry "mb:" ids; the fake list has
      // Deezer ids.
      await open(tester, entryId: dirt);
      expect(find.text('3 of 13 rated'), findsOneWidget);
      expect(
        find.text('9 / 10'),
        findsNWidgets(2),
      ); // Them Bones, Down in a Hole.
      expect(find.text('10 / 10'), findsNWidgets(2)); // Album, Rooster.
    });

    testWidgets('a song has no track list', (tester) async {
      await open(tester, entryId: 'music/human-fly-the-cramps');
      expect(find.text('TRACKS'), findsNothing);
      expect(find.text('Rating'), findsOneWidget);
    });
  });

  testWidgets('changing the status applies at once', (tester) async {
    final container = await open(tester);
    await tester.tap(inSegments('Want'));
    await tester.pumpAndSettle();
    expect(
      repo(container).current!.entryById(_mummy)!.status,
      EntryStatus.want,
    );
  });

  testWidgets('the rating picker sets and clears the rating', (tester) async {
    final container = await open(tester);
    await tester.tap(find.text('9 / 10'));
    await tester.pumpAndSettle();
    expect(find.text('Rating'), findsWidgets);
    expect(find.text('1 is the lowest'), findsOneWidget);
    expect(find.bySemanticsLabel('9 out of 10'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('5 out of 10'));
    await tester.pump();
    expect(find.text('5 / 10'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(repo(container).current!.entryById(_mummy)!.rating, 5);
    expect(find.text('5 / 10'), findsOneWidget);

    await tester.tap(find.text('5 / 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear rating'));
    await tester.pump();
    expect(find.text('Not rated'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(repo(container).current!.entryById(_mummy)!.rating, isNull);
    expect(find.text('Not rated'), findsOneWidget);
  });

  testWidgets('dismissing the rating picker changes nothing', (tester) async {
    final container = await open(tester);
    await tester.tap(find.text('9 / 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('2 out of 10'));
    await tester.tapAt(const Offset(195, 40)); // The scrim above the sheet.
    await tester.pumpAndSettle();
    expect(repo(container).current!.entryById(_mummy)!.rating, 9);
  });

  testWidgets('add to plan toggles plan items and marks repeats', (
    tester,
  ) async {
    final container = await open(tester);
    await tester.ensureVisible(find.text('Add to plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to plan'));
    await tester.pumpAndSettle();
    expect(find.text('Add to plan'), findsWidgets);
    await tester.ensureVisible(find.text('Christmas 2026'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Christmas 2026'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Christmas 2026'));
    await tester.pumpAndSettle();
    final christmas = repo(container).current!.planById('christmas-2026')!;
    final item = christmas.itemFor(_mummy)!;
    expect(item.repeat, isTrue); // The Mummy is already done.
    expect(item.done, isFalse);

    await tester.tap(find.bySemanticsLabel('Halloween 2026'));
    await tester.pumpAndSettle();
    expect(
      repo(container).current!.planById('halloween-2026')!.itemFor(_mummy),
      isNull,
    );
    expect(find.text('New plan'), findsOneWidget); // The A7 link.
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Christmas 2026'), findsOneWidget); // Now in the sheet.
  });

  testWidgets('delete asks first, names the plans, then closes the sheet', (
    tester,
  ) async {
    final container = await open(tester);
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete The Mummy?'), findsOneWidget);
    expect(
      find.text(
        'It will be removed from your library and from the plan '
        'Halloween 2026.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo(container).current!.entryById(_mummy), isNotNull);
    expect(find.text('The Mummy'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
    );
    await tester.pumpAndSettle();
    expect(repo(container).current!.entryById(_mummy), isNull);
    expect(find.text('The Mummy'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('delete with a slow save closes only the sheet', (tester) async {
    // The GitHub repository publishes the change before its apply returns.
    // The sheet closed itself on seeing the entry gone and then the delete
    // handler popped again, taking the screen underneath with it.
    final slow = SlowSaveRepository(
      FixtureLibraryRepository(
        loadJson: () async => encodeLibrary(loadFixture()),
      ),
    );
    await pumpApp(tester, const _Opener(_mummy), repository: slow);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
    );
    // The dialog closes and the change is published; the sheet sees the
    // entry gone in the next frame; the save completes while the sheet is
    // still closing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(slow.delay);
    await tester.pumpAndSettle();
    expect(find.text('The Mummy'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(slow.inner.current!.entryById(_mummy), isNull);
  });

  testWidgets('edit opens the form and the sheet shows the saved change', (
    tester,
  ) async {
    final container = await open(tester);
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);
    final title = find.widgetWithText(TextField, 'The Mummy');
    expect(title, findsOneWidget);
    await tester.enterText(title, 'The Mummy (1999)');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final entry = repo(container).current!.entryById(_mummy)!;
    expect(entry.title, 'The Mummy (1999)');
    expect(entry.rating, 9);
    expect(entry.tags, ['adventure', 'lighthearted', 'halloween', 'favorite']);
    expect(find.text('The Mummy (1999)'), findsOneWidget);
    expect(find.text('Edit entry'), findsNothing);
  });
}
