import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/images/artwork_providers.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/book_format.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/entry/tag_picker_sheet.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/seasons.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/widgets/app_dialog.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/form_fields.dart';
import 'package:library_app/widgets/segmented_control.dart';

import '../../helpers/pump.dart';
import '../../helpers/pump_app.dart';

import 'package:library_app/data/models/series.dart';

void main() {
  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == label,
  );

  /// The "Series" or "Movie" segment of an anime's kind control.
  Finder animeKind(String label) => find.descendant(
    of: find.byType(SegmentedControl<EntryKind?>),
    matching: find.text(label),
  );
  final hintedField = field;

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls back up to [finder], for a field above the visible part.
  Future<void> scrollUpTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Opens the Released picker, types [year] into the year field and
  /// closes the sheet.
  Future<void> typeYear(WidgetTester tester, String year) async {
    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().year}'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, year);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
  }

  group('Book: year from the ebook edition', () {
    const hint = "Year from the ebook edition. Check if it's a reprint.";
    const ebook = LookupMatch(
      type: MediaType.books,
      title: 'Leave the Lights On',
      source: 'itunes:6756269989',
      released: Released(2026, 9, 29),
      releasedFromEbook: true,
    );

    testWidgets('shows while adding and goes once the picker has been open', (
      tester,
    ) async {
      await pumpApp(tester, const EntryFormScreen.create(match: ebook));
      expect(find.text(hint), findsOneWidget);

      // Opened and closed with nothing changed.
      await tester.tap(find.bySemanticsLabel(RegExp('Released, ')));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Released, Sep 29, 2026')),
        findsOneWidget,
      );
    });

    testWidgets('goes when the date is cleared', (tester) async {
      await pumpApp(tester, const EntryFormScreen.create(match: ebook));
      await tester.tap(find.bySemanticsLabel(RegExp('Released, ')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Released, Not set')),
        findsOneWidget,
      );
    });

    testWidgets('not for a year from Open Library', (tester) async {
      await pumpApp(
        tester,
        EntryFormScreen.create(match: ebook.copyWith(releasedFromEbook: false)),
      );
      expect(find.text(hint), findsNothing);
    });

    testWidgets('not once the type is no longer a book', (tester) async {
      await pumpApp(tester, const EntryFormScreen.create(match: ebook));
      await tester.tap(find.widgetWithText(PillChip, 'Movies'));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
    });

    testWidgets('never in Edit', (tester) async {
      await pumpApp(
        tester,
        EntryFormScreen.edit(
          loadFixture()
              .entryById('books/dracula-1897')!
              .copyWith(released: const Released(2026, 9, 29)),
        ),
      );
      expect(find.text(hint), findsNothing);
    });
  });

  testWidgets('Add needs a title; Released is picked on the wheels', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      const EntryFormScreen.create(type: MediaType.movies),
    );
    expect(find.text('New entry'), findsOneWidget);
    expect(find.text('Director'), findsOneWidget);
    final add = find.widgetWithText(FilledButton, 'Add');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);

    await tester.enterText(field('Title'), 'Carrie');
    await tester.pump();
    expect(tester.widget<FilledButton>(add).onPressed, isNotNull);

    expect(find.bySemanticsLabel(RegExp('Released, Not set')), findsOneWidget);
    await typeYear(tester, '1976');
    expect(find.text('1976'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Released, 1976')), findsOneWidget);
    await tester.enterText(field('Optional').first, 'Brian De Palma');
    await tester.pump();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final entry = repo(container).current!.entries.last;
    expect(entry.id, 'movies/carrie-1976');
    expect(entry.title, 'Carrie');
    expect(entry.creator, 'Brian De Palma');
    expect(entry.released, const Released(1976));
    expect(entry.status, EntryStatus.want);
    expect(entry.rating, isNull);
    final today = DateTime.now();
    expect(entry.added, DateTime(today.year, today.month, today.day));
  });

  group('Cover from another match', () {
    Future<ProviderContainer> openDracula(
      WidgetTester tester, {
      String? coverFrom,
    }) {
      final dracula = loadFixture()
          .entryById('books/dracula-1897')!
          .copyWith(source: 'openlibrary:OL45804W', coverFrom: coverFrom);
      return pumpApp(tester, EntryFormScreen.edit(dracula));
    }

    Future<void> pickPaperback(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Cover. Tap to change'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a cover'), findsOneWidget);
      expect(
        find.text('Other matches for “Dracula”. Only the cover changes.'),
        findsOneWidget,
      );
      expect(find.text('The match’s cover'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dracula, 2009 ·\u00a0Paperback'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
    }

    testWidgets('a pick changes only the cover', (tester) async {
      final container = await openDracula(tester);
      expect(find.text('From the match · tap to change'), findsOneWidget);
      await pickPaperback(tester);
      expect(find.text('From another match'), findsOneWidget);
      expect(find.text('Use the match’s cover'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById('books/dracula-1897')!;
      expect(saved.coverFrom, 'fake:dracula-3');
      expect(saved.source, 'openlibrary:OL45804W');
      expect(saved.title, 'Dracula');
      expect(saved.released, const Released(1897));
    });

    testWidgets("“Use the match’s cover” puts the default back", (
      tester,
    ) async {
      final container = await openDracula(tester, coverFrom: 'fake:dracula-3');
      expect(find.text('From another match'), findsOneWidget);
      await tester.tap(find.text('Use the match’s cover'));
      await tester.pumpAndSettle();
      expect(find.text('From the match · tap to change'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById('books/dracula-1897')!;
      expect(saved.coverFrom, isNull);
    });

    testWidgets('changing the type clears it, like the source', (tester) async {
      final container = await openDracula(tester, coverFrom: 'fake:dracula-3');
      await tester.tap(find.widgetWithText(PillChip, 'Movies'));
      await tester.pumpAndSettle();
      expect(find.text('From the match · tap to change'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById('books/dracula-1897')!;
      expect(saved.coverFrom, isNull);
      expect(saved.source, isNull);
    });
  });

  testWidgets('the type changes the creator label and the extra fields', (
    tester,
  ) async {
    await pumpApp(tester, const EntryFormScreen.create());
    await tester.tap(find.widgetWithText(PillChip, 'Books'));
    await tester.pumpAndSettle();
    expect(find.text('Author'), findsOneWidget);
    await scrollTo(tester, find.text('Pages'));
    expect(find.text('Formats'), findsOneWidget);
    expect(find.text('Audiobook'), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);

    await scrollUpTo(tester, find.widgetWithText(PillChip, 'Games'));
    await tester.tap(find.widgetWithText(PillChip, 'Games'));
    await tester.pumpAndSettle();
    expect(find.text('Studio'), findsOneWidget);
    await scrollTo(tester, find.text('Platforms'));
    expect(find.text('Platforms'), findsOneWidget);
    expect(find.text('Formats'), findsNothing);
    expect(find.text('Pages'), findsNothing);

    await scrollUpTo(tester, find.widgetWithText(PillChip, 'Music'));
    await tester.tap(find.widgetWithText(PillChip, 'Music'));
    await tester.pumpAndSettle();
    expect(find.text('Artist'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StatusSegmentedControl),
        matching: find.text('DNF'),
      ),
      findsNothing,
    );
  });

  testWidgets('music gets an Album / Song switch', (tester) async {
    await pumpApp(tester, const EntryFormScreen.create(type: MediaType.music));
    expect(find.text('Album or song'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget); // The segment only.
    Finder inStatus(String label) => find.descendant(
      of: find.byType(StatusSegmentedControl),
      matching: find.text(label),
    );
    expect(inStatus('In progress'), findsNothing);
    await tester.tap(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('Album'), findsNWidgets(2)); // Segment and field label.
    expect(inStatus('In progress'), findsNothing);
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    expect(find.text('Album or song'), findsNothing);
  });

  testWidgets('a lookup match prefills the form and keeps its description', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      EntryFormScreen.create(
        match: FakeLookupSource.catalogSearch('hounds').single,
      ),
    );
    expect(find.widgetWithText(TextField, 'Hounds of Love'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Kate Bush'), findsOneWidget);
    expect(find.text('1985'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final entry = repo(container).current!.entries.last;
    expect(entry.id, 'music/hounds-of-love-kate-bush');
    expect(entry.kind, EntryKind.album);
    expect(entry.description, "Kate Bush's fifth studio album.");
  });

  testWidgets('a match\'s source is saved with the entry', (tester) async {
    final container = await pumpApp(
      tester,
      EntryFormScreen.create(
        match: FakeLookupSource.catalogSearch('perfect blue').single,
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(repo(container).current!.entries.last.source, 'anilist:437');
  });

  testWidgets('changing the type drops the match\'s source', (tester) async {
    final container = await pumpApp(
      tester,
      EntryFormScreen.create(
        match: FakeLookupSource.catalogSearch('perfect blue').single,
      ),
    );
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final saved = repo(container).current!.entries.last;
    expect(saved.type, MediaType.movies);
    expect(saved.source, isNull);
  });

  group('Look up again', () {
    /// Dracula without its details, under a title the fake catalog knows.
    Entry bare() => loadFixture()
        .entryById('books/dracula-1897')!
        .copyWith(
          title: 'Carrie',
          creator: null,
          released: null,
          description: '',
          tags: [],
          note: 'Keep me',
          pages: null,
        );

    testWidgets('a pick fills only what is empty and sets the source', (
      tester,
    ) async {
      final container = await pumpApp(tester, EntryFormScreen.edit(bare()));
      expect(find.text('Look up again'), findsOneWidget);
      expect(find.textContaining('Details fetched online'), findsNothing);

      await tester.tap(find.text('Look up again'));
      await tester.pumpAndSettle();
      // The picker starts on the entry's type and title, with no footer.
      expect(find.text('Look up again'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Carrie'), findsOneWidget);
      expect(find.text('Fill in the details myself'), findsNothing);
      await tester.pump(NewEntryScreen.debounce);
      await tester.pumpAndSettle();
      expect(find.text('BOOK · 1974'), findsOneWidget);
      expect(find.text('MOVIE · 1976'), findsNothing);
      await tester.tap(find.text('BOOK · 1974'));
      await tester.pumpAndSettle();

      expect(find.text('Edit entry'), findsOneWidget);
      expect(find.text('Look up again'), findsNothing);
      expect(find.textContaining('Details fetched online'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Stephen King'), findsOneWidget);
      expect(find.text('1974'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById('books/dracula-1897')!;
      expect(saved.source, 'openlibrary:OL81613W');
      expect(saved.creator, 'Stephen King');
      expect(saved.released, const Released(1974));
      expect(saved.description, isNotEmpty);
      expect(saved.note, 'Keep me');
      expect(saved.status, EntryStatus.done);
      expect(saved.tags, contains('horror'));
      expect(saved.pages, 199);
    });

    testWidgets('a pick replaces the creator, year and description, keeps '
        'the title and note, and forgets the cover even when the pick is '
        'the source the entry had', (tester) async {
      // Already linked to the work the pick will be.
      final dracula = loadFixture()
          .entryById('books/dracula-1897')!
          .copyWith(title: 'Carrie', source: 'openlibrary:OL81613W');
      final container = await pumpApp(tester, EntryFormScreen.edit(dracula));
      final resolver = container.read(artworkResolverProvider);
      expect(await resolver.coverUrl(dracula), isNotNull);
      expect(resolver.cachedCoverUrl(dracula), isNotNull);
      await tester.tap(find.text('Look up again'));
      await tester.pumpAndSettle();
      await tester.pump(NewEntryScreen.debounce);
      await tester.pumpAndSettle();
      await tester.tap(find.text('BOOK · 1974'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Stephen King'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Bram Stoker'), findsNothing);
      expect(find.text('1974'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Carrie'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById('books/dracula-1897')!;
      expect(saved.title, 'Carrie');
      expect(saved.creator, 'Stephen King');
      expect(saved.released, const Released(1974));
      expect(saved.description, isNot(dracula.description));
      expect(saved.note, dracula.note);
      expect(saved.status, dracula.status);
      expect(saved.source, 'openlibrary:OL81613W');
      expect(saved.source, dracula.source);
      expect(resolver.cachedCoverUrl(saved), isNull);
    });

    testWidgets('back without a pick changes nothing', (tester) async {
      await pumpApp(tester, EntryFormScreen.edit(bare()));
      await tester.tap(find.text('Look up again'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Edit entry'), findsOneWidget);
      expect(find.text('Look up again'), findsOneWidget);
      expect(find.textContaining('Details fetched online'), findsNothing);
      expect(find.widgetWithText(TextField, 'Stephen King'), findsNothing);
    });

    testWidgets('the row is there for a new entry by hand', (tester) async {
      await pumpApp(
        tester,
        const EntryFormScreen.create(type: MediaType.games, title: 'Zelda'),
      );
      expect(find.text('Look up again'), findsOneWidget);
    });

    testWidgets('the row is not there while a match is applied', (
      tester,
    ) async {
      await pumpApp(
        tester,
        EntryFormScreen.create(
          match: FakeLookupSource.catalogSearch('akira').first,
        ),
      );
      expect(find.text('Look up again'), findsNothing);
    });
  });

  testWidgets('a song match gets the album field', (tester) async {
    final container = await pumpApp(
      tester,
      EntryFormScreen.create(
        match: FakeLookupSource.catalogSearch('running up').single,
      ),
    );
    expect(find.widgetWithText(SegmentedControl<EntryKind>, 'Album'), findsOne);
    await scrollTo(tester, find.widgetWithText(TextField, 'Hounds of Love'));
    expect(find.widgetWithText(FieldLabel, 'Album'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Hounds of Love'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final entry = repo(container).current!.entries.last;
    expect(entry.kind, EntryKind.song);
    expect(entry.album, 'Hounds of Love');
  });

  testWidgets('editing keeps the id and the fields the form does not show', (
    tester,
  ) async {
    final fixture = loadFixture();
    final dracula = fixture
        .entryById('books/dracula-1897')!
        .copyWith(source: 'openlibrary:OL45804W');
    final container = await pumpApp(tester, EntryFormScreen.edit(dracula));
    expect(find.text('Edit entry'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Dracula'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bram Stoker'), findsOneWidget);
    expect(find.text('1897'), findsOneWidget);
    // The test font's wide digits stack Author and Released, so the
    // rest of the form sits further down the lazy list.
    await scrollTo(tester, find.text('8 / 10'));
    expect(find.text('8 / 10'), findsOneWidget);
    await scrollTo(tester, find.text('#horror'));
    expect(find.text('#horror'), findsOneWidget);

    // Formats sit above the tags, past the Series fields: scroll back up.
    await tester.scrollUntilVisible(
      find.widgetWithText(PillChip, 'Audiobook'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillChip, 'Audiobook'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = repo(container).current!.entryById('books/dracula-1897')!;
    expect(saved.formats, [BookFormat.physical]);
    expect(saved.description, dracula.description);
    expect(saved.added, dracula.added);
    expect(saved.source, 'openlibrary:OL45804W');
    expect(
      repo(container).current!.entries.indexOf(saved),
      fixture.entries.indexWhere((e) => e.id == dracula.id),
    );
  });

  group('a book\'s page count', () {
    Finder pagesField() => find.descendant(
      of: find
          .ancestor(of: find.text('Pages'), matching: find.byType(Column))
          .first,
      matching: find.byType(TextField),
    );

    testWidgets('comes from the match and is saved', (tester) async {
      final container = await pumpApp(
        tester,
        EntryFormScreen.create(
          match: FakeLookupSource.catalogSearch(
            'dune',
            type: MediaType.books,
          ).single,
        ),
      );
      await scrollTo(tester, find.text('Pages'));
      expect(find.widgetWithText(TextField, '412'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.entries.last.pages, 412);
    });

    testWidgets('takes digits only; emptied, the count is dropped', (
      tester,
    ) async {
      final dracula = loadFixture().entryById('books/dracula-1897')!;
      expect(dracula.pages, 418);
      final container = await pumpApp(tester, EntryFormScreen.edit(dracula));
      await scrollTo(tester, find.text('Pages'));
      expect(find.widgetWithText(TextField, '418'), findsOneWidget);

      await tester.enterText(pagesField(), '4x2-0');
      await tester.pump();
      expect(find.widgetWithText(TextField, '420'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        repo(container).current!.entryById('books/dracula-1897')!.pages,
        420,
      );
    });

    testWidgets('an empty field saves no count', (tester) async {
      final dracula = loadFixture().entryById('books/dracula-1897')!;
      final container = await pumpApp(tester, EntryFormScreen.edit(dracula));
      await scrollTo(tester, find.text('Pages'));
      await tester.enterText(pagesField(), '');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        repo(container).current!.entryById('books/dracula-1897')!.pages,
        isNull,
      );
    });

    testWidgets('another type saves no count', (tester) async {
      final shining = loadFixture().entryById('books/the-shining-1977')!;
      final other = await pumpApp(tester, EntryFormScreen.edit(shining));
      await scrollTo(tester, find.widgetWithText(PillChip, 'Movies'));
      await tester.tap(find.widgetWithText(PillChip, 'Movies'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(other).current!.entryById(shining.id)!;
      expect(saved.type, MediaType.movies);
      expect(saved.pages, isNull);
    });
  });

  testWidgets('a show from a match gets its seasons with no status', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      EntryFormScreen.create(
        match: FakeLookupSource.catalogSearch('last of us')
            .firstWhere((m) => m.type == MediaType.shows),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final seasons = repo(container).current!.entries.last.seasons!;
    expect(seasons, const [
      Season(season: 1, released: Released(2023, 1, 15)),
      Season(season: 2, released: Released(2025, 4, 13)),
    ]);
  });

  testWidgets('editing a show keeps its seasons', (tester) async {
    final twinPeaks = loadFixture().entryById('shows/twin-peaks-1990')!;
    final container = await pumpApp(tester, EntryFormScreen.edit(twinPeaks));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = repo(container).current!.entryById(twinPeaks.id)!;
    expect(saved.seasons, twinPeaks.seasons);
    expect(saved.seasons, hasLength(3));
  });

  testWidgets('seasons can be removed, added and dated', (tester) async {
    final twinPeaks = loadFixture().entryById('shows/twin-peaks-1990')!;
    final container = await pumpApp(tester, EntryFormScreen.edit(twinPeaks));
    await scrollTo(tester, find.byTooltip('Remove Season 2'));
    expect(find.text('Sep 30, 1990'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Season 2'));
    await tester.pumpAndSettle();
    expect(find.text('Season 2'), findsNothing);

    await scrollTo(tester, find.text('Add season'));
    await tester.tap(find.text('Add season'));
    await tester.pumpAndSettle();
    expect(find.text('Season 4'), findsOneWidget);
    // The new season's date field; its status pill says Not set too.
    await tester.tap(find.text('Not set').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().year}'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '2027');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final seasons = repo(container).current!.entryById(twinPeaks.id)!.seasons!;
    expect([for (final s in seasons) s.season], [1, 3, 4]);
    expect(seasons[1], twinPeaks.seasons![2]);
    // Added and dated here: the user's, never removed by the daily check.
    expect(
      seasons[2],
      const Season(season: 4, released: Released(2027), manual: true),
    );
  });

  group('a show in the form', () {
    Finder inStatus(String label) => find.descendant(
      of: find.byType(StatusSegmentedControl),
      matching: find.text(label),
    );

    testWidgets('has no Released field; a new one starts with Season 1', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(type: MediaType.shows),
      );
      expect(find.text('Released'), findsNothing);
      await tester.enterText(field('Title'), 'Severance');
      await scrollTo(tester, inStatus('Done'));
      await tester.tap(inStatus('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      final show = repo(container).current!.entries.last;
      expect(show.released, isNull);
      expect(show.seasons, const [
        Season(season: 1, status: EntryStatus.done, manual: true),
      ]);
      expect(show.status, EntryStatus.done);
    });

    testWidgets('several seasons: the status is set by them', (tester) async {
      final severance = loadFixture().entryById('shows/severance-2022')!;
      final container = await pumpApp(tester, EntryFormScreen.edit(severance));
      await scrollTo(tester, find.byType(DerivedStatusField));
      expect(find.byType(StatusSegmentedControl), findsNothing);
      expect(
        find.bySemanticsLabel('Status, In progress, set by the seasons'),
        findsOneWidget,
      );
      // Season 2 to Done in its sheet: the show becomes Done. The seasons
      // sit above the status row.
      await scrollUpTo(
        tester,
        find.bySemanticsLabel(RegExp('^Season 2 status: ')),
      );
      await tester.tap(find.bySemanticsLabel(RegExp('^Season 2 status: ')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SeasonStatusSheet),
          matching: find.text('Done'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Status, Done, set by the seasons'),
        findsOneWidget,
      );
      // Nothing is saved before Save.
      expect(
        repo(container).current!.entryById(severance.id)!.status,
        EntryStatus.inProgress,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById(severance.id)!;
      expect(saved.status, EntryStatus.done);
      expect(saved.seasons![1].status, EntryStatus.done);
    });

    testWidgets('catch-up in the form marks the earlier seasons', (
      tester,
    ) async {
      final things = loadFixture().entryById('shows/stranger-things-2016')!;
      final container = await pumpApp(tester, EntryFormScreen.edit(things));
      final pill = find.bySemanticsLabel(RegExp('^Season 5 status: '));
      await scrollTo(tester, pill);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark seasons 1–4 Done'));
      await tester.pumpAndSettle();
      expect(find.text('Mark seasons 1–4 Done'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final seasons = repo(container).current!.entryById(things.id)!.seasons!;
      expect(
        [for (final s in seasons) s.status],
        [
          EntryStatus.done,
          EntryStatus.done,
          EntryStatus.done,
          EntryStatus.done,
          null,
        ],
      );
    });

    testWidgets('a pick from the lookup replaces seasons made by hand', (
      tester,
    ) async {
      final bear = loadFixture()
          .entryById('shows/the-bear-2022')!
          .copyWith(
            title: 'The Last of Us',
            status: EntryStatus.done,
            seasons: const [
              Season(season: 1, status: EntryStatus.done, manual: true),
            ],
          );
      final container = await pumpApp(tester, EntryFormScreen.edit(bear));
      await tester.tap(find.text('Look up again'));
      await tester.pumpAndSettle();
      await tester.pump(NewEntryScreen.debounce);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SHOW · 2023'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entryById(bear.id)!;
      expect(saved.seasons, const [
        Season(
          season: 1,
          released: Released(2023, 1, 15),
          status: EntryStatus.done,
        ),
        Season(
          season: 2,
          released: Released(2025, 4, 13),
          status: EntryStatus.done,
        ),
      ]);
    });
  });

  testWidgets('one season has no pill; a second season gives both one', (
    tester,
  ) async {
    final hillHouse = loadFixture().entryById(
      'shows/the-haunting-of-hill-house-2018',
    )!;
    await pumpApp(tester, EntryFormScreen.edit(hillHouse));
    await scrollTo(tester, find.text('Season 1'));
    Finder pill(int n) => find.bySemanticsLabel(RegExp('^Season $n status: '));
    expect(find.text('Season 1'), findsOneWidget);
    await scrollTo(tester, find.text('Add season'));
    expect(pill(1), findsNothing);
    await tester.tap(find.text('Add season'));
    await tester.pumpAndSettle();
    await scrollUpTo(tester, pill(1));
    expect(pill(1), findsOneWidget);
    expect(pill(2), findsOneWidget);
  });

  testWidgets('only a show has the Seasons field', (tester) async {
    await pumpApp(tester, const EntryFormScreen.create(type: MediaType.shows));
    await scrollTo(tester, find.text('Add season'));
    expect(find.text('Seasons'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(PillChip, 'Movies'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PillChip, 'Movies'));
    await tester.pumpAndSettle();
    expect(find.text('Add season'), findsNothing);
  });

  testWidgets('the rating field opens the picker', (tester) async {
    await pumpApp(tester, const EntryFormScreen.create());
    await scrollTo(tester, find.text('Not rated'));
    await tester.tap(find.text('Not rated'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('7 out of 10'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('7 / 10'), findsOneWidget);
  });

  group('from a lookup match', () {
    FixtureLibraryRepository repo(ProviderContainer c) =>
        c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

    testWidgets('shows the fetched banner, platform chips and suggestions', (
      tester,
    ) async {
      final match = FakeLookupSource.catalogSearch(
        'the last of us',
        type: MediaType.games,
      ).first;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      expect(
        find.text('Details fetched online. You can change anything.'),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Platforms'));
      expect(find.text('Platforms'), findsOneWidget);
      for (final p in match.platforms) {
        expect(find.widgetWithText(PillChip, p), findsOneWidget);
      }
      // Only the platforms the game came out on: none borrowed from other
      // games in the library.
      expect(find.widgetWithText(PillChip, 'Switch'), findsNothing);
      expect(find.bySemanticsLabel('Other platform'), findsOneWidget);
      // Existing tags are selected; the rest are suggestions marked new.
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.widgetWithText(TagChip, '#horror'), findsOneWidget);
      expect(find.widgetWithText(TagChip, '#adventure'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #post-apocalyptic'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #horror'), findsNothing);
      // The studio from the creator field is suggested too, as new.
      expect(find.bySemanticsLabel('Add #naughty-dog'), findsOneWidget);
      expect(find.text('new'), findsNWidgets(5));
    });

    testWidgets("the lookup's language ticks the library's tag, in Languages", (
      tester,
    ) async {
      // The Akira manga is in Japanese; the library has #japanese already.
      final manga = FakeLookupSource.catalogSearch(
        'akira',
        type: MediaType.books,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: manga));
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#japanese'), findsOneWidget);
    });

    testWidgets('a language the library has no tag for is offered as new, '
        'in Languages', (tester) async {
      final korean = FakeLookupSource.catalogSearch(
        'akira',
        type: MediaType.books,
      ).single.copyWith(language: 'ko');
      await pumpApp(tester, EntryFormScreen.create(match: korean));
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.bySemanticsLabel('Add #korean'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Add #korean'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PillChip>(
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.widgetWithText(PillChip, 'Languages'),
              ),
            )
            .selected,
        isTrue,
      );
      await tester.ensureVisible(find.text('Create tag'));
      await tester.tap(find.text('Create tag'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TagChip, '#korean'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #korean'), findsNothing);
    });

    testWidgets('an anime in Japanese, like nearly every anime, gets no '
        'language tag', (tester) async {
      final anime = FakeLookupSource.catalogSearch(
        'spirited away',
        type: MediaType.anime,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: anime));
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#japanese'), findsNothing);
      expect(find.bySemanticsLabel('Add #japanese'), findsNothing);
    });

    LookupMatch showMatch() => FakeLookupSource.catalogSearch(
      'the last of us',
      type: MediaType.shows,
    ).single;

    LookupMatch movieMatch() =>
        FakeLookupSource.catalogSearch('carrie', type: MediaType.movies).first;

    testWidgets("a show's network the library has no tag for suggests "
        'nothing', (tester) async {
      // HBO: the library has no #hbo, and a network is never offered as new.
      expect(showMatch().network, 'HBO');
      await pumpApp(tester, EntryFormScreen.create(match: showMatch()));
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#hbo'), findsNothing);
      expect(find.bySemanticsLabel('Add #hbo'), findsNothing);
    });

    testWidgets("a show's first network ticks the library's Streaming tag", (
      tester,
    ) async {
      await pumpApp(
        tester,
        EntryFormScreen.create(match: showMatch().copyWith(network: 'Netflix')),
      );
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#netflix'), findsOneWidget);
    });

    testWidgets('a movie no platform made gets no Streaming tag', (
      tester,
    ) async {
      expect(movieMatch().companies, isEmpty);
      await pumpApp(tester, EntryFormScreen.create(match: movieMatch()));
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#netflix'), findsNothing);
    });

    testWidgets("a platform original movie ticks the library's Streaming tag", (
      tester,
    ) async {
      await pumpApp(
        tester,
        EntryFormScreen.create(
          match: movieMatch().copyWith(companies: ['Netflix']),
        ),
      );
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#netflix'), findsOneWidget);
    });

    testWidgets('a platform original movie offers a platform the library has '
        'no tag for as new, in Streaming', (tester) async {
      await pumpApp(
        tester,
        EntryFormScreen.create(
          match: movieMatch().copyWith(companies: ['Disney+']),
        ),
      );
      await scrollTo(tester, find.text('Suggested · tap to add'));
      await tester.tap(find.bySemanticsLabel('Add #disney-plus'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PillChip>(
              find.descendant(
                of: find.byType(AppDialog),
                matching: find.widgetWithText(PillChip, 'Streaming'),
              ),
            )
            .selected,
        isTrue,
      );
    });

    testWidgets('a near miss counts as the existing tag', (tester) async {
      final match = FakeLookupSource.catalogSearch(
        'dune',
        type: MediaType.books,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.text('Tags'));
      // "sci-fi" from the lookup is the library's "scifi".
      expect(find.widgetWithText(TagChip, '#scifi'), findsOneWidget);
      expect(find.widgetWithText(TagChip, '#epic'), findsOneWidget);
      // Only the author is left to suggest.
      expect(find.bySemanticsLabel('Add #frank-herbert'), findsOneWidget);
      expect(find.text('new'), findsOneWidget);
    });

    testWidgets('an album match gets suggestions too', (tester) async {
      final match = FakeLookupSource.catalogSearch('hounds').single;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.widgetWithText(TagChip, '#pop'), findsOneWidget);
      expect(find.widgetWithText(TagChip, '#classic'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #art-pop'), findsOneWidget);
      expect(find.text('Platforms'), findsNothing);
    });

    testWidgets(
      'a new suggestion is confirmed with a category and saved as new',
      (tester) async {
        final match = FakeLookupSource.catalogSearch(
          'the last of us',
          type: MediaType.games,
        ).first;
        final container = await pumpApp(
          tester,
          EntryFormScreen.create(match: match),
        );
        // PC is the default platform in Settings, so it starts picked.
        await scrollTo(tester, find.widgetWithText(PillChip, 'PC'));
        expect(isSelected(tester, find.widgetWithText(PillChip, 'PC')), isTrue);
        await tester.tap(find.widgetWithText(PillChip, 'PlayStation 5'));
        await scrollTo(tester, find.bySemanticsLabel('Add #stealth'));
        await tester.tap(find.bySemanticsLabel('Add #stealth'));
        await tester.pumpAndSettle();
        expect(find.text('Create a new tag?'), findsOneWidget);
        expect(
          find.textContaining(
            'It will be added to your tag list under Game genres.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Create tag'));
        await tester.tap(find.text('Create tag'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TagChip, '#stealth'), findsOneWidget);
        expect(find.bySemanticsLabel('Add #stealth'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();
        final library = repo(container).current!;
        final entry = library.entries.last;
        expect(entry.platform, 'PlayStation 5, PC');
        expect(entry.tags, ['horror', 'adventure', 'stealth']);
        expect(library.tags[TagCategory.gameGenre], contains('stealth'));
        expect(library.allTags.contains('zombies'), isFalse);
      },
    );

    testWidgets('the default platform is picked only when the game is on it', (
      tester,
    ) async {
      // The Last of Us came out on PC; Uncharted did not.
      final onPc = FakeLookupSource.catalogSearch(
        'the last of us',
        type: MediaType.games,
      ).first;
      await pumpApp(tester, EntryFormScreen.create(match: onPc));
      await scrollTo(tester, find.widgetWithText(PillChip, 'PlayStation 5'));
      expect(isSelected(tester, find.widgetWithText(PillChip, 'PC')), isTrue);
      expect(
        isSelected(tester, find.widgetWithText(PillChip, 'PlayStation 5')),
        isFalse,
      );
    });

    testWidgets('no default platform means nothing is picked', (tester) async {
      final match = FakeLookupSource.catalogSearch(
        'the last of us',
        type: MediaType.games,
      ).first;
      final container = await pumpApp(
        tester,
        EntryFormScreen.create(match: match),
        settings: const AppSettings(defaultPlatform: null),
      );
      await scrollTo(tester, find.widgetWithText(PillChip, 'PC'));
      expect(isSelected(tester, find.widgetWithText(PillChip, 'PC')), isFalse);
      expect(
        (await container.read(libraryRepositoryProvider).loadSettings())
            .defaultPlatform,
        null,
      );
    });

    testWidgets('a removed match comes back as a suggestion', (tester) async {
      final match = FakeLookupSource.catalogSearch(
        'the last of us',
        type: MediaType.games,
      ).first;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.widgetWithText(TagChip, '#horror'));
      await tester.tap(find.widgetWithText(TagChip, '#horror'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PillChip, '#horror'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Add #horror'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Add #horror'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TagChip, '#horror'), findsOneWidget);
    });

    testWidgets(
      '"Other…" adds a typed platform; editing keeps the saved ones',
      (tester) async {
        final elden = loadFixture().entryById('games/elden-ring-2022')!;
        final container = await pumpApp(tester, EntryFormScreen.edit(elden));
        expect(
          find.text('Details fetched online. You can change anything.'),
          findsNothing,
        );
        await scrollTo(tester, find.bySemanticsLabel('Other platform'));
        final pc = find.widgetWithText(PillChip, 'PC');
        expect(tester.widget<PillChip>(pc).selected, isTrue);
        // Other games' platforms are not offered (only fetched ones).
        expect(find.widgetWithText(PillChip, 'PlayStation 5'), findsNothing);
        await tester.tap(find.bySemanticsLabel('Other platform'));
        await tester.pumpAndSettle();
        await tester.enterText(hintedField('Type a platform'), 'Steam Deck');
        await tester.tap(find.widgetWithText(OutlinedButton, 'Add'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<PillChip>(find.widgetWithText(PillChip, 'Steam Deck'))
              .selected,
          isTrue,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(
          repo(container).current!.entryById(elden.id)!.platform,
          'PC, Steam Deck',
        );
      },
    );
  });

  group('the creator field suggests its tag', () {
    testWidgets('an author typed by hand is offered once the field is left', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const EntryFormScreen.create(type: MediaType.books),
      );
      await tester.enterText(field('Title'), 'Hell House');
      await tester.enterText(field('Optional').first, 'Richard Matheson');
      await tester.pump();
      // Half-typed names are not tags: nothing while the field has focus.
      expect(find.bySemanticsLabel('Add #richard-matheson'), findsNothing);
      await tester.tap(field('Title'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.bySemanticsLabel('Add #richard-matheson'));
      expect(find.text('new'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Add #richard-matheson'));
      await tester.pumpAndSettle();
      expect(find.text('Create a new tag?'), findsOneWidget);
      expect(
        find.textContaining('It will be added to your tag list under Authors.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Create tag'));
      await tester.tap(find.text('Create tag'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TagChip, '#richard-matheson'), findsOneWidget);
    });

    testWidgets('a Pixar film suggests #pixar, not its director', (
      tester,
    ) async {
      final match = FakeLookupSource.catalogSearch(
        'soul',
        type: MediaType.movies,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.bySemanticsLabel('Add #pixar'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #pete-docter'), findsNothing);
    });

    testWidgets('a movie suggests its top three billed as new actor tags', (
      tester,
    ) async {
      final match = FakeLookupSource.catalogSearch(
        'soul',
        type: MediaType.movies,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.text('Suggested · tap to add'));
      for (final actor in ['jamie-foxx', 'tina-fey', 'graham-norton']) {
        expect(find.bySemanticsLabel('Add #$actor'), findsOneWidget);
      }
      // The new tag starts in the Actors group (Add / edit entry › New tag:
      // confirm and pick a category).
      await tester.tap(find.bySemanticsLabel('Add #tina-fey'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('It will be added to your tag list under Actors.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Create tag'));
      await tester.tap(find.text('Create tag'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TagChip, '#tina-fey'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #tina-fey'), findsNothing);
    });

    testWidgets('an actor the library already has goes on at once', (
      tester,
    ) async {
      final fixture = loadFixture();
      final soul = FakeLookupSource.catalogSearch(
        'soul',
        type: MediaType.movies,
      ).single;
      await pumpApp(
        tester,
        EntryFormScreen.create(match: soul),
        library: fixture.copyWith(
          tags: {
            ...fixture.tags,
            TagCategory.actors: ['tina-fey'],
          },
        ),
      );
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.widgetWithText(TagChip, '#tina-fey'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #tina-fey'), findsNothing);
      expect(find.bySemanticsLabel('Add #jamie-foxx'), findsOneWidget);
    });

    testWidgets('a show gets its cast too', (tester) async {
      final show = FakeLookupSource.catalogSearch(
        'the last of us',
        type: MediaType.shows,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: show));
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.bySemanticsLabel('Add #pedro-pascal'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #bella-ramsey'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #gabriel-luna'), findsOneWidget);
    });

    testWidgets('an existing studio tag goes on at once, like a genre', (
      tester,
    ) async {
      final match = FakeLookupSource.catalogSearch(
        'spirited',
        type: MediaType.anime,
      ).single;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.text('Tags'));
      expect(find.widgetWithText(TagChip, '#studio-ghibli'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #studio-ghibli'), findsNothing);
      // Removed, it comes back as a suggestion without the "new" badge.
      await tester.tap(find.widgetWithText(TagChip, '#studio-ghibli'));
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(PillChip, '#studio-ghibli');
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Add #studio-ghibli'), findsOneWidget);
    });

    testWidgets('an album suggests no artist tag', (tester) async {
      final match = FakeLookupSource.catalogSearch('hounds').single;
      await pumpApp(tester, EntryFormScreen.create(match: match));
      await scrollTo(tester, find.text('Suggested · tap to add'));
      expect(find.bySemanticsLabel('Add #kate-bush'), findsNothing);
    });
  });

  group('tag picker', () {
    Future<ProviderContainer> openPicker(WidgetTester tester) async {
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(type: MediaType.movies),
      );
      await tester.enterText(field('Title'), 'Nosferatu');
      await scrollTo(tester, find.text('Choose from your tags'));
      await tester.tap(find.text('Choose from your tags'));
      await tester.pumpAndSettle();
      expect(find.text('Add tags'), findsOneWidget);
      return container;
    }

    Future<void> done(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
    }

    Future<void> add(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens without the keyboard; the search box waits for a tap', (
      tester,
    ) async {
      await openPicker(tester);
      bool anyFocused() => tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((e) => e.focusNode.hasFocus);
      expect(anyFocused(), isFalse);
      await tester.tap(find.text('Search or create a tag'));
      await tester.pumpAndSettle();
      expect(anyFocused(), isTrue);
    });

    testWidgets('picks existing tags from their groups', (tester) async {
      final container = await openPicker(tester);
      // Every category starts folded (Add / edit entry › Tag picker): its row
      // is there, its chips are not until it is opened.
      expect(find.text('Genres'), findsOneWidget);
      expect(find.text('Mood'), findsOneWidget);
      expect(find.widgetWithText(PillChip, '#horror'), findsNothing);
      await tester.tap(find.text('Genres'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PillChip, '#horror'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mood'));
      await tester.tap(find.text('Mood'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(PillChip, '#dark'));
      await tester.tap(find.widgetWithText(PillChip, '#dark'));
      await tester.pumpAndSettle();
      await done(tester);
      expect(find.text('#horror'), findsOneWidget);
      expect(find.text('#dark'), findsOneWidget);
      await add(tester);
      expect(repo(container).current!.entries.last.tags, ['horror', 'dark']);
    });

    testWidgets(
      'groups holding a tag on the entry start open; folded rows count '
      'the selected; a search opens every match',
      (tester) async {
        await openPicker(tester);
        await tester.tap(find.text('Genres'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PillChip, '#horror'));
        await tester.pumpAndSettle();
        await done(tester);
        // Opened again: Genres is open because #horror is on the entry,
        // the rest stay folded.
        await tester.tap(find.widgetWithText(TagChip, '#horror'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(PillChip, '#horror'), findsOneWidget);
        expect(find.widgetWithText(PillChip, '#dark'), findsNothing);
        // Folded, Genres still says how many of its tags are picked.
        await tester.tap(find.text('Genres'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(PillChip, '#horror'), findsNothing);
        expect(find.text('1 selected'), findsOneWidget);
        // A search shows the matches from every group, folded or not.
        await tester.enterText(
          find.descendant(
            of: find.byType(TagPickerSheet),
            matching: find.byType(TextField),
          ),
          'dar',
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(PillChip, '#dark'), findsOneWidget);
      },
    );

    Future<void> openWithActors(WidgetTester tester, MediaType type) async {
      final fixture = loadFixture();
      await pumpApp(
        tester,
        EntryFormScreen.create(type: type),
        library: fixture.copyWith(
          tags: {
            ...fixture.tags,
            TagCategory.actors: ['kate-siegel'],
          },
        ),
      );
      await tester.enterText(field('Title'), 'Midnight Mass');
      await scrollTo(tester, find.text('Choose from your tags'));
      await tester.tap(find.text('Choose from your tags'));
      await tester.pumpAndSettle();
    }

    testWidgets('Actors shows for a show, folded like the rest', (
      tester,
    ) async {
      await openWithActors(tester, MediaType.shows);
      expect(find.text('Actors'), findsOneWidget);
      expect(find.widgetWithText(PillChip, '#kate-siegel'), findsNothing);
      await tester.tap(find.text('Actors'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PillChip, '#kate-siegel'), findsOneWidget);
    });

    testWidgets('Actors is left out for a book, unless searched', (
      tester,
    ) async {
      await openWithActors(tester, MediaType.books);
      expect(find.text('Actors'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byType(TagPickerSheet),
          matching: find.byType(TextField),
        ),
        'kate',
      );
      await tester.pumpAndSettle();
      expect(find.text('Actors'), findsOneWidget);
      expect(find.widgetWithText(PillChip, '#kate-siegel'), findsOneWidget);
    });

    testWidgets(
      'groups are A to Z; a long one is a row that opens its full list',
      (tester) async {
        final authors = [
          for (var i = 0; i < 25; i++)
            'author-${String.fromCharCode(0x61 + i)}',
        ];
        final fixture = loadFixture();
        final library = fixture.copyWith(
          tags: {...fixture.tags, TagCategory.authors: authors},
          entries: [
            ...fixture.entries,
            fixture.entries.first.copyWith(id: 'books/x', tags: authors),
          ],
        );
        await pumpApp(
          tester,
          const EntryFormScreen.create(type: MediaType.books),
          library: library,
        );
        await scrollTo(tester, find.text('Choose from your tags'));
        await tester.tap(find.text('Choose from your tags'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Genres'));
        await tester.pumpAndSettle();
        final adventure = tester.getTopLeft(
          find.widgetWithText(PillChip, '#adventure'),
        );
        final horror = tester.getTopLeft(
          find.widgetWithText(PillChip, '#horror'),
        );
        expect(adventure.dy <= horror.dy, isTrue);
        final row = find.bySemanticsLabel('Authors, 25 authors');
        await tester.scrollUntilVisible(
          row,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Author C'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel('Authors, 25 authors · 1 selected'),
          findsOneWidget,
        );
        await done(tester);
        expect(find.widgetWithText(TagChip, '#author-c'), findsOneWidget);
      },
    );

    testWidgets('game and music genres show only for their type', (
      tester,
    ) async {
      await openPicker(tester);
      expect(find.text('Game genres'), findsNothing);
      expect(find.text('Music genres'), findsNothing);
      // A search finds any tag.
      await tester.enterText(
        find.descendant(
          of: find.byType(TagPickerSheet),
          matching: find.byType(TextField),
        ),
        'metro',
      );
      await tester.pumpAndSettle();
      expect(find.text('Game genres'), findsOneWidget);
      expect(find.widgetWithText(PillChip, '#metroidvania'), findsOneWidget);
    });

    testWidgets('a similar tag is offered instead', (tester) async {
      final container = await openPicker(tester);
      await tester.enterText(find.byType(TextField).last, 'sci-fi');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Create #sci-fi'));
      await tester.pumpAndSettle();
      expect(find.text('A similar tag exists'), findsOneWidget);
      expect(find.textContaining('used on'), findsOneWidget);
      await tester.tap(find.text('Use #scifi'));
      await tester.pumpAndSettle();
      await done(tester);
      await add(tester);
      final library = repo(container).current!;
      expect(library.entries.last.tags, ['scifi']);
      expect(library.allTags.contains('sci-fi'), isFalse);
    });

    testWidgets('a new tag is confirmed with a category', (tester) async {
      final container = await openPicker(tester);
      await tester.enterText(find.byType(TextField).last, 'Gothic');
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Create #gothic'));
      await tester.pumpAndSettle();
      expect(find.text('Create a new tag?'), findsOneWidget);
      expect(
        find.textContaining('It will be added to your tag list under Genres.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.widgetWithText(PillChip, 'Mood'));
      await tester.tap(find.widgetWithText(PillChip, 'Mood'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('It will be added to your tag list under Mood.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Create tag'));
      await tester.tap(find.text('Create tag'));
      await tester.pumpAndSettle();
      expect(find.text('New on this entry'), findsOneWidget);
      expect(find.widgetWithText(PillChip, '#gothic'), findsOneWidget);
      // Not in the library until the entry is saved.
      expect(repo(container).current!.allTags.contains('gothic'), isFalse);
      await done(tester);
      expect(find.text('#gothic'), findsOneWidget);
      await add(tester);
      final library = repo(container).current!;
      expect(library.tags[TagCategory.mood]!.last, 'gothic');
      expect(library.entries.last.tags, ['gothic']);
    });

    testWidgets(
      'creating anyway after a similar tag goes through the category step',
      (tester) async {
        final container = await openPicker(tester);
        await tester.enterText(find.byType(TextField).last, 'horrors');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Create #horrors'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create #horrors anyway'));
        await tester.pumpAndSettle();
        expect(find.text('Create a new tag?'), findsOneWidget);
        await tester.ensureVisible(find.text('Create tag'));
        await tester.tap(find.text('Create tag'));
        await tester.pumpAndSettle();
        // Unpick it again: it must not be created.
        await tester.tap(find.widgetWithText(PillChip, '#horrors'));
        await tester.pumpAndSettle();
        await done(tester);
        await add(tester);
        final library = repo(container).current!;
        expect(library.allTags.contains('horrors'), isFalse);
        expect(library.entries.last.tags, isEmpty);
      },
    );

    testWidgets(
      'cancelling the similar tag and category dialogs changes nothing',
      (tester) async {
        await openPicker(tester);
        await tester.enterText(find.byType(TextField).last, 'cosy');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Create #cosy'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('A similar tag exists'), findsNothing);
        expect(find.bySemanticsLabel('Create #cosy'), findsOneWidget);

        await tester.enterText(find.byType(TextField).last, 'moody');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Create #moody'));
        await tester.pumpAndSettle();
        expect(find.text('Create a new tag?'), findsOneWidget);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(PillChip, '#moody'), findsNothing);
      },
    );
  });

  group('series', () {
    /// The text field under the label [label].
    Finder fieldUnder(String label) => find.descendant(
      of: find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first,
      matching: find.byType(TextField),
    );
    Finder seriesField() => fieldUnder('Series');
    Finder numberField() => fieldUnder('Number');

    /// Scrolls back up to [finder], past what [scrollTo] left above.
    Future<void> scrollUpTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'movies, books, games and anime movies have Series and Number',
      (tester) async {
        await pumpApp(
          tester,
          const EntryFormScreen.create(type: MediaType.movies),
        );
        // Under the director and the date, on screen from the start.
        expect(find.text('Series'), findsOneWidget);
        expect(find.text('Number'), findsOneWidget);
        for (final type in ['Shows', 'Music']) {
          await tester.tap(find.widgetWithText(PillChip, type));
          await tester.pumpAndSettle();
          expect(find.text('Number'), findsNothing, reason: type);
        }
        await tester.tap(find.widgetWithText(PillChip, 'Games'));
        await tester.pumpAndSettle();
        expect(find.text('Number'), findsOneWidget);
        await tester.tap(find.widgetWithText(PillChip, 'Anime'));
        await tester.pumpAndSettle();
        // An anime of no kind yet may be in a series; a series uses seasons.
        expect(find.text('Series or movie'), findsOneWidget);
        expect(find.text('Number'), findsOneWidget);
        await tester.tap(animeKind('Series'));
        await tester.pumpAndSettle();
        expect(find.text('Number'), findsNothing);
        await scrollTo(tester, find.text('Seasons'));
        expect(find.text('Seasons'), findsOneWidget);
        await scrollUpTo(tester, animeKind('Movie'));
        await tester.tap(animeKind('Movie'));
        await tester.pumpAndSettle();
        expect(find.text('Seasons'), findsNothing);
        expect(find.text('Number'), findsOneWidget);
        // Books: after Pages and Formats, as drawn.
        await scrollUpTo(tester, find.widgetWithText(PillChip, 'Books'));
        await tester.tap(find.widgetWithText(PillChip, 'Books'));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.text('Number'));
        expect(
          tester.getTopLeft(find.text('Series')).dy,
          greaterThan(tester.getTopLeft(find.text('Formats')).dy),
        );
      },
    );

    testWidgets('come from the match and are saved; cleared when emptied', (
      tester,
    ) async {
      const match = LookupMatch(
        type: MediaType.movies,
        title: 'The Two Towers',
        source: 'tmdb:movie:121',
        released: Released(2002),
        series: Series(name: 'The Lord of the Rings', number: 2),
      );
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(match: match),
      );
      await scrollTo(tester, find.text('Number'));
      expect(
        find.widgetWithText(TextField, 'The Lord of the Rings'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entries.last;
      expect(
        saved.series,
        const Series(name: 'The Lord of the Rings', number: 2),
      );
    });

    testWidgets('emptied, the series is dropped', (tester) async {
      final towers = loadFixture().entryById(
        'movies/the-lord-of-the-rings-the-two-towers-2002',
      )!;
      final container = await pumpApp(tester, EntryFormScreen.edit(towers));
      await scrollTo(tester, find.text('Number'));
      await tester.enterText(seriesField(), '');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.entryById(towers.id)!.series, isNull);
    });

    testWidgets('typed by hand, the number is digits only and optional', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(
          type: MediaType.books,
          title: 'Dune Messiah',
        ),
      );
      await scrollTo(tester, find.text('Number'));
      await tester.enterText(seriesField(), 'Dune');
      await tester.enterText(numberField(), 'two');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(
        repo(container).current!.entries.last.series,
        const Series(name: 'Dune'),
      );
    });
  });

  group('anime kind', () {
    testWidgets('a series match gets seasons and no date; the kind is saved', (
      tester,
    ) async {
      final match = FakeLookupSource.catalogSearch('frieren').single;
      final container = await pumpApp(
        tester,
        EntryFormScreen.create(match: match),
      );
      expect(find.text('Series or movie'), findsOneWidget);
      expect(find.text('Released'), findsNothing);
      await scrollTo(tester, find.text('Seasons'));
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      final saved = repo(container).current!.entries.last;
      expect(saved.kind, EntryKind.series);
      expect(saved.released, isNull);
      expect(saved.seasons, hasLength(2));
      expect(saved.usesSeasons, isTrue);
      // Named from Season 1's year, like a show (the fixture has it already).
      expect(saved.id, startsWith('anime/frieren-beyond-journeys-end-2023'));
    });

    testWidgets('a movie match keeps its date and saves the kind', (
      tester,
    ) async {
      final match = FakeLookupSource.catalogSearch(
        'akira',
        type: MediaType.anime,
      ).single;
      final container = await pumpApp(
        tester,
        EntryFormScreen.create(match: match),
      );
      expect(find.text('Released'), findsOneWidget);
      expect(find.text('Seasons'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.entries.last.kind, EntryKind.movie);
    });

    testWidgets('an anime from before kinds starts unpicked and stays so', (
      tester,
    ) async {
      final old = loadFixture().entryById('anime/spirited-away-2001')!;
      expect(old.kind, isNull);
      final container = await pumpApp(tester, EntryFormScreen.edit(old));
      expect(find.text('Released'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo(container).current!.entryById(old.id)!.kind, isNull);
    });

    testWidgets(
      'picking Series turns the date into Season 1; Movie turns it back',
      (tester) async {
        final old = loadFixture().entryById('anime/spirited-away-2001')!;
        final container = await pumpApp(tester, EntryFormScreen.edit(old));
        await tester.tap(animeKind('Series'));
        await tester.pumpAndSettle();
        expect(find.text('Released'), findsNothing);
        await scrollTo(tester, find.text('Seasons'));
        expect(find.text('Season 1'), findsOneWidget);
        expect(find.text('2001'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        final series = repo(container).current!.entryById(old.id)!;
        expect(series.kind, EntryKind.series);
        expect(series.released, isNull);
        expect(series.seasons!.single.released, const Released(2001));
        expect(series.seasons!.single.status, EntryStatus.done);
        expect(series.status, EntryStatus.done);
      },
    );

    testWidgets('back to Movie, the date and status come from Season 1', (
      tester,
    ) async {
      final series = loadFixture().entryById(
        'anime/frieren-beyond-journeys-end-2023',
      )!;
      final container = await pumpApp(tester, EntryFormScreen.edit(series));
      await tester.tap(animeKind('Movie'));
      await tester.pumpAndSettle();
      expect(find.text('Seasons'), findsNothing);
      expect(find.text('Sep 29, 2023'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final movie = repo(container).current!.entryById(series.id)!;
      expect(movie.kind, EntryKind.movie);
      expect(movie.seasons, isNull);
      expect(movie.released, const Released(2023, 9, 29));
      expect(movie.status, EntryStatus.inProgress);
    });
  });
}
