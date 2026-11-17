import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_files.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_covers.dart';
import 'package:library_app/features/settings/artists_without_photo_screen.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/settings/your_covers_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

Uint8List bytes(int length) => Uint8List(length);

const steelbook = 'movies/the-mummy-1999.steelbook.jpg';
const dirtCover = 'music/dirt-alice-in-chains.91be04c.jpg';
const oldPoster = 'movies/old-poster.png';
const gatto = 'movies/gatto-2027.a3f9c2e.jpg';

void main() {
  late CoverStore store;
  final entries = [
    mummy.copyWith(coverFrom: 'repo:$steelbook'),
    dirt.copyWith(coverFrom: 'repo:$dirtCover'),
  ];
  final files = {
    steelbook: bytes(400000),
    dirtCover: bytes(300000),
    oldPoster: bytes(1200000),
    gatto: bytes(100000),
  };

  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
    Map<String, Uint8List>? withFiles,
    List<Entry>? withEntries,
  }) async {
    store = fakeCoverStore(files: withFiles ?? files);
    await store.refresh();
    return pumpApp(
      tester,
      home,
      // Tall enough for every row: the lists build what is in view.
      size: const Size(360, 1400),
      library: Library(entries: withEntries ?? entries),
      overrides: [coverStoreProvider.overrideWithValue(store)],
    );
  }

  test('the rows: unused first with path and reason, then by title', () {
    final list = [
      for (final MapEntry(:key, :value) in files.entries)
        CoverFile(path: key, size: value.length, sha: key),
      const CoverFile(path: 'movies/the-mummy-1999.b.jpg', size: 1, sha: 'x'),
    ];
    final library = Library(entries: entries);
    final rows = CoverReviewRow.of(list, library);
    expect(
      [for (final r in rows) (r.name, r.detail, r.unused)],
      [
        // The one place a path is shown.
        (oldPoster, 'Doesn’t match any title', true),
        // Named by the apps for a title that is gone.
        (gatto, 'Its title was deleted', true),
        ('Dirt', 'Album · Alice in Chains · 1992', false),
        ('The Mummy', 'Movie · 1999 · steelbook', false),
        // Named after the title, but not its cover now.
        ('The Mummy', 'Movie · 1999 · b · not in use', false),
      ],
    );
    expect(
      uploadedCoversSummary(list, library),
      '5 covers · 2 unused · 2.0 MB',
    );
  });

  testWidgets('Library connection lists the group while there are covers', (
    tester,
  ) async {
    await pump(tester, const ConnectionScreen());
    expect(find.text('YOUR COVERS'), findsOneWidget);
    expect(find.text('Uploaded covers'), findsOneWidget);
    expect(find.text('4 covers · 2 unused · 2.0 MB'), findsOneWidget);
    await tester.ensureVisible(find.text('Review'));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byType(YourCoversScreen), findsOneWidget);
  });

  testWidgets('and not without any, nor any artist', (tester) async {
    await pump(
      tester,
      const ConnectionScreen(),
      withFiles: const {},
      withEntries: [mummy],
    );
    expect(find.text('Uploaded covers'), findsNothing);
    expect(find.text('Artist photos'), findsNothing);
    expect(find.text('YOUR COVERS'), findsNothing);
  });

  group('Artist photos (Settings › Library connection: artist photos not '
      'ready yet)', () {
    const record = 'artists/_missing.json';
    Uint8List text(String text) => Uint8List.fromList(text.codeUnits);

    testWidgets('a read-only row that waits for the desktop\'s first run', (
      tester,
    ) async {
      await pump(tester, const ConnectionScreen(), withFiles: const {});
      expect(find.text('YOUR COVERS'), findsOneWidget);
      expect(find.text('Uploaded covers'), findsNothing);
      expect(find.text('Artist photos'), findsOneWidget);
      expect(
        find.text('Waiting for the first run on the desktop.'),
        findsOneWidget,
      );
      // No Pause, Resume or Check again here.
      expect(find.text('Check again'), findsNothing);
      expect(find.text('Review'), findsNothing);
    });

    testWidgets('after it, with every artist covered: the count alone', (
      tester,
    ) async {
      await pump(
        tester,
        const ConnectionScreen(),
        withFiles: {
          record: text(
            '{\n  "version": 1,\n  "backfilled": "2026-11-15",\n'
            '  "artists": {}\n}\n',
          ),
          'artists/alice-in-chains.jpg': text('photo'),
          // A file for an artist no longer in the library is not counted.
          'artists/gone.jpg': text('photo'),
        },
      );
      expect(find.text('1 of 1 artist has one'), findsOneWidget);
      // Nobody to review, and the review of uploaded covers leaves the
      // artists' folder alone.
      expect(find.text('Review'), findsNothing);
      expect(find.text('Uploaded covers'), findsNothing);
    });

    final ghost = dirt.copyWith(
      id: 'music/impera-ghost',
      title: 'Impera',
      creator: 'Ghost',
    );
    final rats = dirt.copyWith(
      id: 'music/rats-ghost',
      title: 'Rats',
      creator: 'Ghost',
      kind: EntryKind.song,
    );
    final abba = dirt.copyWith(
      id: 'music/arrival-abba',
      title: 'Arrival',
      creator: 'ABBA',
    );
    final various = dirt.copyWith(
      id: 'music/now-42',
      title: 'Now 42',
      creator: 'Various Artists',
    );
    const backfilled =
        '{\n  "version": 1,\n  "backfilled": "2026-11-15",\n'
        '  "artists": {}\n}\n';

    test('the row: waiting, then the count with those without, then '
        'all', () async {
      Future<({String text, bool review})?> row(
        int have,
        int total, {
        bool ready = true,
        bool local = false,
      }) async {
        final store = fakeCoverStore(
          files: {
            if (ready) record: text(backfilled),
            for (var i = 0; i < have; i++) 'artists/artist-$i.jpg': text('p'),
          },
        );
        await store.refresh();
        return artistPhotosSummary(
          Library(
            entries: [
              for (var i = 0; i < total; i++)
                dirt.copyWith(id: 'music/a-$i', creator: 'Artist $i'),
            ],
          ),
          store,
          local: local,
        );
      }

      expect(await row(0, 0), isNull);
      expect(await row(2, 3, ready: false), (
        text: 'Waiting for the first run on the desktop.',
        review: false,
      ));
      expect(await row(2, 3), (
        text: '2 of 3 artists have one · 1 without',
        review: true,
      ));
      expect(await row(0, 1), (
        text: '0 of 1 artist has one · 1 without',
        review: true,
      ));
      expect(await row(3, 3), (text: 'All 3 artists have one', review: false));
      // Kept on this phone there is no desktop run to wait for.
      expect(await row(1, 3, ready: false, local: true), (
        text: '1 of 3 artists have one · 2 without',
        review: true,
      ));
    });

    testWidgets('with artists without one: the count, those without and '
        'Review, which opens Without a photo', (tester) async {
      await pump(
        tester,
        const ConnectionScreen(),
        withFiles: {
          record: text(backfilled),
          'artists/alice-in-chains.jpg': text('photo'),
        },
        withEntries: [dirt, ghost, rats, abba, various],
      );
      expect(find.text('1 of 3 artists have one · 2 without'), findsOneWidget);
      await tester.ensureVisible(find.text('Review'));
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistsWithoutPhotoScreen), findsOneWidget);
      expect(find.text('Without a photo'), findsOneWidget);
    });

    testWidgets('Without a photo lists every artist with no file, A to Z, '
        'with what is saved by them; a tap opens Pick a photo, and an '
        'artist who gets a photo leaves the list', (tester) async {
      final container = await pump(
        tester,
        const ArtistsWithoutPhotoScreen(),
        withFiles: {
          record: text(backfilled),
          'artists/alice-in-chains.jpg': text('photo'),
        },
        withEntries: [dirt, ghost, rats, abba, various],
      );
      expect(
        find.text(
          '2 artists. No photo was found for these; pick or upload one.',
        ),
        findsOneWidget,
      );
      // Not the artist with a file, nor Various Artists.
      expect(find.text('Alice in Chains'), findsNothing);
      expect(find.text('Various Artists'), findsNothing);
      expect(
        tester.getTopLeft(find.text('ABBA')).dy,
        lessThan(tester.getTopLeft(find.text('Ghost')).dy),
      );
      expect(find.text('1 album'), findsOneWidget);
      expect(find.text('1 album, 1 song'), findsOneWidget);
      expect(find.text('Add photo'), findsNWidgets(2));
      expect(
        find.bySemanticsLabel('Ghost, 1 album, 1 song, add a photo'),
        findsOneWidget,
      );

      await tester.tap(find.text('Ghost'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a photo'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.runAsync(
        () => container
            .read(coverStoreProvider)
            .putArtistPhoto(
              'Ghost',
              text('picked'),
              picked: true,
              summary: 'Set the photo of Ghost',
            ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ghost'), findsNothing);
      expect(find.text('ABBA'), findsOneWidget);
      expect(
        find.text(
          '1 artist. No photo was found for this one; pick or upload one.',
        ),
        findsOneWidget,
      );
      expect(artistsWithoutPhotoIntro(0), 'Every artist has a photo.');
    });

    test(
      'the artists\' folder and the record are no uploaded covers',
      () async {
        final store = fakeCoverStore(
          files: {
            ...files,
            record: text('{}'),
            'artists/alice-in-chains.jpg': text('photo'),
          },
        );
        await store.refresh();
        final library = Library(entries: entries);
        expect(
          store.files.map((f) => f.path),
          isNot(contains(startsWith('artists/'))),
        );
        expect(
          CoverReviewRow.of(store.files, library).map((r) => r.file.path),
          isNot(contains(startsWith('artists/'))),
        );
        expect(
          uploadedCoversSummary(store.files, library),
          startsWith('4 covers · 2 unused'),
        );
        expect(artistPhotosSummary(library, store, local: true), (
          text: '1 of 1 artist has one',
          review: false,
        ));
      },
    );
  });

  testWidgets('the review preselects Delete for unused, Keep for the rest', (
    tester,
  ) async {
    final container = await pump(tester, const YourCoversScreen());
    expect(find.text('Your covers'), findsOneWidget);
    expect(
      find.text(
        'Covers you uploaded. Deleting one removes the file from GitHub; a '
        'title that used it goes back to its online cover.',
      ),
      findsOneWidget,
    );
    expect(find.text('UNUSED'), findsOneWidget);
    expect(find.text('IN USE'), findsOneWidget);
    expect(
      find.text('No title uses these, and their names match no title.'),
      findsOneWidget,
    );
    expect(find.text(oldPoster), findsOneWidget);
    expect(find.text('Doesn’t match any title'), findsOneWidget);
    expect(find.text('Its title was deleted'), findsOneWidget);
    expect(find.text('Movie · 1999 · steelbook'), findsOneWidget);
    // A title's cover is never named by its path.
    expect(find.text(steelbook), findsNothing);
    // The button counts what will go.
    expect(find.text('Delete 2 files'), findsOneWidget);

    await tester.tap(find.text('Delete 2 files'));
    await tester.pumpAndSettle();
    expect(store.files.map((f) => f.path), [steelbook, dirtCover]);
    expect(store.pending.map((c) => c.summary), [
      'Delete the cover $gatto',
      'Delete the cover $oldPoster',
    ]);
    // The library is as it was.
    expect(
      repo(container).current!.entryById(mummy.id)!.coverFrom,
      'repo:$steelbook',
    );
    expect(find.byType(YourCoversScreen), findsNothing);
  });

  testWidgets('each row can be turned; a cover in use sends its title back', (
    tester,
  ) async {
    final container = await pump(tester, const YourCoversScreen());
    Finder choice(String row, String label) => find.descendant(
      of: find.bySemanticsLabel(row),
      matching: find.text(label),
    );
    // Keep the two unused ones: nothing to delete.
    await tester.tap(choice(oldPoster, 'Keep'));
    await tester.tap(choice(gatto, 'Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to delete'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Nothing to delete'),
          )
          .onPressed,
      isNull,
    );
    // Delete The Mummy's cover.
    await tester.tap(choice('The Mummy', 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 file'), findsOneWidget);
    await tester.tap(find.text('Delete 1 file'));
    await tester.pumpAndSettle();
    expect(store.files.map((f) => f.path), [gatto, oldPoster, dirtCover]);
    expect(store.pending.single.summary, 'Delete a cover of The Mummy');
    // Back to its online cover, or to none.
    final saved = repo(container).current!.entryById(mummy.id)!;
    expect(saved.coverFrom, isNull);
    expect(saved.coverKeepMine, isNull);
  });

  testWidgets('Cancel deletes nothing', (tester) async {
    await pump(tester, const YourCoversScreen());
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.files, hasLength(4));
    expect(store.pendingCount, 0);
  });
}
