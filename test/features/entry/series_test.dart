import 'package:flutter/material.dart';

import 'dart:ui' show CheckedState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/data/lookup/text_clean.dart';
import 'package:library_app/features/entry/series.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/widgets/app_buttons.dart';
import 'package:library_app/widgets/chips.dart';

import '../../helpers/pump_app.dart';

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

/// Pushes the series page for the entry, as a series row of the library
/// list does.
class _PageOpener extends StatelessWidget {
  const _PageOpener(this.entryId);
  final String entryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => openSeriesPage(context, entryId),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

const _fellowship =
    'movies/the-lord-of-the-rings-the-fellowship-of-the-ring-2001';
const _towers = 'movies/the-lord-of-the-rings-the-two-towers-2002';
const _berserk43 = 'books/berserk-vol-43-2025';

Entry _entry(
  String id,
  String title, {
  MediaType type = MediaType.movies,
  int? number,
  String? source,
  EntryStatus status = EntryStatus.want,
  int? year,
}) => Entry(
  id: id,
  type: type,
  title: title,
  status: status,
  released: year == null ? null : Released(year),
  added: DateTime(2026),
  source: source,
  series: Series(name: 'The Lord of the Rings', number: number),
);

void main() {
  Future<ProviderContainer> open(
    WidgetTester tester,
    String entryId, {
    FakeLookupSource? source,
  }) async {
    final container = await pumpApp(
      tester,
      _Opener(entryId),
      lookupOverrides: fakeLookupOverrides(source: source),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> toSeries(WidgetTester tester) async {
    await tester.ensureVisible(find.text('SERIES'));
    await tester.pumpAndSettle();
  }

  group('seriesRows', () {
    const SeriesParts parts = (
      name: 'The Lord of the Rings',
      parts: [
        (
          number: 1,
          title: 'The Fellowship of the Ring',
          year: 2001,
          released: null,
          source: 'tmdb:movie:120',
          creator: null,
          cover: null,
          extra: false,
        ),
        (
          number: 2,
          title: 'The Two Towers',
          year: 2002,
          released: null,
          source: 'tmdb:movie:121',
          creator: null,
          cover: null,
          extra: false,
        ),
        (
          number: 3,
          title: 'The Return of the King',
          year: 2003,
          released: null,
          source: 'tmdb:movie:122',
          creator: null,
          cover: null,
          extra: false,
        ),
      ],
    );

    test('matches the library\'s entries by id, number, then title', () {
      final byId = _entry(
        'a',
        'Fellowship',
        number: 9,
        source: 'tmdb:movie:120',
      );
      final byNumber = _entry('b', 'Towers again', number: 2);
      final byTitle = _entry('c', 'the return of the king');
      final rows = seriesRows(
        current: byId,
        library: [byId, byNumber, byTitle],
        parts: parts,
      );
      expect(
        {for (final r in rows) r.number: r.entry?.id},
        {9: 'a', 2: 'b', 3: 'c'},
      );
    });

    test('an id match wins over a weaker match of an earlier part', () {
      // IGDB's Tomb Raider: part 1 shares its title with the 2013 reboot
      // (part 4 here), and Rise was stored as number 2 of another
      // collection; ids put both where they are.
      const SeriesParts tombRaider = (
        name: 'The Lord of the Rings',
        parts: [
          (
            number: 1,
            title: 'Tomb Raider',
            year: 1996,
            released: null,
            source: 'igdb:912',
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 2,
            title: 'Tomb Raider II',
            year: 1997,
            released: null,
            source: 'igdb:1',
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 3,
            title: 'Legend',
            year: 2006,
            released: null,
            source: 'igdb:2',
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 4,
            title: 'Tomb Raider',
            year: 2013,
            released: null,
            source: 'igdb:1164',
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 5,
            title: 'Rise of the Tomb Raider',
            year: 2015,
            released: null,
            source: 'igdb:7323',
            creator: null,
            cover: null,
            extra: false,
          ),
        ],
      );
      final reboot = _entry(
        'r',
        'Tomb Raider',
        number: 4,
        year: 2013,
        source: 'igdb:1164',
      );
      final rise = _entry(
        'x',
        'Rise of the Tomb Raider',
        number: 2,
        year: 2015,
        source: 'igdb:7323',
      );
      final rows = seriesRows(
        current: reboot,
        library: [reboot, rise],
        parts: tombRaider,
      );
      expect(rows.length, 5);
      expect(rows.where((r) => r.owned).map((r) => r.entry!.id), {'x', 'r'});
      expect(
        rows.where((r) => r.title == 'Tomb Raider II').single.owned,
        false,
      );
      expect(
        rows.where((r) => r.year == 1996).single.owned,
        isFalse,
        reason: 'the 1996 part is not the 2013 entry',
      );
    });

    test('a title match prefers the part of the same year', () {
      const SeriesParts twice = (
        name: 'The Lord of the Rings',
        parts: [
          (
            number: 1,
            title: 'Tomb Raider',
            year: 1996,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 2,
            title: 'Tomb Raider',
            year: 2013,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
        ],
      );
      final reboot = _entry('r', 'Tomb Raider', year: 2013);
      final rows = seriesRows(current: reboot, library: [reboot], parts: twice);
      expect(rows.map((r) => (r.number, r.year, r.owned)), [
        (1, 1996, false),
        (2, 2013, true),
      ]);
    });

    test('a part shows the title and year of the entry that is it', () {
      // Open Library's work for volume 16 is an omnibus, "Berserk #16-20".
      const SeriesParts berserk = (
        name: 'Berserk',
        parts: [
          (
            number: 16,
            title: 'Berserk #16-20',
            year: 2007,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 17,
            title: 'Berserk Volume 17',
            year: 2007,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
        ],
      );
      final sixteen = _entry('s', 'Berserk Volume 16', number: 16, year: 2008);
      final rows = seriesRows(
        current: sixteen,
        library: [sixteen],
        parts: berserk,
      );
      expect(rows.map((r) => (r.number, r.title, r.year, r.owned)), [
        (16, 'Berserk Volume 16', 2008, true),
        (17, 'Berserk Volume 17', 2007, false),
      ]);
    });

    test('a part takes the number of the entry that is it', () {
      // The Asian Saga: Wikidata numbers only Whirlwind, the owner put
      // Shōgun first; the lookup lists the rest by date.
      const SeriesParts saga = (
        name: 'The Lord of the Rings',
        parts: [
          (
            number: 6,
            title: 'Whirlwind',
            year: 1986,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: null,
            title: 'King Rat',
            year: 1962,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: null,
            title: 'Tai-Pan',
            year: 1966,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: null,
            title: 'Shōgun',
            year: 1975,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 2,
            title: 'Noble House',
            year: 1981,
            released: null,
            source: null,
            creator: null,
            cover: null,
            extra: false,
          ),
        ],
      );
      final shogun = _entry('s', 'Shōgun', number: 1);
      final noble = _entry('n', 'Noble House', number: 5);
      final rows = seriesRows(
        current: shogun,
        library: [shogun, noble],
        parts: saga,
      );
      expect(rows.map((r) => (r.number, r.title)), [
        (1, 'Shōgun'),
        (5, 'Noble House'),
        (6, 'Whirlwind'),
        (null, 'King Rat'),
        (null, 'Tai-Pan'),
      ]);
      expect(rows[0].entry?.id, 's');
      expect(rows[1].entry?.id, 'n');
    });

    test('entries the lookup does not list are placed by number', () {
      final extra = _entry('x', 'The Hobbit', number: 0, year: 2012);
      final later = _entry('y', 'Something later');
      final current = _entry('c', 'The Two Towers', number: 2);
      final rows = seriesRows(
        current: current,
        library: [current, extra, later],
        parts: parts,
      );
      expect(rows.map((r) => r.title), [
        'The Hobbit',
        'The Fellowship of the Ring',
        'The Two Towers',
        'The Return of the King',
        'Something later',
      ]);
      expect(rows[0].owned, isTrue);
      expect(rows[1].owned, isFalse);
      expect(rows[2].entry?.id, 'c');
    });

    test('without fetched parts the rows are the library\'s entries', () {
      final two = _entry('b', 'Two', number: 2);
      final one = _entry('a', 'One', number: 1);
      final other = _entry(
        'z',
        'Other series',
      ).copyWith(series: const Series(name: 'Dune'));
      final otherType = _entry('t', 'Three', type: MediaType.books, number: 3);
      final rows = seriesRows(
        current: two,
        library: [two, one, other, otherType],
      );
      expect(rows.map((r) => r.entry!.id), ['a', 'b']);
      expect(seriesRows(current: other, library: [other]).length, 1);
    });

    test('the window: all of up to five, else three around this one', () {
      final rows = [
        for (var n = 1; n <= 8; n++) SeriesRow(number: n, title: '$n'),
      ];
      expect(seriesWindow(rows.sublist(0, 5), 4), hasLength(5));
      expect(seriesWindow(rows, 0).map((r) => r.number), [1, 2, 3]);
      expect(seriesWindow(rows, 3).map((r) => r.number), [3, 4, 5]);
      expect(seriesWindow(rows, 7).map((r) => r.number), [6, 7, 8]);
    });

    test('a part\'s title drops the series name in front', () {
      expect(
        seriesPartTitle(
          'The Lord of the Rings: The Fellowship of the Ring',
          'The Lord of the Rings',
        ),
        'The Fellowship of the Ring',
      );
      expect(seriesPartTitle('Berserk, Vol. 43', 'Berserk'), 'Vol. 43');
      expect(seriesPartTitle('Dune Messiah', 'Dune'), 'Dune Messiah');
      expect(
        seriesPartTitle('Harry Potter and the Goblet of Fire', 'Harry Potter'),
        'Harry Potter and the Goblet of Fire',
      );
    });

    test('nouns by type', () {
      expect(seriesNouns(MediaType.books), ('volume', 'volumes'));
      expect(seriesNouns(MediaType.movies), ('movie', 'movies'));
      expect(seriesNouns(MediaType.anime), ('movie', 'movies'));
      expect(seriesNouns(MediaType.games), ('game', 'games'));
    });
  });

  testWidgets('a movie in a series lists every part, this one marked', (
    tester,
  ) async {
    await open(tester, _fellowship);
    await toSeries(tester);
    expect(find.text('SERIES'), findsOneWidget);
    expect(find.text('2 of 4 in your library'), findsOneWidget);
    expect(find.text('The Lord of the Rings'), findsOneWidget);
    expect(find.text('The Fellowship of the Ring'), findsOneWidget);
    expect(find.text('This one'), findsOneWidget);
    expect(find.text('The Two Towers'), findsOneWidget);
    expect(find.bySemanticsLabel('Open The Two Towers, want'), findsOneWidget);
    expect(find.text('The Return of the King'), findsOneWidget);
    expect(find.text('2003 · Not in your library'), findsOneWidget);
    expect(find.bySemanticsLabel('Add The Return of the King'), findsOneWidget);
    expect(find.textContaining('All 3'), findsNothing);
  });

  testWidgets('another part opens in the same sheet, from the top', (
    tester,
  ) async {
    await open(tester, _fellowship);
    await toSeries(tester);
    await tester.tap(find.bySemanticsLabel('Open The Two Towers, want'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailsSheet), findsOneWidget);
    expect(find.text('MOVIE · 2002'), findsOneWidget);
    expect(find.text('The Lord of the Rings: The Two Towers'), findsOneWidget);
    await toSeries(tester);
    expect(find.bySemanticsLabel('The Two Towers, this one'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Open The Fellowship of the Ring, done'),
      findsOneWidget,
    );
  });

  testWidgets('"+ Add" starts a new entry looked up for the part', (
    tester,
  ) async {
    await open(tester, _fellowship);
    await toSeries(tester);
    await tester.tap(find.bySemanticsLabel('Add The Return of the King'));
    await tester.pumpAndSettle();
    expect(find.byType(NewEntryScreen), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller!.text,
      'The Lord of the Rings: The Return of the King',
    );
    expect(
      tester.widget<PillChip>(find.widgetWithText(PillChip, 'Movies')).selected,
      isTrue,
    );
  });

  testWidgets('a long series shows three around this one and all of them', (
    tester,
  ) async {
    await open(tester, _berserk43);
    await toSeries(tester);
    expect(find.text('3 of 43 in your library'), findsOneWidget);
    expect(find.text('Vol. 41'), findsOneWidget);
    expect(find.text('Vol. 42'), findsOneWidget);
    expect(find.text('Vol. 43'), findsOneWidget);
    expect(find.text('Vol. 1'), findsNothing);
    expect(find.text('All 43 volumes'), findsOneWidget);
    await tester.tap(find.text('All 43 volumes'));
    await tester.pumpAndSettle();
    expect(find.byType(AllSeriesScreen), findsOneWidget);
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('43 volumes · 3 in your library'), findsOneWidget);
    // Opened scrolled to this one: it is on screen, the first volume above.
    expect(find.text('This one'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Vol. 43')).dy, lessThan(780));
    expect(tester.getTopLeft(find.text('Vol. 1')).dy, lessThan(0));
    // A part tapped there opens in the sheet.
    await tester.tap(find.bySemanticsLabel('Open Vol. 42, in progress'));
    await tester.pumpAndSettle();
    expect(find.byType(AllSeriesScreen), findsNothing);
    expect(find.text('Berserk, Vol. 42'), findsOneWidget);
    expect(find.bySemanticsLabel('Vol. 42, this one'), findsOneWidget);
  });

  testWidgets('without a fetched list the section shows the library\'s parts', (
    tester,
  ) async {
    await open(
      tester,
      _towers,
      source: FakeLookupSource(
        seriesBySource: {'fake:the-lord-of-the-rings-the-two-towers': null},
      ),
    );
    await toSeries(tester);
    expect(find.text('2 of 2 in your library'), findsOneWidget);
    expect(find.text('The Fellowship of the Ring'), findsOneWidget);
    expect(find.text('The Return of the King'), findsNothing);
  });

  testWidgets('an entry in no series has no section', (tester) async {
    await open(tester, 'movies/the-mummy-1999');
    expect(find.text('SERIES'), findsNothing);
  });

  group('the series page from a series row', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Series options'));
      await tester.pumpAndSettle();
    }

    Future<ProviderContainer> openPage(WidgetTester tester) async {
      final container = await pumpApp(
        tester,
        const _PageOpener(_fellowship),
        lookupOverrides: fakeLookupOverrides(),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('lists every part with no "this one", and a ⋮ menu', (
      tester,
    ) async {
      await openPage(tester);
      expect(find.byType(AllSeriesScreen), findsOneWidget);
      expect(find.text('The Lord of the Rings'), findsOneWidget);
      expect(find.text('4 movies · 2 in your library'), findsOneWidget);
      expect(find.text('This one'), findsNothing);
      expect(
        find.bySemanticsLabel('Open The Fellowship of the Ring, done'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Open The Two Towers, want'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Add The Return of the King'),
        findsOneWidget,
      );
      await openMenu(tester);
      expect(find.text('Series cover'), findsOneWidget);
      expect(find.text('Choose what to show'), findsOneWidget);
    });

    testWidgets('the list scrolls clear of the pill and "+"', (tester) async {
      await openPage(tester);
      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(AllSeriesScreen),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        (scroll.padding! as EdgeInsets).bottom,
        AppShell.contentBottomPadding,
      );
    });

    testWidgets('a part opens its details sheet; closing it comes back', (
      tester,
    ) async {
      await openPage(tester);
      await tester.tap(find.bySemanticsLabel('Open The Two Towers, want'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsSheet), findsOneWidget);
      expect(find.text('MOVIE · 2002'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsSheet), findsNothing);
      expect(find.byType(AllSeriesScreen), findsOneWidget);
      expect(find.text('4 movies · 2 in your library'), findsOneWidget);
    });

    testWidgets('Cover picks the part whose cover stands for the series', (
      tester,
    ) async {
      final container = await openPage(tester);
      await openMenu(tester);
      await tester.tap(find.text('Series cover'));
      await tester.pumpAndSettle();
      expect(find.text('Series cover'), findsOneWidget);
      expect(
        find.text('Shown for The Lord of the Rings in your library'),
        findsOneWidget,
      );
      expect(find.text('First in the series'), findsOneWidget);
      expect(find.text('Your pick'), findsNothing);
      await tester.tap(
        find.bySemanticsLabel('The Lord of the Rings: The Two Towers'),
      );
      await tester.pumpAndSettle();
      expect(find.text('First in the series'), findsNothing);
      expect(find.text('Your pick'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('Series cover'), findsNothing);
      final repository =
          container.read(libraryRepositoryProvider) as FixtureLibraryRepository;
      expect(repository.current!.entryById(_towers)!.series!.cover, isTrue);
      expect(repository.current!.entryById(_fellowship)!.series!.cover, isNull);

      // Opened again, the pick is ringed; Done without a change applies
      // nothing.
      await openMenu(tester);
      await tester.tap(find.text('Series cover'));
      await tester.pumpAndSettle();
      expect(find.text('Your pick'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Done'));
      await tester.pumpAndSettle();
      expect(repository.current!.entryById(_towers)!.series!.cover, isTrue);
    });

    testWidgets('with one part in the library there is no Series cover', (
      tester,
    ) async {
      final library = loadFixture();
      await pumpApp(
        tester,
        const _PageOpener(_fellowship),
        library: library.copyWith(
          entries: [
            for (final e in library.entries)
              if (e.id != _towers) e,
          ],
        ),
        lookupOverrides: fakeLookupOverrides(),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('4 movies · 1 in your library'), findsOneWidget);
      await openMenu(tester);
      expect(find.text('Series cover'), findsNothing);
      expect(find.text('Choose what to show'), findsOneWidget);
    });

    testWidgets(
      'Choose what to show hides a part not in the library, and the hidden '
      'row shows it for now (Library › Series page: hidden parts)',
      (tester) async {
        final container = await openPage(tester);
        await openMenu(tester);
        await tester.tap(find.text('Choose what to show'));
        await tester.pumpAndSettle();
        expect(find.text('Show in this series'), findsOneWidget);
        // Only the part not in the library is listed, ticked.
        final row = find.bySemanticsLabel('The Return of the King');
        expect(row, findsOneWidget);
        expect(find.text('Number 3 · 2003'), findsOneWidget);
        await tester.tap(row);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppButton, 'Done'));
        await tester.pumpAndSettle();

        expect(find.text('Show in this series'), findsNothing);
        expect(find.text('3 movies · 2 in your library'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Add The Return of the King'),
          findsNothing,
        );
        expect(find.text('1 hidden part'), findsOneWidget);
        expect(
          container
              .read(displayPreferencesProvider)
              .hiddenPartsOf('movies:${titleKey('The Lord of the Rings')}'),
          {'fake:the-lord-of-the-rings-the-return-of-the-king'},
        );

        await tester.tap(find.widgetWithText(TextButton, 'Show'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Add The Return of the King'),
          findsOneWidget,
        );
        // Still not counted while it shows.
        expect(find.text('3 movies · 2 in your library'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Hide'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Add The Return of the King'),
          findsNothing,
        );

        // Ticked again, it is back and nothing is kept for the series.
        await openMenu(tester);
        await tester.tap(find.text('Choose what to show'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('The Return of the King'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppButton, 'Done'));
        await tester.pumpAndSettle();
        expect(find.text('4 movies · 2 in your library'), findsOneWidget);
        expect(find.text('1 hidden part'), findsNothing);
        expect(
          container.read(displayPreferencesProvider).hiddenSeriesParts,
          {},
        );
      },
    );
  });

  testWidgets(
    'an extra of the automatic rules starts hidden, and Choose what to show '
    'shows it (Library › Book series after the automatic rules)',
    (tester) async {
      const SeriesParts withExtra = (
        name: 'The Lord of the Rings',
        parts: [
          (
            number: 1,
            title: 'The Lord of the Rings: The Fellowship of the Ring',
            year: 2001,
            released: null,
            source: 'fake:the-lord-of-the-rings-the-fellowship-of-the-ring',
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: 2,
            title: 'The Lord of the Rings: The Two Towers',
            year: 2002,
            released: null,
            source: 'fake:the-lord-of-the-rings-the-two-towers',
            creator: null,
            cover: null,
            extra: false,
          ),
          (
            number: null,
            title: 'The Appendices',
            year: 2003,
            released: null,
            source: 'fake:appendices',
            creator: null,
            cover: null,
            extra: true,
          ),
        ],
      );
      final container = await pumpApp(
        tester,
        const _PageOpener(_fellowship),
        lookupOverrides: fakeLookupOverrides(
          source: FakeLookupSource(
            seriesBySource: {
              'fake:the-lord-of-the-rings-the-fellowship-of-the-ring':
                  withExtra,
              'fake:the-lord-of-the-rings-the-two-towers': withExtra,
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('2 movies · 2 in your library'), findsOneWidget);
      expect(find.text('1 hidden part'), findsOneWidget);
      expect(find.bySemanticsLabel('Add The Appendices'), findsNothing);

      await tester.tap(find.byTooltip('Series options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose what to show'));
      await tester.pumpAndSettle();
      final row = find.bySemanticsLabel('The Appendices');
      expect(
        tester.getSemantics(row).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(row).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Done'));
      await tester.pumpAndSettle();

      expect(find.text('3 movies · 2 in your library'), findsOneWidget);
      expect(find.text('1 hidden part'), findsNothing);
      expect(find.bySemanticsLabel('Add The Appendices'), findsOneWidget);
      final prefs = container.read(displayPreferencesProvider);
      final key = 'movies:${titleKey('The Lord of the Rings')}';
      expect(prefs.shownPartsOf(key), {'fake:appendices'});
      expect(prefs.hiddenPartsOf(key), isEmpty);
    },
  );

  testWidgets(
    'a series the lookup could not update says so, and Try again asks again '
    '(Library › Series page: couldn\'t update)',
    (tester) async {
      final source = _FlakySeries();
      addTearDown(() => seasonClock = DateTime.now);
      await pumpApp(
        tester,
        const _PageOpener(_fellowship),
        lookupOverrides: fakeLookupOverrides(source: source),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('4 movies · 2 in your library'), findsOneWidget);
      expect(find.text('Couldn’t update this series'), findsNothing);

      // A week on, the stored list is asked about again, and the lookup
      // does not answer: the stored list stays, with the line.
      source.failing = true;
      final later = DateTime.now().add(const Duration(days: 8));
      seasonClock = () => later;
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('4 movies · 2 in your library'), findsOneWidget);
      expect(find.text('Couldn’t update this series'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t update this series'), findsOneWidget);

      source.failing = false;
      await tester.tap(find.widgetWithText(TextButton, 'Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Couldn’t update this series'), findsNothing);
      expect(find.text('4 movies · 2 in your library'), findsOneWidget);
    },
  );

  test('splitHiddenRows never hides a part in the library', () {
    final owned = SeriesRow(
      title: 'Owned',
      entry: loadFixture().entryById(_fellowship),
      partKey: 'a',
    );
    const missing = SeriesRow(title: 'Missing', partKey: 'b');
    const other = SeriesRow(title: 'Other', partKey: 'c');
    const extra = SeriesRow(title: 'Extra', partKey: 'd', extra: true);
    const shownExtra = SeriesRow(
      title: 'Shown extra',
      partKey: 'e',
      extra: true,
    );
    final ownedExtra = SeriesRow(
      title: 'Owned extra',
      entry: loadFixture().entryById(_fellowship),
      partKey: 'f',
      extra: true,
    );
    final (:shown, :hidden) = splitHiddenRows(
      [owned, missing, other, extra, shownExtra, ownedExtra],
      (hidden: {'a', 'b'}, shown: {'e'}),
    );
    expect(shown.map((r) => r.title), [
      'Owned',
      'Other',
      'Shown extra',
      'Owned extra',
    ]);
    expect(hidden.map((r) => r.title), ['Missing', 'Extra']);
  });

  test('an extra never takes an owned part by its number', () {
    // Wikidata's six-book edition numbers its books 1 to 6 too.
    final towers = loadFixture().entryById(_towers)!;
    final rows = seriesRows(
      current: towers,
      library: loadFixture().entries,
      parts: (
        name: 'The Lord of the Rings',
        parts: [
          (
            number: 2,
            title: 'The Journey of the Nine Companions',
            year: null,
            released: null,
            source: 'wikidata:Q2',
            creator: null,
            cover: null,
            extra: true,
          ),
          (
            number: 2,
            title: 'The Lord of the Rings: The Two Towers',
            year: 2002,
            released: null,
            source: 'wikidata:Q1',
            creator: null,
            cover: null,
            extra: false,
          ),
        ],
      ),
    );
    final matched = rows.firstWhere((r) => r.entry?.id == _towers);
    expect(matched.extra, isFalse);
    expect(
      rows
          .firstWhere((r) => r.title == 'The Journey of the Nine Companions')
          .owned,
      isFalse,
    );
  });
}

/// The fake lookup, whose series lists fail while [failing] is set.
class _FlakySeries extends FakeLookupSource {
  bool failing = false;

  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    if (failing) throw const LookupException(LookupFailure.offline);
    return super.seriesParts(source, name: name);
  }
}
