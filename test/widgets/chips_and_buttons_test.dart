import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/app_buttons.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/underline_tabs.dart';

import '../helpers/pump.dart';

void main() {
  testWidgets('PillChip is 44 px tall, reports taps and selection', (
    tester,
  ) async {
    var taps = 0;
    await pumpThemed(
      tester,
      Center(
        child: PillChip(
          label: 'Movies',
          selected: true,
          dotColor: Colors.amber,
          onTap: () => taps++,
        ),
      ),
    );
    expect(tester.getSize(find.byType(PillChip)).height, 44);
    expect(isSelected(tester, find.text('Movies')), isTrue);
    await tester.tap(find.text('Movies'));
    expect(taps, 1);
  });

  testWidgets('ChoiceChips are 32 px tall with a 48 px touch area, the '
      'selected one filled and the others outlined', (tester) async {
    String? picked;
    await pumpThemed(
      tester,
      Center(
        child: ChoiceChips<String>(
          options: const [
            ChoiceChipOption('a', 'Artists'),
            ChoiceChipOption('b', 'Albums'),
          ],
          selected: 'a',
          onChanged: (v) => picked = v,
        ),
      ),
    );
    final albums = find.widgetWithText(PillChip, 'Albums');
    expect(tester.getSize(albums).height, 32);
    expect(tester.getSize(find.byType(ChoiceChips<String>)).height, 48);
    expect(tester.widget<PillChip>(albums).selected, isFalse);
    expect(
      tester
          .widget<PillChip>(find.widgetWithText(PillChip, 'Artists'))
          .selected,
      isTrue,
    );
    // A tap 7 px below the chip is inside its touch area.
    final bottom = tester.getBottomLeft(albums);
    await tester.tapAt(bottom + const Offset(20, 7));
    expect(picked, 'b');
  });

  testWidgets('StatusChips start with All and word the statuses for the '
      'type', (tester) async {
    EntryStatus? picked = EntryStatus.want;
    await pumpThemed(
      tester,
      StatusChips(
        type: MediaType.books,
        selected: EntryStatus.done,
        onChanged: (s) => picked = s,
      ),
    );
    final labels = tester
        .widgetList<PillChip>(find.byType(PillChip))
        .map((c) => c.label)
        .toList();
    expect(labels, ['All', 'Want', 'Reading', 'Done', 'DNF']);
    await tester.tap(find.text('All'));
    expect(picked, isNull);
  });

  testWidgets('ScrollingTabs underline the selected tab in its own color', (
    tester,
  ) async {
    int? picked;
    await pumpThemed(
      tester,
      ScrollingTabs<int>(
        tabs: const [
          ScrollingTabOption(0, 'Home'),
          ScrollingTabOption(
            1,
            'Movies',
            dotColor: Colors.amber,
            lineColor: Colors.amber,
          ),
        ],
        selected: 1,
        onChanged: (v) => picked = v,
      ),
    );
    await tester.pumpAndSettle();
    final movies = tester.widget<ScrollingTab>(
      find.widgetWithText(ScrollingTab, 'Movies'),
    );
    expect(movies.selected, isTrue);
    expect(movies.lineColor, Colors.amber);
    expect(
      tester
          .widget<ScrollingTab>(find.widgetWithText(ScrollingTab, 'Home'))
          .selected,
      isFalse,
    );
    expect(tester.getSize(find.byType(ScrollingTab).first).height, 48);
    // Each tab is at least 48 px wide with half the gap on either side.
    expect(
      tester.getSize(find.byType(ScrollingTab).first).width,
      greaterThanOrEqualTo(48),
    );
    // The line spans the dot and the label exactly, 3 px tall and 4 px
    // under the label's line box, well above the tab's bottom edge.
    final tab = find.widgetWithText(ScrollingTab, 'Movies');
    final line = tester.getRect(
      find.descendant(of: tab, matching: find.byKey(ScrollingTab.lineKey)),
    );
    final content = tester.getRect(
      find.descendant(of: tab, matching: find.byType(Row)).first,
    );
    expect(line.left, content.left);
    expect(line.right, content.right);
    expect(line.height, 3);
    expect(line.top, content.bottom + 4);
    expect(line.bottom, lessThan(tester.getRect(tab).bottom));
    // No hairline under the row.
    expect(
      find.descendant(
        of: find.byType(ScrollingTabs<int>),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).border != null,
        ),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Home'));
    expect(picked, 0);
  });

  testWidgets('TagChip shows a hash before the name', (tester) async {
    await pumpThemed(tester, const TagChip('horror'));
    expect(find.text('#horror'), findsOneWidget);
  });

  testWidgets('destructive buttons use red text on the grey outline', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      Column(
        children: [
          AppButton(
            label: 'Delete',
            kind: AppButtonKind.destructive,
            onPressed: () {},
          ),
          AppButton(
            label: 'Cancel',
            kind: AppButtonKind.outline,
            onPressed: () {},
          ),
          AppButton(label: 'Save', onPressed: () {}),
        ],
      ),
    );
    final context = tester.element(find.text('Delete'));
    final colors = LibraryColors.of(context);
    final delete = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Delete'),
    );
    final style = delete.style!;
    // No fill: the grey outline from the theme and red text.
    expect(style.backgroundColor?.resolve({}), isNull);
    expect(style.foregroundColor!.resolve({}), colors.dangerText);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Save')).height,
      48,
    );
    expect(find.byType(OutlinedButton), findsNWidgets(2));
  });
}
