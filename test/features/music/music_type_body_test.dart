import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/dev/long_lists.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/library_home_screen.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/music/artist_index.dart';
import 'package:library_app/features/music/artist_screen.dart';
import 'package:library_app/features/music/artist_tiles.dart';
import 'package:library_app/features/music/music_tab.dart';
import 'package:library_app/features/music/music_type_body.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/underline_tabs.dart';
import 'package:library_app/widgets/entry_row.dart';

import '../../helpers/pump_app.dart';

void main() {
  final fixture = loadFixture();
  final visible = fixture
      .entriesOfType(MediaType.music)
      .where((e) => !e.seasonalOnly)
      .toList();
  final albums = visible.where((e) => e.kind != EntryKind.song).toList();
  final songs = visible.where((e) => e.kind == EntryKind.song).toList();
  final artists = visible.map((e) => e.creator).toSet().length;

  Future<void> pickMusic(WidgetTester tester) async {
    final chip = find.widgetWithText(ScrollingTab, 'Music');
    final row = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    await tester.dragUntilVisible(chip, row, const Offset(-80, 0));
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> pickTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ChoiceChips<MusicTab>),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Music shows the artist tabs, the tab\'s count and its sort', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    expect(find.byType(StatusChips), findsNothing);
    expect(find.byType(ChoiceChips<MusicTab>), findsOneWidget);
    expect(find.text('$artists artists'), findsOneWidget);
    expect(find.text('Name, A to Z'), findsOneWidget);
    expect(find.byTooltip('Change view'), findsOneWidget);
    // Lazily built, so only the rows on screen exist.
    expect(find.byType(ArtistRow), findsWidgets);
    expect(
      tester.widgetList<ArtistRow>(find.byType(ArtistRow)).first.artist.name,
      '2Pac',
    );
    expect(find.text('Alice in Chains'), findsOneWidget);
    expect(find.text('1 album'), findsWidgets);
    expect(find.byType(EntryRow), findsNothing);
    // Short list: no letter headers.
    expect(find.text('A'), findsNothing);
  });

  testWidgets('an artist row opens the artist screen', (tester) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    await tester.tap(find.text('Alice in Chains'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistScreen), findsOneWidget);
    expect(find.text('ALBUMS'), findsOneWidget);
    expect(find.text('Dirt'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MusicTypeBody), findsOneWidget);
  });

  testWidgets('the Albums tab is a flat list by title', (tester) async {
    // Tall enough for every album row to be built; the list is lazy.
    await pumpApp(
      tester,
      const LibraryHomeScreen(),
      size: const Size(360, 1200),
    );
    await pickMusic(tester);
    await pickTab(tester, 'Albums');
    final rows = tester
        .widgetList<EntryRow>(find.byType(EntryRow))
        .map((r) => r.title)
        .toList();
    expect(rows.length, albums.length);
    expect(
      rows,
      [...rows]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
    expect(find.byType(ArtistRow), findsNothing);
  });

  testWidgets('the Songs tab lists song entries, not songs rated on albums', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    await pickTab(tester, 'Songs');
    expect(find.byType(EntryRow), findsNWidgets(songs.length));
    expect(find.text('Bad Moon Rising'), findsOneWidget);
    // Rooster is rated on Dirt, an album entry; it stays on the album.
    expect(
      albums.any((a) => a.tracks?.any((t) => t.title == 'Rooster') ?? false),
      isTrue,
    );
    expect(find.text('Rooster'), findsNothing);
  });

  testWidgets('the view is remembered per tab', (tester) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    // Artists say "with photos".
    await tester.tap(find.text('Grid with photos'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistGridTile), findsWidgets);
    expect(find.byType(ArtistRow), findsNothing);
    expect(
      container.read(displayPreferencesProvider).viewForMusic(MusicTab.artists),
      EntryView.grid,
    );
    await pickTab(tester, 'Albums');
    expect(find.byType(CoverGridTile), findsNothing);
    expect(find.byType(EntryRow), findsWidgets);
    expect(
      container.read(displayPreferencesProvider).viewForMusic(MusicTab.albums),
      EntryView.text,
    );
    await tester.tap(find.byTooltip('Change view'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List with covers'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryRow), findsWidgets);
    expect(
      tester.widgetList<EntryRow>(find.byType(EntryRow)).first.leading,
      isNotNull,
    );
  });

  testWidgets('a long artist list gets letter headers and a rail', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: padForLongLists(fixture),
    );
    await pickMusic(tester);
    expect(find.byKey(EntryListBody.railKey), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text('VA'), findsOneWidget);
    await tester.tap(find.text('VA'));
    await tester.pumpAndSettle();
    expect(find.text('VARIOUS ARTISTS'), findsOneWidget);
    expect(find.widgetWithText(ArtistRow, 'Various Artists'), findsOneWidget);
  });

  testWidgets('the count line counts the tab shown', (tester) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    await pickTab(tester, 'Albums');
    expect(find.text('${albums.length} albums'), findsOneWidget);
    expect(find.text('$artists artists'), findsNothing);
    await pickTab(tester, 'Songs');
    // Song entries only: the tracks rated on Dirt are not counted.
    expect(find.text('${songs.length} songs'), findsOneWidget);
  });

  testWidgets('each tab offers its own sorts and keeps its own choice', (
    tester,
  ) async {
    final container = await pumpApp(tester, const LibraryHomeScreen());
    DisplayPreferences prefs() => container.read(displayPreferencesProvider);
    await pickMusic(tester);

    await tester.tap(find.text('Name, A to Z'));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Most songs'), findsOneWidget);
    expect(find.text('Artist, A to Z'), findsNothing);
    await tester.tap(find.text('Most albums'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(prefs().musicArtistsSort, ArtistsSort.mostAlbums);
    expect(find.text('Most albums'), findsOneWidget);

    await pickTab(tester, 'Albums');
    await tester.tap(find.text('Title, A to Z'));
    await tester.pumpAndSettle();
    expect(find.text('Name, A to Z'), findsNothing);
    expect(find.text('Rating, highest first'), findsOneWidget);
    await tester.tap(find.text('Artist, A to Z'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(prefs().sortForMusic(MusicTab.albums), LibrarySort.artistAz);
    final rows = tester
        .widgetList<EntryRow>(find.byType(EntryRow))
        .map((r) => r.title)
        .toList();
    expect(
      rows,
      sortEntries(
        albums,
        LibrarySort.artistAz,
      ).take(rows.length).map((e) => e.title),
    );

    // Songs and Artists are as they were.
    expect(prefs().sortForMusic(MusicTab.songs), LibrarySort.titleAz);
    await pickTab(tester, 'Songs');
    expect(find.text('Title, A to Z'), findsOneWidget);
    await tester.tap(find.text('Title, A to Z'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year, newest first'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(prefs().sortForMusic(MusicTab.songs), LibrarySort.yearNewest);
    expect(prefs().sortForMusic(MusicTab.albums), LibrarySort.artistAz);
    expect(prefs().musicArtistsSort, ArtistsSort.mostAlbums);
  });

  testWidgets('artists by anything but name are one list with no rail', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: padForLongLists(fixture),
    );
    container
        .read(displayPreferencesProvider.notifier)
        .setMusicArtistsSort(ArtistsSort.mostAlbums);
    await pickMusic(tester);
    expect(find.byKey(EntryListBody.railKey), findsNothing);
    expect(find.text('A'), findsNothing);
    final counts = tester
        .widgetList<ArtistRow>(find.byType(ArtistRow))
        .map((r) => r.artist.albums.length)
        .toList();
    expect(counts, [...counts]..sort((a, b) => b.compareTo(a)));
  });

  testWidgets('long albums by artist get the artists\' letters on the rail', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      const LibraryHomeScreen(),
      library: padForLongLists(fixture),
    );
    container
        .read(displayPreferencesProvider.notifier)
        .setMusicSort(MusicTab.albums, LibrarySort.artistAz);
    await pickMusic(tester);
    await pickTab(tester, 'Albums');
    expect(find.byKey(EntryListBody.railKey), findsOneWidget);
    expect(find.text('VA'), findsOneWidget);
  });
}
