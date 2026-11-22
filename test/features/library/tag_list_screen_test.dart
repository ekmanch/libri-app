import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/tag_list_screen.dart';

import '../../helpers/pump.dart';
import '../../helpers/sample_library.dart';

/// Thirty authors spread over the alphabet, each on one book, plus a
/// "The" to sort by its second word.
const authors = [
  'isaac-asimov',
  'margaret-atwood',
  'clive-barker',
  'ray-bradbury',
  'octavia-e-butler',
  'agatha-christie',
  'blake-crouch',
  'philip-k-dick',
  'charles-dickens',
  'gillian-flynn',
  'neil-gaiman',
  'frank-herbert',
  'joe-hill',
  'shirley-jackson',
  'stephen-king',
  'ursula-k-le-guin',
  'h-p-lovecraft',
  'richard-matheson',
  'cormac-mccarthy',
  'jo-nesbo',
  'george-orwell',
  'edgar-allan-poe',
  'terry-pratchett',
  'anne-rice',
  'mary-shelley',
  'dan-simmons',
  'bram-stoker',
  'the-brothers-grimm',
  'kurt-vonnegut',
  'andy-weir',
];

Library authorsLibrary() => Library(
  tags: const {TagCategory.authors: authors},
  entries: [
    for (final (i, tag) in authors.indexed)
      mummy.copyWith(
        id: 'books/b$i',
        title: 'Book $i',
        creator: tag == 'ursula-k-le-guin' ? 'Ursula K. Le Guin' : null,
        tags: [tag],
      ),
  ],
);

void main() {
  Future<List<String>> pumpList(
    WidgetTester tester, {
    Set<String> selected = const {},
    double height = 780,
    List<String> tags = authors,
  }) async {
    final toggled = <String>[];
    await tester.binding.setSurfaceSize(Size(360, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpThemed(
      tester,
      TagListScreen(
        category: TagCategory.authors,
        tags: tags,
        selected: selected,
        library: authorsLibrary(),
        onToggle: toggled.add,
      ),
    );
    await tester.pumpAndSettle();
    return toggled;
  }

  testWidgets('lists the group A to Z under letter headers with the count', (
    tester,
  ) async {
    await pumpList(tester, selected: {'stephen-king'});
    expect(find.text('Authors'), findsOneWidget);
    expect(find.text('30 authors · 1 selected'), findsOneWidget);
    // By tag, so first name first: Agatha before Andy, and Isaac Asimov
    // is under I. The display name comes from the creator text where an
    // entry has one, else from the tag.
    final christie = tester.getTopLeft(find.text('Agatha Christie'));
    final weir = tester.getTopLeft(find.text('Andy Weir'));
    expect(christie.dy, lessThan(weir.dy));
    expect(find.text('#agatha-christie · 1 entry'), findsOneWidget);
    expect(find.text('Isaac Asimov'), findsNothing);
    // Thirty rows and their headers are over three screens: the rail.
    expect(find.byKey(EntryListBody.railKey), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(EntryListBody.railKey),
        matching: find.text('I'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Isaac Asimov'), findsOneWidget);
    expect(find.text('Ursula K. Le Guin'), findsNothing);
  });

  testWidgets('a short group keeps its letter headers and gets no rail', (
    tester,
  ) async {
    await pumpList(tester, tags: authors.take(8).toList());
    expect(find.byKey(EntryListBody.railKey), findsNothing);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('8 authors'), findsOneWidget);
  });

  testWidgets('the search narrows by name or tag and hides the rail', (
    tester,
  ) async {
    await pumpList(tester, height: 500);
    await tester.enterText(find.byType(TextField), 'le guin');
    await tester.pumpAndSettle();
    expect(find.text('Ursula K. Le Guin'), findsOneWidget);
    expect(find.text('Isaac Asimov'), findsNothing);
    expect(find.text('1 author'), findsOneWidget);
    expect(find.byKey(EntryListBody.railKey), findsNothing);

    await tester.enterText(find.byType(TextField), '#king');
    await tester.pumpAndSettle();
    expect(find.text('Stephen King'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('None of your authors match.'), findsOneWidget);
  });

  testWidgets('a tap toggles the row and tells the caller', (tester) async {
    final toggled = await pumpList(tester, selected: {'stephen-king'});
    await tester.tap(find.text('Agatha Christie'));
    await tester.pumpAndSettle();
    expect(find.text('30 authors · 2 selected'), findsOneWidget);
    await tester.tap(find.text('Agatha Christie'));
    await tester.pumpAndSettle();
    expect(find.text('30 authors · 1 selected'), findsOneWidget);
    expect(toggled, ['agatha-christie', 'agatha-christie']);
  });

  testWidgets('"The" sorts by the next word', (tester) async {
    await pumpList(tester);
    // "brothers-grimm" sits under B, between Bram Stoker and the C's.
    final grimm = tester.getTopLeft(find.text('The Brothers Grimm'));
    final stoker = tester.getTopLeft(find.text('Bram Stoker'));
    final dickens = tester.getTopLeft(find.text('Charles Dickens'));
    expect(grimm.dy, greaterThan(stoker.dy));
    expect(grimm.dy, lessThan(dickens.dy));
  });
}
