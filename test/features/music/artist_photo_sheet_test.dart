import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/dev/fake_artists.dart';
import 'package:library_app/dev/fake_covers.dart';
import 'package:library_app/dev/fake_images.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/music/artist_photo_sheet.dart';
import 'package:library_app/features/music/artist_screen.dart';
import 'package:library_app/features/music/artist_tiles.dart';
import 'package:library_app/features/music/artist_index.dart';
import 'package:library_app/widgets/cover_choice.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

Entry album(String title, String artist, int year) => Entry(
  id: 'music/${title.toLowerCase().replaceAll(' ', '-')}',
  type: MediaType.music,
  title: title,
  released: Released(year),
  creator: artist,
  status: EntryStatus.done,
  added: DateTime(2026, 1, year % 28 + 1),
  kind: EntryKind.album,
);

void main() {
  late CoverStore store;
  late FakeAppleArtists apple;
  late FakeCoverSources sources;
  late FakeCoverPictures pictures;

  final library = Library(
    entries: [
      dirt,
      album('Facelift', 'Alice in Chains', 1990),
      album('Impera', 'Ghost', 2022),
    ],
  );

  /// Lets the image cache and the store, which work off the real clock,
  /// finish, then draws.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String name = 'Alice in Chains',
    Map<String, Uint8List> files = const {},
    Set<String> noPhoto = const {},
  }) async {
    store = fakeCoverStore(files: files);
    await store.refresh();
    apple = FakeAppleArtists(noPhoto: noPhoto);
    sources = FakeCoverSources(photo: Uint8List.fromList('a photo'.codeUnits));
    pictures = FakeCoverPictures(size: (1000, 1000));
    final container = await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showArtistPhotoPicker(context, name: name),
            child: const Text('Open'),
          ),
        ),
      ),
      library: library,
      lookupOverrides: fakeLookupOverrides(appleArtists: apple),
      overrides: [
        coverStoreProvider.overrideWithValue(store),
        coverSourcesProvider.overrideWithValue(sources),
        coverPicturesProvider.overrideWithValue(pictures),
      ],
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await settle(tester);
    return container;
  }

  List<String> captions(WidgetTester tester) => [
    for (final tile in tester.widgetList<CoverChoice>(find.byType(CoverChoice)))
      tile.title,
  ];

  CoverChoice tile(WidgetTester tester, String caption) => tester
      .widgetList<CoverChoice>(find.byType(CoverChoice))
      .firstWhere((t) => t.title == caption);

  Future<void> tapTile(WidgetTester tester, String caption) async {
    final finder = find.widgetWithText(CoverChoice, caption).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets('one list of round tiles with no headings and no source '
      'names: Upload, Suggested, Another photo, then the album covers, the '
      'cover in use ringed while there is no file', (tester) async {
    await open(tester);
    expect(find.text('Pick a photo'), findsOneWidget);
    expect(find.text('Alice in Chains'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(captions(tester), [
      'Suggested',
      'Another photo',
      // The most recently added first.
      'Album cover · 1992',
      'Album cover · 1990',
    ]);
    expect(
      tester
          .widgetList<CoverChoice>(find.byType(CoverChoice))
          .every((t) => t.round),
      isTrue,
    );
    expect(tile(tester, 'Album cover · 1992').picked, isTrue);
    expect(tile(tester, 'Suggested').picked, isFalse);
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.textContaining('Deezer'), findsNothing);
    expect(find.textContaining('.jpg'), findsNothing);
    // Asked once, when the sheet opened.
    expect(apple.calls, ['choices:Alice in Chains']);
    // Nothing is yours yet, and there is one artist of the name.
    expect(find.text('Use automatic'), findsNothing);
    expect(find.textContaining('Not the right artist?'), findsNothing);
  });

  testWidgets('a tap is the choice, saved at once: the tile becomes Your '
      'photo, and Use automatic takes it back', (tester) async {
    await open(tester);
    await tapTile(tester, 'Another photo');
    final put = store.pending.whereType<ArtistPhotoPut>().single;
    expect(put.path, 'artists/alice-in-chains.jpg');
    expect(put.picked, isTrue);
    expect(put.summary, 'Set the photo of Alice in Chains');
    expect(store.photoKindOf('Alice in Chains'), PhotoKind.picked);
    expect(captions(tester).first, 'Your photo');
    expect(tile(tester, 'Your photo').picked, isTrue);
    expect(tile(tester, 'Your photo').badge, 'Yours');
    expect(tile(tester, 'Album cover · 1992').picked, isFalse);

    await tester.ensureVisible(find.text('Use automatic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use automatic'));
    await settle(tester);
    expect(store.artistPhoto('Alice in Chains'), isNull);
    expect(find.text('Your photo'), findsNothing);
    expect(find.text('Use automatic'), findsNothing);
    expect(tile(tester, 'Album cover · 1992').picked, isTrue);
  });

  testWidgets('the photo found for the artist, once it is the file, is the '
      'Suggested tile, ringed; picking the suggested one is the fetch\'s, '
      'not a pick', (tester) async {
    await open(tester);
    await tapTile(tester, 'Suggested');
    final put = store.pending.whereType<ArtistPhotoPut>().single;
    expect(put.picked, isFalse);
    expect(store.photoKindOf('Alice in Chains'), isNull);
    expect(captions(tester).first, 'Suggested');
    expect(tile(tester, 'Suggested').picked, isTrue);
    expect(find.text('Your photo'), findsNothing);
    expect(find.text('Use automatic'), findsNothing);
  });

  testWidgets('with several artists of the name the link loads the others '
      'on demand, each captioned with one of its albums', (tester) async {
    await open(tester, name: 'Ghost');
    const link = 'Not the right artist? Show others named Ghost';
    expect(find.text(link), findsOneWidget);
    expect(apple.calls, ['choices:Ghost']);
    await tester.ensureVisible(find.text(link));
    await tester.pumpAndSettle();
    await tester.tap(find.text(link));
    await settle(tester);
    expect(find.text(link), findsNothing);
    expect(apple.calls.skip(1), [
      'photo:ghost-o0',
      'photo:ghost-o1',
      'photo:ghost-o2',
    ]);
    expect(
      captions(tester),
      containsAllInOrder([
        'Suggested',
        'Another photo',
        'Ghost in the Machine',
        'Ghost Stories Live',
        'Ghosts of the Past',
        'Album cover · 2022',
      ]),
    );
  });

  testWidgets('no photo found: it says so and offers the album covers and '
      'Upload', (tester) async {
    await open(tester, noPhoto: {'alice-in-chains'});
    expect(
      find.text(
        'No photo was found for this artist, so one of your album covers '
        'is shown.',
      ),
      findsOneWidget,
    );
    expect(find.text('Suggested'), findsNothing);
    expect(find.text('Upload'), findsOneWidget);
    expect(tile(tester, 'Album cover · 1992').picked, isTrue);
  });

  testWidgets('Upload is the covers\' sheet, saved as your photo; a picture '
      'that is not square opens Fit your cover at 1:1', (tester) async {
    await open(tester);
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Upload a photo'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(store.photoKindOf('Alice in Chains'), PhotoKind.uploaded);
    expect(tile(tester, 'Your photo').badge, 'Yours');
    expect(find.text('Use automatic'), findsOneWidget);

    pictures.size = (1000, 1500);
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();
    expect(find.text('Fit your cover'), findsOneWidget);
    expect(
      find.text('1000 × 1500. It isn’t 1:1, so part of it is cut.'),
      findsOneWidget,
    );
  });

  testWidgets('a photo set on another device shows as Suggested, with no '
      'Use automatic', (tester) async {
    await open(
      tester,
      files: {
        'artists/alice-in-chains.jpg': fakeCoverPng('theirs', square: true),
      },
    );
    expect(captions(tester).first, 'Suggested');
    expect(tile(tester, 'Suggested').picked, isTrue);
    expect(find.text('Use automatic'), findsNothing);
  });

  group('the ways in', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      Widget home, {
      Map<String, Uint8List> files = const {},
    }) async {
      store = fakeCoverStore(files: files);
      await store.refresh();
      await pumpApp(
        tester,
        home,
        library: library,
        overrides: [coverStoreProvider.overrideWithValue(store)],
      );
    }

    testWidgets('the artist page has the round photo in the text view too: '
        'a tap shows it larger with Change photo, a long press on it or on '
        'the name opens the picker', (tester) async {
      await pumpScreen(
        tester,
        const ArtistScreen(name: 'Alice in Chains'),
        files: {
          'artists/alice-in-chains.jpg': fakeCoverPng('aic', square: true),
        },
      );
      final photo = find.bySemanticsLabel(
        'Alice in Chains. Tap to see the photo, long-press to change it',
      );
      expect(photo, findsOneWidget);
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(find.text('Change photo'), findsOneWidget);
      expect(find.text('Add a photo'), findsNothing);
      expect(find.textContaining('No photo yet.'), findsNothing);
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a photo'), findsOneWidget);
      expect(find.text('Change photo'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.longPress(photo);
      await tester.pumpAndSettle();
      expect(find.text('Pick a photo'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Alice in Chains'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a photo'), findsOneWidget);
    });

    testWidgets('an artist with no file of their own: the larger view says '
        'so and its button reads Add a photo, which opens the picker '
        '(Music › Artist photo, larger: no photo yet)', (tester) async {
      await pumpScreen(tester, const ArtistScreen(name: 'Alice in Chains'));
      await tester.tap(
        find.bySemanticsLabel(
          'Alice in Chains. Tap to see the photo, long-press to change it',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No photo yet.'), findsOneWidget);
      expect(find.text('Change photo'), findsNothing);
      await tester.tap(find.text('Add a photo'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a photo'), findsOneWidget);
      // With one of the library's covers standing in, or initials alone.
      expect(
        noArtistPhotoNote(cover: true),
        'No photo yet. One of your album covers is shown.',
      );
      expect(noArtistPhotoNote(cover: false), 'No photo yet.');
    });

    testWidgets('a long press on an artist\'s row or tile opens the picker, '
        'in every view', (tester) async {
      final artist = artistIndex(library.entries).first;
      for (final view in [
        ArtistRow(artist: artist, onTap: () {}),
        ArtistRow(artist: artist, onTap: () {}, photo: true),
        SizedBox(
          width: 100,
          child: ArtistGridTile(artist: artist, onTap: () {}),
        ),
      ]) {
        await pumpScreen(tester, Scaffold(body: Center(child: view)));
        await tester.longPress(find.text(artist.name));
        await tester.pumpAndSettle();
        expect(find.text('Pick a photo'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
    });
  });

  testWidgets('a pick a sync dropped is said at the bottom, with Pick '
      'again, which opens the picker for that artist (Music › Artist '
      'photo: your pick wasn\'t saved)', (tester) async {
    store = fakeCoverStore();
    await store.refresh();
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDroppedPhotos(context, const [
              DroppedPhoto(
                path: 'artists/alice-in-chains.jpg',
                name: 'Alice in Chains',
              ),
              // A refused Use automatic is reported the same way, and an
              // artist is told once.
              DroppedPhoto(
                path: 'artists/alice-in-chains.jpg',
                name: 'Alice in Chains',
                removal: true,
              ),
            ]),
            child: const Text('Sync'),
          ),
        ),
      ),
      library: library,
      overrides: [coverStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Another device chose a photo for Alice in Chains first, so your '
        'pick was dropped.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Pick again'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a photo'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
  });

  testWidgets('the dropped pick message leaves after ten seconds', (
    tester,
  ) async {
    store = fakeCoverStore();
    await store.refresh();
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDroppedPhotos(context, const [
              DroppedPhoto(
                path: 'artists/alice-in-chains.jpg',
                name: 'Alice in Chains',
              ),
            ]),
            child: const Text('Sync'),
          ),
        ),
      ),
      library: library,
      overrides: [coverStoreProvider.overrideWithValue(store)],
    );
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Pick again'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Pick again'), findsNothing);
  });
}
