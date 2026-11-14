import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_files.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_covers.dart';
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

  testWidgets('and not without any', (tester) async {
    await pump(tester, const ConnectionScreen(), withFiles: const {});
    expect(find.text('Uploaded covers'), findsNothing);
    expect(find.text('YOUR COVERS'), findsNothing);
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
