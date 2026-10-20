import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/dev/long_lists.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/library_home_screen.dart';
import 'package:library_app/features/music/artist_screen.dart';
import 'package:library_app/features/music/artist_tiles.dart';
import 'package:library_app/features/music/music_tab.dart';
import 'package:library_app/features/music/music_type_body.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/entry_row.dart';
import 'package:library_app/widgets/segmented_control.dart';

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
  final ratedTracks = albums.fold(0, (n, a) => n + (a.tracks?.length ?? 0));

  Future<void> pickMusic(WidgetTester tester) async {
    final chip = find.widgetWithText(PillChip, 'Music');
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
        of: find.byType(SegmentedControl<MusicTab>),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Music shows the artist tabs, one count line and no sort', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    expect(find.byType(StatusSegmentedControl), findsNothing);
    expect(find.byType(SegmentedControl<MusicTab>), findsOneWidget);
    expect(
      find.text(
        '$artists artists, ${albums.length} albums, ${songs.length} songs',
      ),
      findsOneWidget,
    );
    expect(find.text('Newest added'), findsNothing);
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

  testWidgets('the Songs tab lists songs and rated tracks together', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen());
    await pickMusic(tester);
    await pickTab(tester, 'Songs');
    expect(songItems(songs, albums).length, songs.length + ratedTracks);
    expect(find.byType(EntryRow), findsNWidgets(songs.length));
    expect(find.byType(TrackRow), findsWidgets);
    expect(find.text('Rooster'), findsOneWidget);
    // One format for songs and rated tracks: artist and year.
    expect(find.text('Alice in Chains · 1992'), findsNWidgets(3));
    expect(find.text('10 / 10'), findsWidgets);
    expect(find.text('Bad Moon Rising'), findsOneWidget);
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
}
