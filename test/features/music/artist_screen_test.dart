import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/music_kind.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/widgets/cover_placeholder.dart';
import 'package:library_app/features/music/artist_screen.dart';
import 'package:library_app/features/music/music_tab.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/widgets/entry_row.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

void main() {
  final would = dirt.copyWith(
    id: 'music/would-alice-in-chains',
    title: 'Would?',
    kind: MusicKind.song,
    album: 'Dirt',
    tracks: null,
  );
  final facelift = dirt.copyWith(
    id: 'music/facelift-alice-in-chains',
    title: 'Facelift',
    released: const Released(1990),
    tracks: null,
  );
  final library = sampleLibrary().copyWith(
    entries: [mummy, dirt, would, facelift],
  );

  testWidgets('albums then songs, with counts and year subtitles', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const ArtistScreen(name: 'Alice in Chains'),
      library: library,
    );
    expect(find.text('Alice in Chains'), findsOneWidget);
    expect(find.text('2 albums, 1 song'), findsOneWidget);
    expect(find.text('ALBUMS'), findsOneWidget);
    expect(find.text('SONGS'), findsOneWidget);
    final rows = tester
        .widgetList<EntryRow>(find.byType(EntryRow))
        .map((r) => (r.title, r.subtitle))
        .toList();
    expect(rows, [
      ('Facelift', '1990'),
      ('Dirt', '1992'),
      ('Would?', 'Dirt · 1992'),
    ]);
    expect(find.byType(CoverPlaceholder), findsNothing);
    expect(find.text('Year, oldest first'), findsOneWidget);
  });

  testWidgets('the sort link reorders and is kept', (tester) async {
    final container = await pumpApp(
      tester,
      const ArtistScreen(name: 'Alice in Chains'),
      library: library,
    );
    await tester.tap(find.text('Year, oldest first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year, newest first'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    final rows = tester
        .widgetList<EntryRow>(find.byType(EntryRow))
        .map((r) => r.title)
        .toList();
    expect(rows, ['Dirt', 'Facelift', 'Would?']);
    expect(
      container.read(displayPreferencesProvider).artistSort.name,
      'yearNewest',
    );
  });

  testWidgets('a photo view for Artists shows covers', (tester) async {
    final container = await pumpApp(
      tester,
      const ArtistScreen(name: 'Alice in Chains'),
      library: library,
    );
    container
        .read(displayPreferencesProvider.notifier)
        .setMusicView(MusicTab.artists, EntryView.listWithPhotos);
    await tester.pumpAndSettle();
    expect(find.byType(CoverPlaceholder), findsNWidgets(3));
  });

  testWidgets('an unknown name says so instead of crashing', (tester) async {
    await pumpApp(tester, const ArtistScreen(name: 'Nobody'), library: library);
    expect(
      find.text('Nothing saved for this artist any more.'),
      findsOneWidget,
    );
  });
}
