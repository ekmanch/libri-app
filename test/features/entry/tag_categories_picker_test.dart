import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/entry/entry_form_screen.dart';
import 'package:library_app/features/entry/tag_picker_sheet.dart';
import 'package:library_app/widgets/app_dialog.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/tag_group.dart';

import '../../helpers/pump_app.dart';

/// A tag in more than one category in Add / edit entry (Tag in two
/// categories: entry form, tag picker; New tag): ticked per category, its
/// categories edited with a long press or "+ Add to", created with several
/// categories, and ticked per role by a lookup.
void main() {
  const babyId = 'movies/million-dollar-baby-2004';
  const westernId = 'movies/the-good-the-bad-and-the-ugly-1966';

  FixtureLibraryRepository repo(ProviderContainer c) =>
      c.read(libraryRepositoryProvider) as FixtureLibraryRepository;

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// The tag chip in one group of the picker.
  Finder chipIn(String group, String tag) => find.descendant(
    of: find.widgetWithText(TagGroup, group),
    matching: find.widgetWithText(PillChip, tag),
  );

  Finder pickerField() => find.descendant(
    of: find.byType(TagPickerSheet),
    matching: find.byType(TextField),
  );

  /// Edits Million Dollar Baby and opens its tag picker.
  Future<ProviderContainer> openPicker(WidgetTester tester) async {
    final container = await pumpApp(
      tester,
      EntryFormScreen.edit(loadFixture().entryById(babyId)!),
    );
    await scrollTo(tester, find.text('Tags'));
    await tester.tap(find.widgetWithText(TagChip, '#drama'));
    await tester.pumpAndSettle();
    expect(find.text('Add tags'), findsOneWidget);
    return container;
  }

  /// Scrolls the sheet to the chip, then taps or long-presses it.
  Future<void> press(
    WidgetTester tester,
    Finder finder, {
    bool long = false,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    if (long) {
      await tester.longPress(finder);
    } else {
      await tester.tap(finder);
    }
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  testWidgets('the form shows a chip per role; the picker ticks per group', (
    tester,
  ) async {
    final container = await openPicker(tester);
    // Behind the picker, the form: one chip per category the tag has here.
    expect(find.text('#clint-eastwood · Director'), findsOneWidget);
    expect(find.text('#clint-eastwood · Actor'), findsOneWidget);
    expect(find.widgetWithText(TagChip, '#hilary-swank'), findsOneWidget);
    // The picker lists the tag in both groups, ticked in both; both groups
    // start open since they hold a tag on the entry.
    expect(chipIn('Directors', '#clint-eastwood'), findsOneWidget);
    expect(chipIn('Actors', '#clint-eastwood'), findsOneWidget);
    expect(
      tester.widget<PillChip>(chipIn('Actors', '#clint-eastwood')).selected,
      isTrue,
    );
    expect(find.text('3 selected'), findsOneWidget); // Actors.
    await press(tester, chipIn('Actors', '#clint-eastwood'));
    expect(find.text('2 selected'), findsOneWidget);
    expect(
      tester.widget<PillChip>(chipIn('Directors', '#clint-eastwood')).selected,
      isTrue,
    );
    await done(tester);
    expect(find.text('#clint-eastwood · Director'), findsOneWidget);
    expect(find.text('#clint-eastwood · Actor'), findsNothing);
    await save(tester, 'Save');
    final saved = repo(container).current!.entryById(babyId)!;
    expect(saved.tags, [
      'drama',
      'clint-eastwood',
      'hilary-swank',
      'morgan-freeman',
    ]);
    expect(saved.tagCategories, {
      'clint-eastwood': [TagCategory.directors],
    });
  });

  testWidgets('the last category unticked takes the tag off the entry', (
    tester,
  ) async {
    final container = await openPicker(tester);
    await press(tester, chipIn('Actors', '#clint-eastwood'));
    await press(tester, chipIn('Directors', '#clint-eastwood'));
    await done(tester);
    // Off the entry; the creator field offers it again under the Tags box.
    expect(
      find.descendant(
        of: find.byType(TagChip),
        matching: find.textContaining('#clint-eastwood'),
      ),
      findsNothing,
    );
    expect(
      find.widgetWithText(DashedChip, '#clint-eastwood · Director'),
      findsOneWidget,
    );
    await save(tester, 'Save');
    final saved = repo(container).current!.entryById(babyId)!;
    expect(saved.tags, ['drama', 'hilary-swank', 'morgan-freeman']);
    expect(saved.tagCategories, isNull);
  });

  testWidgets('a long press edits the categories; a category taken away '
      'reaches every entry when the form is saved', (tester) async {
    final container = await openPicker(tester);
    await press(tester, chipIn('Directors', '#clint-eastwood'), long: true);
    expect(
      find.text('Used on 2 entries: as an actor on 2, as a director on 1.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'People can be in Authors, Directors and Actors. At least one stays '
        'picked.',
      ),
      findsOneWidget,
    );
    Finder dialogChip(String label) => find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(PillChip, label),
    );
    expect(dialogChip('Authors'), findsOneWidget);
    expect(dialogChip('Genres'), findsNothing);
    expect(tester.widget<PillChip>(dialogChip('Actors')).selected, isTrue);
    await tester.tap(dialogChip('Actors'));
    await tester.pumpAndSettle();
    // At least one stays: the last one cannot be unticked.
    await tester.tap(dialogChip('Directors'));
    await tester.pumpAndSettle();
    expect(tester.widget<PillChip>(dialogChip('Directors')).selected, isTrue);
    await tester.tap(
      find.descendant(of: find.byType(AppDialog), matching: find.text('Save')),
    );
    await tester.pumpAndSettle();
    // One category now: listed once, and the form's chip has no role.
    expect(chipIn('Actors', '#clint-eastwood'), findsNothing);
    expect(chipIn('Directors', '#clint-eastwood'), findsOneWidget);
    await done(tester);
    expect(find.text('#clint-eastwood'), findsOneWidget);
    expect(find.text('#clint-eastwood · Director'), findsNothing);
    await save(tester, 'Save');
    final library = repo(container).current!;
    expect(library.categoriesOf('clint-eastwood'), [TagCategory.directors]);
    expect(library.entryById(babyId)!.tagCategories, isNull);
    // Only an actor there: the western lost the tag.
    expect(library.entryById(westernId)!.tags, ['adventure', 'classic']);
  });

  testWidgets('a long press on a one-category tag moves it to another '
      'one-category group, and it stays on all its entries', (tester) async {
    final container = await openPicker(tester);
    // Other is folded: nothing of it is on this entry.
    await press(tester, find.text('Other'));
    await press(tester, chipIn('Other', '#favorite'), long: true);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(
      find.text(
        'This kind of tag is in one category. Moving it keeps it on all its '
        'entries.',
      ),
      findsOneWidget,
    );
    Finder dialogChip(String label) => find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(PillChip, label),
    );
    expect(dialogChip('Languages'), findsOneWidget);
    expect(dialogChip('Mood'), findsOneWidget);
    expect(dialogChip('Genres'), findsNothing);
    expect(dialogChip('Directors'), findsNothing);
    expect(tester.widget<PillChip>(dialogChip('Other')).selected, isTrue);
    await tester.tap(dialogChip('Languages'));
    await tester.pumpAndSettle();
    // Exactly one: picking Languages unpicks Other.
    expect(tester.widget<PillChip>(dialogChip('Other')).selected, isFalse);
    expect(tester.widget<PillChip>(dialogChip('Languages')).selected, isTrue);
    await tester.tap(
      find.descendant(of: find.byType(AppDialog), matching: find.text('Save')),
    );
    await tester.pumpAndSettle();
    expect(chipIn('Other', '#favorite'), findsNothing);
    await press(tester, find.text('Languages'));
    expect(chipIn('Languages', '#favorite'), findsOneWidget);
    await done(tester);
    await save(tester, 'Save');
    final before = loadFixture();
    final library = repo(container).current!;
    expect(library.categoriesOf('favorite'), [TagCategory.languages]);
    expect(library.tags[TagCategory.other], ['classic']);
    // Every entry that had it still has it.
    for (final entry in before.entries) {
      expect(
        library.entryById(entry.id)!.tags.contains('favorite'),
        entry.tags.contains('favorite'),
        reason: entry.id,
      );
    }
  });

  testWidgets('a search offers "Add to" another category of the kind', (
    tester,
  ) async {
    final container = await openPicker(tester);
    await tester.enterText(pickerField(), 'hilary');
    await tester.pumpAndSettle();
    expect(chipIn('Actors', '#hilary-swank'), findsOneWidget);
    expect(find.text('Not a director tag yet'), findsOneWidget);
    expect(find.text('Not an author tag yet'), findsOneWidget);
    expect(find.text('Add to Directors'), findsOneWidget);
    await press(
      tester,
      find.bySemanticsLabel('Add #hilary-swank to Directors'),
    );
    // The search is cleared; the tag now sits in Directors too, ticked.
    expect(find.text('Add to Directors'), findsNothing);
    expect(
      tester.widget<PillChip>(chipIn('Directors', '#hilary-swank')).selected,
      isTrue,
    );
    await done(tester);
    expect(find.text('#hilary-swank · Director'), findsOneWidget);
    expect(find.text('#hilary-swank · Actor'), findsOneWidget);
    await save(tester, 'Save');
    final library = repo(container).current!;
    expect(library.categoriesOf('hilary-swank'), [
      TagCategory.directors,
      TagCategory.actors,
    ]);
    expect(library.entryById(babyId)!.tagCategories!['hilary-swank'], [
      TagCategory.directors,
      TagCategory.actors,
    ]);
  });

  testWidgets('a new tag takes several categories of one kind; another kind '
      'starts over', (tester) async {
    final container = await pumpApp(
      tester,
      const EntryFormScreen.create(type: MediaType.movies),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Title',
      ),
      'A Fistful of Dollars',
    );
    await scrollTo(tester, find.text('Choose from your tags'));
    await tester.tap(find.text('Choose from your tags'));
    await tester.pumpAndSettle();
    await tester.enterText(pickerField(), 'sergio-leone');
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Create #sergio-leone'));
    await tester.pumpAndSettle();
    Finder chip(String label) => find.descendant(
      of: find.byType(AppDialog),
      matching: find.widgetWithText(PillChip, label),
    );
    expect(find.textContaining('under Genres.'), findsOneWidget);
    await tester.tap(chip('Directors')); // Another kind: starts over.
    await tester.pumpAndSettle();
    expect(find.textContaining('under Directors.'), findsOneWidget);
    await tester.tap(chip('Actors'));
    await tester.pumpAndSettle();
    expect(find.textContaining('under Directors and Actors.'), findsOneWidget);
    await tester.tap(chip('Mood'));
    await tester.pumpAndSettle();
    expect(find.textContaining('under Mood.'), findsOneWidget);
    await tester.tap(chip('Mood'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one category.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create tag'))
          .onPressed,
      isNull,
    );
    await tester.tap(chip('Directors'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Actors'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create tag'));
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();
    expect(find.text('New on this entry'), findsOneWidget);
    await done(tester);
    expect(find.text('#sergio-leone · Director'), findsOneWidget);
    expect(find.text('#sergio-leone · Actor'), findsOneWidget);
    await save(tester, 'Add');
    final library = repo(container).current!;
    expect(library.categoriesOf('sergio-leone'), [
      TagCategory.directors,
      TagCategory.actors,
    ]);
    expect(library.entries.last.tagCategories, {
      'sergio-leone': [TagCategory.directors, TagCategory.actors],
    });
  });

  group('a lookup ticks a person per role', () {
    const match = LookupMatch(
      type: MediaType.movies,
      title: 'Gran Torino',
      source: 'tmdb:movie:13223',
      creator: 'Clint Eastwood',
      cast: ['Clint Eastwood', 'Bee Vang'],
    );

    testWidgets('the director who also stars is ticked as both', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(match: match),
      );
      await scrollTo(tester, find.text('Tags'));
      expect(find.text('#clint-eastwood · Director'), findsOneWidget);
      expect(find.text('#clint-eastwood · Actor'), findsOneWidget);
      expect(find.bySemanticsLabel('Add #bee-vang'), findsOneWidget);
      await save(tester, 'Add');
      expect(repo(container).current!.entries.last.tagCategories, {
        'clint-eastwood': [TagCategory.directors, TagCategory.actors],
      });
    });

    testWidgets('a person the library has under another role is offered '
        'with the new one', (tester) async {
      final fixture = loadFixture();
      final container = await pumpApp(
        tester,
        const EntryFormScreen.create(match: match),
        library: fixture.copyWith(
          tags: {
            ...fixture.tags,
            TagCategory.actors: ['hilary-swank', 'morgan-freeman'],
          },
        ),
      );
      await scrollTo(tester, find.text('Suggested · tap to add'));
      // Ticked as the director, which is the tag's only category.
      expect(find.widgetWithText(TagChip, '#clint-eastwood'), findsOneWidget);
      expect(
        find.widgetWithText(DashedChip, '#clint-eastwood · Actor'),
        findsOneWidget,
      );
      await press(tester, find.bySemanticsLabel('Add #clint-eastwood · Actor'));
      expect(find.text('#clint-eastwood · Director'), findsOneWidget);
      expect(find.text('#clint-eastwood · Actor'), findsOneWidget);
      expect(find.byType(DashedChip), findsOneWidget); // #bee-vang.
      await save(tester, 'Add');
      final library = repo(container).current!;
      expect(library.categoriesOf('clint-eastwood'), [
        TagCategory.directors,
        TagCategory.actors,
      ]);
      expect(library.entries.last.tagCategories, {
        'clint-eastwood': [TagCategory.directors, TagCategory.actors],
      });
    });
  });
}
