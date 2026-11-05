import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/underline_tabs.dart';

import '../helpers/pump.dart';

void main() {
  Widget tabs({
    String selected = 'library',
    ValueChanged<String>? onChanged,
    double textScale = 1,
  }) => MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Center(
      child: SizedBox(
        width: 320,
        child: UnderlineTabs<String>(
          tabs: const [
            UnderlineTab('library', 'Library', count: 29),
            UnderlineTab('discover', 'Discover', count: 112),
            UnderlineTab('all', 'All'),
          ],
          selected: selected,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  testWidgets('shows each label with its count and reports the tapped tab', (
    tester,
  ) async {
    String? picked;
    await pumpThemed(tester, tabs(onChanged: (value) => picked = value));
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('29'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('112'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(isSelected(tester, find.text('Library')), isTrue);
    expect(isSelected(tester, find.text('Discover')), isFalse);

    await tester.tap(find.text('112'));
    expect(picked, 'discover');
  });

  testWidgets('the selected tab is in the text color, the others muted, '
      'the counts a step dimmer', (tester) async {
    await pumpThemed(tester, tabs());
    final context = tester.element(find.text('Library'));
    final scheme = Theme.of(context).colorScheme;
    final colors = LibraryColors.of(context);
    expect(colorOf(tester, 'Library'), scheme.onSurface);
    expect(colorOf(tester, '29'), colors.muted);
    expect(colorOf(tester, 'Discover'), colors.muted);
    expect(colorOf(tester, '112'), colors.placeholder);
  });

  testWidgets('each tab is an equal third and 48 dp tall', (tester) async {
    await pumpThemed(tester, tabs());
    final sizes = [
      for (final label in ['Library', 'Discover', 'All'])
        tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        ),
    ];
    for (final size in sizes) {
      expect(size.width, moreOrLessEquals(320 / 3));
      expect(size.height, 48);
    }
  });

  testWidgets('a label too wide at a large text size shrinks to fit', (
    tester,
  ) async {
    await pumpThemed(tester, tabs(textScale: 2));
    expect(tester.takeException(), isNull);
    final tab = tester.getRect(
      find.ancestor(of: find.text('Discover'), matching: find.byType(InkWell)),
    );
    expect(tester.getRect(find.text('Discover')).left, greaterThan(tab.left));
    expect(tester.getRect(find.text('112')).right, lessThan(tab.right));
  });
}
