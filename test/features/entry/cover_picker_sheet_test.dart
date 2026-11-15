import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_files.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/github/git_blob.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/lookup_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_covers.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/widgets/cover_choice.dart';
import 'package:library_app/features/entry/cover_picker_sheet.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);

const mummyOnline = 'fake://cover/poster/tmdb:movie:564';
const steelbook = 'movies/the-mummy-1999.steelbook.jpg';
const uploaded = 'movies/the-mummy-1999.a3f9c2e.jpg';

void main() {
  late CoverStore store;
  late FakeCoverRemote remote;
  late FakeCoverSources sources;
  late FakeCoverPictures pictures;
  final picks = <CoverPick>[];

  setUp(() {
    picks.clear();
    sources = FakeCoverSources(photo: bytes('a photo'), file: bytes('a file'));
    pictures = FakeCoverPictures();
  });

  /// Opens Pick a cover on [subject] over a library of [entries], with
  /// [files] in the library repo.
  Future<ProviderContainer> open(
    WidgetTester tester,
    CoverSubject subject, {
    Map<String, Uint8List> files = const {},
    List<Entry>? entries,
    String? ownCoverUrl = mummyOnline,
    bool askForMatchCover = false,
  }) async {
    store = fakeCoverStore(files: files);
    remote = store.remote! as FakeCoverRemote;
    await store.refresh();
    final container = await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCoverPicker(
              context,
              subject: subject,
              ownCoverUrl: ownCoverUrl,
              askForMatchCover: askForMatchCover,
              onPicked: picks.add,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      library: Library(entries: entries ?? [mummy, dirt]),
      overrides: [
        coverStoreProvider.overrideWithValue(store),
        coverSourcesProvider.overrideWithValue(sources),
        coverPicturesProvider.overrideWithValue(pictures),
      ],
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  CoverSubject mummySubject({String? coverFrom, bool keepMine = false}) =>
      CoverSubject(
        id: mummy.id,
        type: MediaType.movies,
        title: 'The Mummy',
        year: 1999,
        source: 'tmdb:movie:564',
        coverFrom: coverFrom,
        keepMine: keepMine,
      );

  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Finder tile(String label) => find.bySemanticsLabel(label);

  /// The online covers sit under the fold with a row of your own above.
  Future<void> tapMatchCover(WidgetTester tester) async {
    final match = tile('The Mummy, 1999, The match’s cover');
    await tester.ensureVisible(match);
    await tester.pumpAndSettle();
    await tester.tap(match);
    await tester.pumpAndSettle();
  }

  testWidgets('two sections: your covers with Upload first, then online', (
    tester,
  ) async {
    await open(
      tester,
      mummySubject(),
      files: {
        steelbook: bytes('steelbook'),
        uploaded: bytes('upload'),
        // Another title's, and a file that is no image: not offered.
        'movies/the-mummy-1999-2.jpg': bytes('other'),
        'movies/the-mummy-1999.txt': bytes('notes'),
      },
    );
    expect(find.text('Pick a cover'), findsOneWidget);
    expect(
      find.text('The Mummy · 1999. Only the cover changes.'),
      findsOneWidget,
    );
    expect(find.text('YOUR COVERS'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    // A file committed by hand is captioned with its label; an upload is
    // "Your cover". Both are marked Yours, and neither is applied on its
    // own.
    expect(find.text('Yours'), findsNWidgets(2));
    expect(tile('steelbook, Yours'), findsOneWidget);
    expect(tile('Your cover, Yours'), findsOneWidget);
    // Online: the match's own first, then the four other matches.
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('The match’s cover'), findsOneWidget);
    // No file names, folders or source names anywhere.
    expect(find.textContaining('.jpg'), findsNothing);
    expect(find.textContaining('movies/'), findsNothing);
    expect(picks, isEmpty);
  });

  testWidgets('picking one of your covers over a known online one keeps it', (
    tester,
  ) async {
    await open(tester, mummySubject(), files: {steelbook: bytes('steelbook')});
    await tester.tap(tile('steelbook, Yours'));
    await tester.pumpAndSettle();
    // The lookup has a cover: choosing yours is a choice made, so no
    // online cover is pointed out later.
    expect(picks.single.coverFrom, 'repo:$steelbook');
    expect(picks.single.keepMine, isTrue);
    expect(find.text('New'), findsNothing);
    expect(find.text('Keep mine'), findsNothing);
  });

  testWidgets('an upload is read, stored, picked and shown at once', (
    tester,
  ) async {
    sources.gate = Completer<void>();
    await open(tester, mummySubject());
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Upload a cover'), findsOneWidget);
    expect(find.text('Photo library'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    // The clipboard holds no image.
    expect(find.text('Paste image'), findsNothing);
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();
    expect(find.text('Reading…'), findsOneWidget);
    expect(find.text('Upload'), findsNothing);
    sources.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Reading…'), findsNothing);

    final name = coverUploadName(
      'the-mummy-1999',
      gitBlobSha(bytes('a photo')),
    );
    expect(store.files.single.path, 'movies/$name');
    expect(store.pending.single.summary, 'Add a cover for The Mummy');
    expect(picks.single.coverFrom, 'repo:movies/$name');
    expect(picks.single.url, 'repo:movies/$name');
    expect(find.text('Just uploaded'), findsOneWidget);
    expect(tile('Your cover, Yours, Just uploaded'), findsOneWidget);
    // 2:3: no Fit your cover.
    expect(pictures.fitted, isEmpty);
    // Nothing is sent from the sheet: the sync does that.
    expect(remote.writes, isEmpty);
  });

  testWidgets('Paste image is listed while the clipboard holds an image', (
    tester,
  ) async {
    sources.clipboard = bytes('copied');
    await open(tester, mummySubject());
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste image'));
    await tester.pumpAndSettle();
    expect(store.files.single.sha, gitBlobSha(bytes('copied')));
  });

  testWidgets('a file that is not an image leaves one red line', (
    tester,
  ) async {
    pictures.notAnImage = true;
    await open(tester, mummySubject());
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('That file isn’t an image.'), findsOneWidget);
    expect(store.files, isEmpty);
    expect(picks, isEmpty);
    // The next try clears it.
    pictures.notAnImage = false;
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('That file isn’t an image.'), findsNothing);
    expect(store.files, hasLength(1));
  });

  testWidgets('closing the picker without a file changes nothing', (
    tester,
  ) async {
    sources.photo = null;
    await open(tester, mummySubject());
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('That file isn’t an image.'), findsNothing);
    expect(store.files, isEmpty);
  });

  group('Fit your cover', () {
    testWidgets('opens only for an image clearly off 2:3, and crops', (
      tester,
    ) async {
      pictures.size = (1920, 1080);
      await open(tester, mummySubject());
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(find.text('Fit your cover'), findsOneWidget);
      expect(
        find.text('1920 × 1080. It isn’t 2:3, so part of it is cut.'),
        findsOneWidget,
      );
      expect(
        find.text('Drag sideways to choose which part is kept.'),
        findsOneWidget,
      );
      expect(find.text('Saved at 720 × 1080.'), findsOneWidget);
      // Crop only.
      expect(find.textContaining('Whole image'), findsNothing);

      // Dragging to the right end moves the frame there.
      final preview = find.bySemanticsLabel(RegExp('^The image'));
      await tester.dragFrom(tester.getCenter(preview), const Offset(400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this cover'));
      await tester.pumpAndSettle();
      expect(pictures.fitted, [1.0]);
      expect(store.files, hasLength(1));
      expect(isRepoCover(picks.single.coverFrom), isTrue);
    });

    testWidgets('a tall image is dragged up or down; Back adds nothing', (
      tester,
    ) async {
      pictures.size = (1080, 2400);
      await open(tester, mummySubject());
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(
        find.text('1080 × 2400. It isn’t 2:3, so part of it is cut.'),
        findsOneWidget,
      );
      expect(
        find.text('Drag up or down to choose which part is kept.'),
        findsOneWidget,
      );
      expect(find.text('Saved at 1000 × 1500.'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a cover'), findsOneWidget);
      expect(store.files, isEmpty);
      expect(picks, isEmpty);
      expect(pictures.fitted, isEmpty);
    });

    testWidgets('dragging a tall image up moves the frame, not the sheet', (
      tester,
    ) async {
      pictures.size = (1080, 2400);
      await open(tester, mummySubject());
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      final preview = find.bySemanticsLabel(RegExp('^The image'));
      await tester.dragFrom(tester.getCenter(preview), const Offset(0, 300));
      await tester.pumpAndSettle();
      // Still open: the drag down did not pull the sheet away.
      expect(find.text('Fit your cover'), findsOneWidget);
      // (Under the fold in the test font, whose lines run long.)
      await tester.ensureVisible(find.text('Use this cover'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this cover'));
      await tester.pumpAndSettle();
      expect(pictures.fitted, [1.0]);
    });

    testWidgets('music is fitted to 1:1', (tester) async {
      pictures.size = (1000, 1500);
      await open(
        tester,
        CoverSubject(id: dirt.id, type: MediaType.music, title: 'Dirt'),
        ownCoverUrl: null,
      );
      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(
        find.text('1000 × 1500. It isn’t 1:1, so part of it is cut.'),
        findsOneWidget,
      );
      expect(find.text('Saved at 1000 × 1000.'), findsOneWidget);
    });
  });

  testWidgets('long-press one of your covers: Delete file falls back', (
    tester,
  ) async {
    final container = await open(
      tester,
      mummySubject(coverFrom: 'repo:$uploaded', keepMine: true),
      files: {uploaded: bytes('upload')},
      entries: [
        mummy.copyWith(coverFrom: 'repo:$uploaded', coverKeepMine: true),
        dirt,
      ],
    );
    await tester.longPress(tile('Your cover, Yours'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Used as the cover of The Mummy. Deleting removes the file from '
        'GitHub.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete file'));
    await tester.pumpAndSettle();
    expect(store.files, isEmpty);
    expect(store.pending.single.summary, 'Delete a cover of The Mummy');
    // The title goes back to the match's cover, in the library too: it
    // never names a file that is gone.
    expect(picks.single.coverFrom, isNull);
    final saved = repo(container).current!.entryById(mummy.id)!;
    expect(saved.coverFrom, isNull);
    expect(saved.coverKeepMine, isNull);
    expect(find.text('Yours'), findsNothing);
  });

  group('an online cover that turned up later', () {
    testWidgets('has a New badge and Keep mine, which is remembered', (
      tester,
    ) async {
      await open(
        tester,
        mummySubject(coverFrom: 'repo:$uploaded'),
        files: {uploaded: bytes('upload')},
      );
      expect(find.text('New'), findsOneWidget);
      expect(
        find.text(
          'An online cover is available now. You’ve been using your own.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();
      expect(picks.single, (
        coverFrom: 'repo:$uploaded',
        keepMine: true,
        url: 'repo:$uploaded',
      ));
      expect(find.text('New'), findsNothing);
      expect(find.text('Keep mine'), findsNothing);
    });

    testWidgets('is not pointed out once Keep mine is set', (tester) async {
      await open(
        tester,
        mummySubject(coverFrom: 'repo:$uploaded', keepMine: true),
        files: {uploaded: bytes('upload')},
      );
      expect(find.text('New'), findsNothing);
      expect(find.text('Keep mine'), findsNothing);
    });
  });

  group('picking an online cover while yours is in use', () {
    Future<ProviderContainer> openOnYours(WidgetTester tester) => open(
      tester,
      mummySubject(coverFrom: 'repo:$uploaded', keepMine: true),
      files: {uploaded: bytes('upload')},
      entries: [
        mummy.copyWith(coverFrom: 'repo:$uploaded', coverKeepMine: true),
        dirt,
      ],
    );

    testWidgets('Delete my file: the cover changes and the file goes', (
      tester,
    ) async {
      final container = await openOnYours(tester);
      await tapMatchCover(tester);
      expect(find.text('Delete your file too?'), findsOneWidget);
      expect(
        find.text(
          'The Mummy will use the online cover. Your own cover file is '
          'still in your library on GitHub.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete my file'));
      await tester.pumpAndSettle();
      expect(picks.single.coverFrom, isNull);
      expect(picks.single.keepMine, isFalse);
      expect(store.files, isEmpty);
      expect(repo(container).current!.entryById(mummy.id)!.coverFrom, isNull);
    });

    testWidgets('Keep my file: it stays under Your covers', (tester) async {
      await openOnYours(tester);
      await tapMatchCover(tester);
      await tester.tap(find.text('Keep my file'));
      await tester.pumpAndSettle();
      expect(picks.single.coverFrom, isNull);
      expect(store.files.single.path, uploaded);
      expect(find.text('Yours'), findsOneWidget);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      await openOnYours(tester);
      await tapMatchCover(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picks, isEmpty);
      expect(store.files, hasLength(1));
    });

    testWidgets('a file another title shows is never deleted', (tester) async {
      await open(
        tester,
        mummySubject(coverFrom: 'repo:$uploaded', keepMine: true),
        files: {uploaded: bytes('upload')},
        entries: [
          mummy,
          dirt.copyWith(coverFrom: 'repo:$uploaded'),
        ],
      );
      await tapMatchCover(tester);
      await tester.tap(find.text('Delete my file'));
      await tester.pumpAndSettle();
      expect(picks.single.coverFrom, isNull);
      expect(store.files, hasLength(1));
    });

    testWidgets("“Use the match’s cover” from the form asks at once", (
      tester,
    ) async {
      await open(
        tester,
        mummySubject(coverFrom: 'repo:$uploaded', keepMine: true),
        files: {uploaded: bytes('upload')},
        askForMatchCover: true,
      );
      expect(find.text('Delete your file too?'), findsOneWidget);
    });
  });

  testWidgets('a title with no online cover says so', (tester) async {
    await open(
      tester,
      const CoverSubject(
        id: 'movies/gatto-2027',
        type: MediaType.movies,
        title: 'Gatto',
        year: 2027,
      ),
      ownCoverUrl: null,
    );
    expect(
      find.text('No online cover found for this title. Upload your own above.'),
      findsOneWidget,
    );
    // An upload here is not kept for good: an online cover that turns up
    // later is pointed out.
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();
    expect(picks.single.keepMine, isFalse);
  });

  testWidgets("a song's picker works on its album, and saves at once", (
    tester,
  ) async {
    final rooster = Entry(
      id: 'music/rooster-alice-in-chains',
      type: MediaType.music,
      title: 'Rooster',
      creator: 'Alice in Chains',
      status: EntryStatus.done,
      added: DateTime(2026),
      kind: EntryKind.song,
      album: 'Dirt',
    );
    pictures.size = (1000, 1000);
    final container = await open(
      tester,
      CoverSubject.album(dirt, song: 'Rooster'),
      ownCoverUrl: null,
      entries: [mummy, dirt, rooster],
    );
    expect(
      find.text(
        'Rooster uses its album’s cover. Changing it here changes Dirt’s '
        'cover.',
      ),
      findsOneWidget,
    );
    expect(find.text('DIRT’S COVERS'), findsOneWidget);
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();
    // Named after the album, in the music folder, and saved on the album.
    final path = store.files.single.path;
    expect(path, startsWith('music/dirt-alice-in-chains.'));
    expect(
      repo(container).current!.entryById(dirt.id)!.coverFrom,
      'repo:$path',
    );
    expect(repo(container).current!.entryById(rooster.id)!.coverFrom, isNull);
  });

  group('more covers (Pick a cover: more covers found)', () {
    const link = 'None of these? Search for more covers';

    testWidgets('an album has the link under Online; it adds the second '
        'catalog\'s covers once and goes; a pick is that cover\'s id', (
      tester,
    ) async {
      final container = await open(
        tester,
        CoverSubject(
          id: dirt.id,
          type: MediaType.music,
          title: 'Dirt',
          creator: 'Alice in Chains',
          stored: true,
        ),
        ownCoverUrl: null,
      );
      final fake =
          container.read(lookupSourcesProvider).single as FakeLookupSource;
      expect(fake.calls.where((c) => c.startsWith('more-covers:')), isEmpty);
      final before = find.byType(CoverChoice).evaluate().length;
      await tester.ensureVisible(find.text(link));
      await tester.pumpAndSettle();
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      expect(find.text(link), findsNothing);
      expect(find.byType(CoverChoice).evaluate().length, before + 2);
      expect(fake.calls.where((c) => c.startsWith('more-covers:')), [
        'more-covers:Dirt',
      ]);
      expect(find.textContaining('Apple'), findsNothing);

      final added = tile('Dirt, 2011');
      await tester.ensureVisible(added);
      await tester.pumpAndSettle();
      await tester.tap(added);
      await tester.pumpAndSettle();
      expect(picks.last.coverFrom, 'itunes:album:1800000001');
    });

    testWidgets('other types have no such link', (tester) async {
      await open(tester, mummySubject());
      expect(find.text(link), findsNothing);
    });
  });
}
