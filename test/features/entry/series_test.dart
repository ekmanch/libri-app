import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/series.dart';
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
          source: 'tmdb:movie:120',
        ),
        (
          number: 2,
          title: 'The Two Towers',
          year: 2002,
          source: 'tmdb:movie:121',
        ),
        (
          number: 3,
          title: 'The Return of the King',
          year: 2003,
          source: 'tmdb:movie:122',
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
      expect(rows.map((r) => r.entry?.id), ['a', 'b', 'c']);
      expect(rows.map((r) => r.title), parts.parts.map((p) => p.title));
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
    expect(find.text('2 of 3 in your library'), findsOneWidget);
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
}
