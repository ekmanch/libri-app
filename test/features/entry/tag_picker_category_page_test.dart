import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/features/entry/tag_picker_sheet.dart';
import 'package:library_app/features/library/library_home_screen.dart';
import 'package:library_app/features/library/tag_list_screen.dart';
import 'package:library_app/widgets/app_dialog.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/create_tag_row.dart';

import '../../helpers/pump.dart';
import '../../helpers/pump_app.dart';

/// Creating a tag from a category's own page (Library › Tag picker: all
/// Authors, create a tag; Add / edit entry › New tag: from a category's
/// page): the page a long group opens to from the entry form's tag picker
/// offers to create the tag a search names, in that category; the same
/// page opened from the filter sheet does not.
void main() {
  // Twenty-six authors make a long group.
  final authors = [
    for (var i = 0; i < 25; i++) 'author-${String.fromCharCode(0x61 + i)}',
    'stephen-king',
  ];

  Library longAuthors() {
    final fixture = loadFixture();
    return fixture.copyWith(
      tags: {...fixture.tags, TagCategory.authors: authors},
      entries: [
        ...fixture.entries,
        for (final (i, tag) in authors.indexed)
          fixture.entries.first.copyWith(
            id: 'books/author-$i',
            type: MediaType.books,
            title: 'Book $i',
            tags: [tag],
          ),
      ],
    );
  }

  Finder pageField() => find.descendant(
    of: find.byType(TagListScreen),
    matching: find.byType(TextField),
  );

  Finder createRow(String tag) =>
      find.bySemanticsLabel('Create #$tag in Authors');

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(pageField(), text);
    await tester.pumpAndSettle();
  }

  /// Starts a new book, opens its tag picker and the Authors page from it.
  Future<ProviderContainer> openAuthors(WidgetTester tester) async {
    final container = await pumpApp(
      tester,
      const EntryFormScreen.create(type: MediaType.books),
      library: longAuthors(),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Title',
      ),
      'A Man Called Ove',
    );
    await tester.scrollUntilVisible(
      find.text('Choose from your tags'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from your tags'));
    await tester.pumpAndSettle();
    final row = find.bySemanticsLabel('Authors, 26 authors');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(TagListScreen), findsOneWidget);
    return container;
  }

  testWidgets('a query that is no tag yet offers to create it in the '
      'category, above the matches', (tester) async {
    await openAuthors(tester);
    expect(find.byType(CreateTagRow), findsNothing);

    // Nothing matches: the row and the empty line.
    await search(tester, 'Fredrik Backman');
    expect(createRow('fredrik-backman'), findsOneWidget);
    expect(find.text('Create “#fredrik-backman” in Authors'), findsOneWidget);
    expect(find.text('None of your authors match.'), findsOneWidget);

    // Something matches, but not exactly: the row sits above the matches.
    await search(tester, 'king');
    expect(createRow('king'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(CreateTagRow)).dy,
      lessThan(tester.getTopLeft(find.text('Stephen King')).dy),
    );
    expect(find.text('None of your authors match.'), findsNothing);

    // An existing tag is not offered, in this category or another, and is
    // found by its name typed any way that names it.
    await search(tester, 'Stephen King');
    expect(find.byType(CreateTagRow), findsNothing);
    await search(tester, 'stephen.king');
    expect(find.byType(CreateTagRow), findsNothing);
    expect(find.text('Stephen King'), findsOneWidget);
    await search(tester, '#horror');
    expect(find.byType(CreateTagRow), findsNothing);

    // Normalized as everywhere, the "&" rule included.
    await search(tester, 'R & B');
    expect(createRow('r&b'), findsOneWidget);
  });

  testWidgets('the row opens New tag with the category picked; Create '
      'returns to the page with the tag ticked', (tester) async {
    final container = await openAuthors(tester);
    await search(tester, 'Aaron Aardvark');
    await tester.tap(createRow('aaron-aardvark'));
    await tester.pumpAndSettle();

    expect(find.text('Create a new tag?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.textContaining('#aaron-aardvark'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('under Authors.'), findsOneWidget);
    Finder chip(String label) => find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(PillChip, label),
    );
    expect(tester.widget<PillChip>(chip('Authors')).selected, isTrue);
    // More categories of the same kind can be added, as usual.
    await tester.tap(chip('Directors'));
    await tester.pumpAndSettle();
    expect(find.textContaining('under Authors and Directors.'), findsOneWidget);
    await tester.tap(chip('Directors'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create tag'));
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();

    // Back on the category's page: the search shows the new tag, ticked.
    expect(find.byType(TagListScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(pageField()).controller!.text,
      'Aaron Aardvark',
    );
    expect(find.byType(CreateTagRow), findsNothing);
    expect(find.text('1 author · 1 selected'), findsOneWidget);
    expect(find.text('#aaron-aardvark · new'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Aaron Aardvark')),
      isSemantics(isChecked: true),
    );

    // Done returns to the picker, which has the tag; then the form.
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(TagListScreen), findsNothing);
    expect(find.text('Add tags'), findsOneWidget);
    expect(find.text('New on this entry'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('#aaron-aardvark'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final library = (container.read(
      libraryRepositoryProvider,
    ) as FixtureLibraryRepository).current!;
    expect(library.categoriesOf('aaron-aardvark'), [TagCategory.authors]);
    expect(library.entries.last.tags, contains('aaron-aardvark'));
  });

  testWidgets('Back returns to the picker', (tester) async {
    await openAuthors(tester);
    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    expect(find.byType(TagListScreen), findsNothing);
    expect(find.byType(TagPickerSheet), findsOneWidget);
  });

  testWidgets('the similar-tag check runs: using the existing tag ticks it '
      'on the page', (tester) async {
    await openAuthors(tester);
    await search(tester, 'stephen kings');
    await tester.tap(createRow('stephen-kings'));
    await tester.pumpAndSettle();
    expect(find.text('A similar tag exists'), findsOneWidget);
    await tester.tap(find.text('Use #stephen-king'));
    await tester.pumpAndSettle();
    expect(find.text('Create a new tag?'), findsNothing);
    expect(find.byType(TagListScreen), findsOneWidget);
    expect(find.text('1 author · 1 selected'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Stephen King')),
      isSemantics(isChecked: true),
    );

    // Cancelling the check leaves the page and its search as they were.
    await search(tester, 'stephen kings');
    await tester.tap(createRow('stephen-kings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(createRow('stephen-kings'), findsOneWidget);
    expect(find.text('None of your authors match.'), findsOneWidget);
  });

  testWidgets('the same page opened from Filter has no Create row', (
    tester,
  ) async {
    await pumpApp(tester, const LibraryHomeScreen(), library: longAuthors());
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    final row = find.bySemanticsLabel('Authors, 26 authors');
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(TagListScreen), findsOneWidget);
    await search(tester, 'Fredrik Backman');
    expect(find.byType(CreateTagRow), findsNothing);
    expect(find.text('None of your authors match.'), findsOneWidget);
    await search(tester, 'king');
    expect(find.byType(CreateTagRow), findsNothing);
    expect(find.text('Stephen King'), findsOneWidget);
  });

  testWidgets('the page alone creates nothing unless it is given a way', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpThemed(
      tester,
      TagListScreen(
        category: TagCategory.authors,
        tags: authors,
        selected: const {},
        library: longAuthors(),
        onToggle: (_) {},
        // No onCreate: asked or not, there is no row.
        canCreate: (_) => true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byType(CreateTagRow), findsNothing);
  });
}
