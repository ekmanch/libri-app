import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_providers.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/series_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_images.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/upcoming/creator_lookup.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/features/entry/entry_details_sheet.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/series.dart';
import 'package:library_app/features/library/coming_soon_screen.dart';
import 'package:library_app/features/library/home_sections.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/widgets/cached_image.dart';
import 'package:library_app/widgets/cover_placeholder.dart';

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

  const gollumCover =
      'fake://cover/poster/fake:the-lord-of-the-rings-the-hunt-for-gollum';
  const gollum = UpcomingPart(
    type: MediaType.movies,
    seriesName: 'The Lord of the Rings',
    entryId: 'movies/fellowship',
    title: 'The Lord of the Rings: The Hunt for Gollum',
    released: Released(2027, 12, 17),
    number: 4,
    source: 'fake:the-lord-of-the-rings-the-hunt-for-gollum',
    cover: gollumCover,
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

  Finder cover(String? url) =>
      find.byWidgetPredicate((w) => w is CachedImage && w.url == url);

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

  testWidgets('a swipe moves between the segments', (tester) async {
    await pump(tester);
    expect(find.text('2 entries you want'), findsOneWidget);
    expect(find.text('Stranger Things'), findsNothing);

    // Left: Everything upcoming, with the hint and the Add rows.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('4 upcoming · 2 not in your library'), findsOneWidget);
    expect(find.text(ComingSoonScreen.hint), findsOneWidget);
    expect(find.text('Stranger Things'), findsOneWidget);

    // Right: back to Your wants. Nothing past the ends.
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 entries you want'), findsOneWidget);
    expect(find.text(ComingSoonScreen.hint), findsNothing);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
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
    // The part has a lookup id, so the form opens prefilled from it, as
    // Want; nothing is looked up again by hand.
    expect(find.byType(NewEntryScreen), findsNothing);
    expect(find.byType(EntryFormScreen), findsOneWidget);
    expect(
      find.widgetWithText(
        TextField,
        'The Lord of the Rings: The Hunt for Gollum',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the sheet shows the cover the check recorded, fetched when it opens, '
    'and the form starts with it',
    (tester) async {
      final container = await pump(tester, everything: true);
      final fetcher = container.read(imageFetcherProvider) as FakeImageFetcher;
      // The list is text rows: nothing is fetched for it.
      expect(fetcher.fetched, isEmpty);
      await tester.tap(row('The Hunt for Gollum'));
      await tester.pumpAndSettle();
      expect(cover(gollumCover), findsOneWidget);
      // The fake fetcher writes the file off the frame clock.
      for (var i = 0; i < 40 && find.byType(Image).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(fetcher.fetched, [gollumCover]);
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryFormScreen), findsOneWidget);
      // The same image, already on the device: not fetched again.
      expect(cover(gollumCover), findsOneWidget);
      expect(fetcher.fetched, [gollumCover]);
    },
  );

  testWidgets('a part without a lookup id is looked up by its title', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const ComingSoonScreen(startEverything: true),
      library: library(),
      lookupOverrides: fakeLookupOverrides(
        upcomingParts: MemoryUpcomingPartsStore(const [
          UpcomingPart(
            type: MediaType.movies,
            seriesName: 'The Lord of the Rings',
            entryId: 'movies/fellowship',
            title: 'The Lord of the Rings: The War of the Rohirrim',
            released: Released(2027, 6),
            number: 3,
          ),
        ]),
      ),
    );
    await tester.tap(row('The War of the Rohirrim'));
    await tester.pumpAndSettle();
    // No cover recorded yet: the placeholder, and nothing fetched.
    expect(cover(null), findsOneWidget);
    expect(find.byType(CoverPlaceholder), findsOneWidget);
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(find.byType(NewEntryScreen), findsOneWidget);
  });

  testWidgets('a followed creator\'s release is an Add row; the form opens '
      'prefilled; Not interested hides it through the settings', (
    tester,
  ) async {
    final found = FoundRelease(
      kind: FollowKind.artists,
      creatorId: 'alice in chains',
      creatorName: 'Alice in Chains',
      match: const LookupMatch(
        type: MediaType.music,
        title: 'Rainier Fog II',
        source: 'fake:aic-next',
        released: Released(2026, 11, 20),
        creator: 'Alice in Chains',
        description: 'The eighth album.',
      ),
      foundOn: DateTime(2026, 10, 28),
    );
    final container = await pumpApp(
      tester,
      const ComingSoonScreen(startEverything: true),
      library: library(),
      lookupOverrides: fakeLookupOverrides(
        upcomingParts: MemoryUpcomingPartsStore(const [gollum]),
        foundReleases: MemoryFoundReleaseStore([found]),
      ),
    );
    expect(find.text('5 upcoming · 3 not in your library'), findsOneWidget);
    expect(find.text('Rainier Fog II'), findsOneWidget);
    expect(find.text('Music · Alice in Chains'), findsOneWidget);
    expect(find.text('Nov 20'), findsOneWidget);
    await tester.tap(row('Rainier Fog II'));
    await tester.pumpAndSettle();
    expect(find.text('MUSIC · NOV 20'), findsOneWidget);
    expect(
      find.text(
        'Why it’s here: A new album by Alice in Chains, whom you follow.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Add to library'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryFormScreen), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Rainier Fog II'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(row('Rainier Fog II'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not interested'));
    await tester.pumpAndSettle();
    expect(find.text('Rainier Fog II'), findsNothing);
    expect(
      (await container.read(libraryRepositoryProvider).loadSettings())
          .notInterested,
      {'fake:aic-next'},
    );
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
    expect(
      (await container.read(libraryRepositoryProvider).loadSettings())
          .notInterested,
      {'shows/stranger-things#5'},
    );
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
