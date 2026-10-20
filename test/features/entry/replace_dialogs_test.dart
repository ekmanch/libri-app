import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/features/entry/replace_dialogs.dart';
import 'package:library_app/widgets/segmented_control.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

void main() {
  final fixture = loadFixture();

  group('matching', () {
    final would = dirt.copyWith(
      id: 'music/would-alice-in-chains',
      title: 'Would?',
      kind: EntryKind.song,
      album: 'dirt ',
      rating: 8,
      tracks: null,
    );
    final noAlbum = would.copyWith(id: 'x', title: 'Nutshell', album: null);
    final otherArtist = would.copyWith(id: 'y', creator: 'Nirvana');
    final library = sampleLibrary().copyWith(
      entries: [mummy, dirt, would, noAlbum, otherArtist],
    );

    test('songsFromAlbum needs the same artist and album title', () {
      expect(songsFromAlbum(library, dirt).map((e) => e.id), [would.id]);
    });

    test('albumOfSong needs album info and the same artist', () {
      expect(albumOfSong(library, would)?.id, dirt.id);
      expect(albumOfSong(library, noAlbum), isNull);
      expect(albumOfSong(library, otherArtist), isNull);
    });

    test('albumOfSong trusts a matching album id over the names', () {
      final linked = library.copyWith(
        entries: [
          mummy,
          dirt.copyWith(source: 'deezer:album:91627'),
          noAlbum,
        ],
      );
      // No album title on the song, but the lookup said which album.
      expect(
        albumOfSong(linked, noAlbum, albumSource: 'deezer:album:91627')?.id,
        dirt.id,
      );
      // An id nothing carries falls back to the names.
      expect(
        albumOfSong(linked, would, albumSource: 'deezer:album:1')?.id,
        dirt.id,
      );
      expect(
        albumOfSong(linked, noAlbum, albumSource: 'deezer:album:1'),
        isNull,
      );
    });

    test('absorbSongs moves ratings into the track list, once', () {
      final rooster = would.copyWith(id: 'r', title: 'Rooster', rating: 5);
      final unrated = would.copyWith(id: 'u', title: 'Dirt', rating: null);
      final merged = absorbSongs(dirt, [would, rooster, unrated]);
      expect(merged.tracks!.map((t) => (t.title, t.rating)), [
        ('Rooster', 10), // Kept, not overwritten by the song's 5.
        ('Would?', 8),
      ]);
      expect(
        absorbSongs(dirt.copyWith(tracks: null), [unrated]).tracks,
        isNull,
      );
    });
  });

  group('in the form', () {
    FixtureLibraryRepository repo(ProviderContainer c) =>
        c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

    Finder hinted(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );

    Future<ProviderContainer> fillSong(WidgetTester tester) async {
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(type: MediaType.music),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedControl<EntryKind>),
          matching: find.text('Song'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(hinted('Title'), 'Rooster');
      await tester.enterText(hinted('Optional').at(0), 'Alice in Chains');
      await tester.enterText(hinted('Optional').at(1), 'Dirt');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('Dirt is already in your library'), findsOneWidget);
      expect(
        find.text('You are adding the song Rooster from this album.'),
        findsOneWidget,
      );
      return container;
    }

    testWidgets(
      'song over its album: replacing the album deletes it and adds the song',
      (tester) async {
        final container = await fillSong(tester);
        await tester.tap(find.text('Replace album with this song'));
        await tester.pumpAndSettle();
        final library = repo(container).current!;
        expect(library.entryById(dirt.id), isNull);
        final song = library.entries.last;
        expect(song.id, 'music/rooster-alice-in-chains');
        expect(song.kind, EntryKind.song);
        expect(song.album, 'Dirt');
        expect(find.byType(EntryFormScreen), findsNothing);
      },
    );

    testWidgets('song over its album: keeping both leaves the album', (
      tester,
    ) async {
      final container = await fillSong(tester);
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();
      final library = repo(container).current!;
      expect(library.entryById(dirt.id), isNotNull);
      expect(library.entries.last.title, 'Rooster');
    });

    testWidgets(
      'song over its album: cancel saves nothing and keeps the form',
      (tester) async {
        final container = await fillSong(tester);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo(container).current!.entries.length, fixture.entries.length);
        expect(find.byType(EntryFormScreen), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      'album over its songs: an album absorbs its saved songs when replacing',
      (tester) async {
        final container = await pumpApp(
          tester,
          const EntryFormScreen.create(type: MediaType.music),
        );
        await tester.enterText(hinted('Title'), 'Green River');
        await tester.enterText(
          hinted('Optional').at(0),
          'Creedence Clearwater Revival',
        );
        await tester.tap(find.text('Not set'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('${DateTime.now().year}'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '1969');
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();
        expect(
          find.text('You have 1 song from Green River saved'),
          findsOneWidget,
        );
        expect(find.text('Bad Moon Rising'), findsOneWidget);
        await tester.tap(find.text('Replace songs with album'));
        await tester.pumpAndSettle();
        final library = repo(container).current!;
        expect(
          library.entryById(
            'music/bad-moon-rising-creedence-clearwater-revival',
          ),
          isNull,
        );
        final album = library.entries.last;
        expect(album.id, 'music/green-river-creedence-clearwater-revival');
        expect(album.tracks!.single.title, 'Bad Moon Rising');
        expect(album.tracks!.single.rating, 9);
        // The song's tags were only pruned where nothing else uses them.
        expect(library.allTags.contains('halloween'), isTrue);
      },
    );
  });
}
