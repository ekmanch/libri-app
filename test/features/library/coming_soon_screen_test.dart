import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/series_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/series.dart';
import 'package:library_app/features/library/coming_soon_screen.dart';
import 'package:library_app/features/library/home_sections.dart';
import 'package:library_app/features/settings/display_preferences.dart';

import '../../helpers/pump_app.dart';

void main() {
  final today = DateTime(2026, 10, 28);
  setUp(() => seasonClock = () => today);
  tearDown(() => seasonClock = DateTime.now);

  Entry entry(
    String id,
    MediaType type, {
    required String title,
    Released? released,
    String? creator,
    EntryStatus status = EntryStatus.want,
    List<Season>? seasons,
    Series? series,
    String description = '',
  }) => Entry(
    id: id,
    type: type,
    title: title,
    released: released,
    creator: creator,
    status: status,
    added: DateTime(2026, 1, 1),
    seasons: seasons,
    series: series,
    description: description,
  );

  const gollum = UpcomingPart(
    type: MediaType.movies,
    seriesName: 'The Lord of the Rings',
    entryId: 'movies/fellowship',
    title: 'The Lord of the Rings: The Hunt for Gollum',
    released: Released(2027, 12, 17),
    number: 4,
    source: 'fake:the-lord-of-the-rings-the-hunt-for-gollum',
  );

  Library library() => Library(
    entries: [
      entry(
        'movies/werwulf',
        MediaType.movies,
        title: 'Werwulf',
        released: const Released(2026, 12, 25),
        creator: 'Robert Eggers',
      ),
      entry(
        'books/winds',
        MediaType.books,
        title: 'The Winds of Winter',
        creator: 'George R. R. Martin',
      ),
      entry(
        'shows/stranger-things',
        MediaType.shows,
        title: 'Stranger Things',
        creator: 'The Duffer Brothers',
        status: EntryStatus.done,
        description: 'A missing boy, a girl with powers, a town upside down.',
        seasons: const [
          Season(season: 1, released: Released(2016), status: EntryStatus.done),
          Season(season: 2, released: Released(2017), status: EntryStatus.done),
          Season(season: 5, released: Released(2026, 11, 26)),
        ],
      ),
      entry(
        'movies/fellowship',
        MediaType.movies,
        title: 'The Fellowship of the Ring',
        released: const Released(2001),
        status: EntryStatus.done,
        series: const Series(name: 'The Lord of the Rings', number: 1),
      ),
      entry(
        'movies/towers',
        MediaType.movies,
        title: 'The Two Towers',
        released: const Released(2002),
        status: EntryStatus.done,
        series: const Series(name: 'The Lord of the Rings', number: 2),
      ),
    ],
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool everything = false,
    DisplayPreferences? prefs,
  }) => pumpApp(
    tester,
    ComingSoonScreen(startEverything: everything),
    library: library(),
    prefs: prefs,
    lookupOverrides: fakeLookupOverrides(
      upcomingParts: MemoryUpcomingPartsStore(const [gollum]),
    ),
  );

  Finder row(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(HomeRow));

  testWidgets('Your wants lists what the owner wants, by month', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('2 entries you want'), findsOneWidget);
    expect(find.text('DECEMBER'), findsOneWidget);
    expect(find.text('Werwulf'), findsOneWidget);
    expect(find.text('Movie · Robert Eggers'), findsOneWidget);
    expect(find.text('Dec 25'), findsOneWidget);
    expect(find.text('DATE NOT SET'), findsOneWidget);
    expect(find.text('The Winds of Winter'), findsOneWidget);
    expect(find.text('Date not set'), findsOneWidget);
    // Not wanted: only in Everything upcoming.
    expect(find.text('Stranger Things'), findsNothing);
    expect(find.text('The Hunt for Gollum'), findsNothing);
    expect(find.text('Want'), findsNothing);
    expect(find.text('Add'), findsNothing);
    expect(find.text(ComingSoonScreen.hint), findsNothing);

    // A wanted row opens the entry's details.
    await tester.tap(row('Werwulf'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailsSheet), findsOneWidget);
  });

  testWidgets('Everything upcoming adds seasons and parts with Want or Add', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Everything upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('4 upcoming · 2 not in your library'), findsOneWidget);
    expect(find.text(ComingSoonScreen.hint), findsOneWidget);
    expect(find.text('NOVEMBER'), findsOneWidget);
    expect(find.text('Stranger Things'), findsOneWidget);
    expect(find.text('Show · Season 5'), findsOneWidget);
    expect(find.text('Nov 26'), findsOneWidget);
    expect(find.text('DECEMBER'), findsOneWidget);
    expect(find.text('DECEMBER 2027'), findsOneWidget);
    expect(find.text('The Hunt for Gollum'), findsOneWidget);
    expect(find.text('Movie · The Lord of the Rings'), findsOneWidget);
    expect(find.text('Dec 17, 2027'), findsOneWidget);
    expect(find.text('Want'), findsNWidgets(2));
    expect(find.text('Add'), findsNWidgets(2));
    // The order on screen: the rows by date, undated last.
    final titles = tester
        .widgetList<HomeRow>(find.byType(HomeRow))
        .map((r) => r.row.title)
        .toList();
    expect(titles, [
      'Stranger Things',
      'Werwulf',
      'The Hunt for Gollum',
      'The Winds of Winter',
    ]);
  });

  testWidgets('opens on Everything upcoming when asked', (tester) async {
    await pump(tester, everything: true);
    expect(find.text('4 upcoming · 2 not in your library'), findsOneWidget);
    await tester.tap(find.text('Your wants'));
    await tester.pumpAndSettle();
    expect(find.text('2 entries you want'), findsOneWidget);
  });

  testWidgets(
    'an Add row opens the add sheet; Add to library sets a season Want',
    (tester) async {
      final container = await pump(tester, everything: true);
      await tester.tap(row('Stranger Things'));
      await tester.pumpAndSettle();
      expect(find.byType(UpcomingAddSheet), findsOneWidget);
      expect(find.text('SHOW · NOV 26'), findsOneWidget);
      expect(find.text('Stranger Things, Season 5'), findsOneWidget);
      expect(find.text('The Duffer Brothers'), findsOneWidget);
      expect(
        find.text('A missing boy, a girl with powers, a town upside down.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Why it’s here: Stranger Things is in your library; '
          'seasons 1 and 2 are Done.',
        ),
        findsOneWidget,
      );
      expect(find.text(UpcomingAddSheet.note), findsOneWidget);

      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();
      expect(find.byType(UpcomingAddSheet), findsNothing);
      final show = container
          .read(libraryProvider)
          .value!
          .entryById('shows/stranger-things')!;
      expect(
        show.seasons!.singleWhere((s) => s.season == 5).status,
        EntryStatus.want,
      );
      expect(find.text('4 upcoming · 1 not in your library'), findsOneWidget);
      expect(find.text('Want'), findsNWidgets(3));
      expect(find.text('Add'), findsOneWidget);
    },
  );

  testWidgets('Add to library on a part starts a new entry for it', (
    tester,
  ) async {
    await pump(tester, everything: true);
    await tester.tap(row('The Hunt for Gollum'));
    await tester.pumpAndSettle();
    expect(find.text('MOVIE · DEC 17, 2027'), findsOneWidget);
    expect(
      find.text('The Lord of the Rings: The Hunt for Gollum'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Why it’s here: Part 4 of The Lord of the Rings; '
        'parts 1 and 2 are in your library.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(find.byType(NewEntryScreen), findsOneWidget);
  });

  testWidgets('Not interested hides the row: a part through its series', (
    tester,
  ) async {
    final container = await pump(tester, everything: true);
    await tester.tap(row('The Hunt for Gollum'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not interested'));
    await tester.pumpAndSettle();
    expect(find.text('The Hunt for Gollum'), findsNothing);
    expect(find.text('3 upcoming · 1 not in your library'), findsOneWidget);
    expect(
      container
          .read(displayPreferencesProvider)
          .hiddenPartsOf(seriesKey(MediaType.movies, 'The Lord of the Rings')),
      {'fake:the-lord-of-the-rings-the-hunt-for-gollum'},
    );

    await tester.tap(row('Stranger Things'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not interested'));
    await tester.pumpAndSettle();
    expect(find.text('Stranger Things'), findsNothing);
    expect(find.text('2 upcoming · 0 not in your library'), findsOneWidget);
    expect(container.read(displayPreferencesProvider).hiddenUpcoming, {
      'shows/stranger-things#5',
    });
  });

  testWidgets('says when nothing is coming', (tester) async {
    await pumpApp(
      tester,
      const ComingSoonScreen(),
      library: Library(
        entries: [
          entry(
            'movies/old',
            MediaType.movies,
            title: 'Old',
            released: const Released(1999),
            status: EntryStatus.done,
          ),
        ],
      ),
    );
    expect(find.text('0 entries you want'), findsOneWidget);
    expect(find.text(ComingSoonScreen.emptyWants), findsOneWidget);
    await tester.tap(find.text('Everything upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('0 upcoming · 0 not in your library'), findsOneWidget);
    expect(find.text(ComingSoonScreen.emptyEverything), findsOneWidget);
  });
}
