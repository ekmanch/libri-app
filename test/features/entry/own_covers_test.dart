import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_covers.dart';
import 'package:library_app/features/entry/delete_entry_dialog.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/widgets/chips.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);

const uploaded = 'movies/the-mummy-1999.a3f9c2e.jpg';
const steelbook = 'movies/the-mummy-1999.steelbook.jpg';

class _Deleter extends ConsumerWidget {
  const _Deleter(this.entry);

  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      onPressed: () =>
          confirmDeleteEntry(context, ref, entry: entry, plans: const []),
      child: const Text('Open'),
    ),
  );
}

void main() {
  late CoverStore store;

  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
    required List<Entry> entries,
    Map<String, Uint8List> files = const {},
  }) async {
    store = fakeCoverStore(files: files);
    await store.refresh();
    return pumpApp(
      tester,
      home,
      library: Library(entries: entries),
      overrides: [
        coverStoreProvider.overrideWithValue(store),
        coverSourcesProvider.overrideWithValue(FakeCoverSources()),
        coverPicturesProvider.overrideWithValue(FakeCoverPictures()),
      ],
    );
  }

  group('Delete confirmation: with a cover file', () {
    final yours = mummy.copyWith(coverFrom: 'repo:$uploaded');

    testWidgets('the box is ticked, and the file goes after the entry', (
      tester,
    ) async {
      final container = await pump(
        tester,
        _Deleter(yours),
        entries: [yours, dirt],
        files: {uploaded: bytes('a')},
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Also delete its cover file'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Also delete its cover file')),
        isSemantics(isChecked: true, hasCheckedState: true),
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.entryById(mummy.id), isNull);
      expect(store.files, isEmpty);
      expect(store.pending.single.summary, 'Delete a cover of The Mummy');
    });

    testWidgets('unticked, the files stay and are unused from then on', (
      tester,
    ) async {
      final container = await pump(
        tester,
        _Deleter(yours),
        entries: [yours, dirt],
        files: {uploaded: bytes('a'), steelbook: bytes('b')},
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Also delete its 2 cover files'), findsOneWidget);
      await tester.tap(find.text('Also delete its 2 cover files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.entryById(mummy.id), isNull);
      expect(store.files, hasLength(2));
      expect(store.pendingCount, 0);
    });

    testWidgets('an entry without cover files of its own has no box', (
      tester,
    ) async {
      // The file is also Dirt's cover: not the Mummy's own to delete.
      final shared = dirt.copyWith(coverFrom: 'repo:$uploaded');
      await pump(
        tester,
        _Deleter(yours),
        entries: [yours, shared],
        files: {uploaded: bytes('a')},
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete The Mummy?'), findsOneWidget);
      expect(find.textContaining('Also delete'), findsNothing);
    });
  });

  group('the form', () {
    testWidgets('says "Your cover", and saving keeps cover_keep_mine', (
      tester,
    ) async {
      final yours = mummy.copyWith(
        coverFrom: 'repo:$uploaded',
        coverKeepMine: true,
      );
      final container = await pump(
        tester,
        EntryFormScreen.edit(yours),
        entries: [yours, dirt],
        files: {uploaded: bytes('a')},
      );
      expect(find.text('Your cover'), findsOneWidget);
      // The lookup has a cover for it.
      expect(find.text('Use the match’s cover'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Title',
        ),
        'The Mummy (1999)',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById(mummy.id)!;
      expect(saved.title, 'The Mummy (1999)');
      expect(saved.coverFrom, 'repo:$uploaded');
      expect(saved.coverKeepMine, isTrue);
    });

    testWidgets('"Use the match’s cover" asks about your file', (tester) async {
      final yours = mummy.copyWith(coverFrom: 'repo:$uploaded');
      await pump(
        tester,
        EntryFormScreen.edit(yours),
        entries: [yours, dirt],
        files: {uploaded: bytes('a')},
      );
      await tester.tap(find.text('Use the match’s cover'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your file too?'), findsOneWidget);
      await tester.tap(find.text('Keep my file'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('From the match · tap to change'), findsOneWidget);
      expect(store.files, hasLength(1));
    });

    testWidgets('a type change keeps your cover and moves its files', (
      tester,
    ) async {
      final yours = mummy.copyWith(coverFrom: 'repo:$uploaded');
      final container = await pump(
        tester,
        EntryFormScreen.edit(yours),
        entries: [yours, dirt],
        files: {
          uploaded: bytes('a'),
          steelbook: bytes('b'),
          'movies/old-poster.png': bytes('c'),
        },
      );
      await tester.tap(find.widgetWithText(PillChip, 'Shows'));
      await tester.pumpAndSettle();
      expect(find.text('Your cover'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById(mummy.id)!;
      expect(saved.coverFrom, 'repo:shows/the-mummy-1999.a3f9c2e.jpg');
      expect(store.files.map((f) => f.path), [
        // Not the title's: it stays.
        'movies/old-poster.png',
        'shows/the-mummy-1999.a3f9c2e.jpg',
        'shows/the-mummy-1999.steelbook.jpg',
      ]);
      expect(store.pending.map((c) => c.summary).toSet(), {
        'Move a cover of The Mummy to shows',
      });
    });

    testWidgets('a title with no cover says so, and the picker opens on it', (
      tester,
    ) async {
      await pump(
        tester,
        const EntryFormScreen.create(),
        entries: [mummy, dirt],
      );
      expect(find.text('No cover yet · tap to add'), findsNothing);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Title',
        ),
        'Gatto',
      );
      await tester.pumpAndSettle();
      expect(find.text('No cover yet · tap to add'), findsOneWidget);
      // No match is needed: a title is enough.
      await tester.tap(find.bySemanticsLabel('Cover. Tap to change'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a cover'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
      expect(
        find.text(
          'No online cover found for this title. Upload your own above.',
        ),
        findsOneWidget,
      );
    });
  });
}
