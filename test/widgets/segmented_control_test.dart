import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/widgets/segmented_control.dart';

import '../helpers/pump.dart';

void main() {
  testWidgets('reports the tapped segment and marks the selected one', (
    tester,
  ) async {
    EntryStatus? picked;
    await pumpThemed(
      tester,
      StatusSegmentedControl(
        selected: null,
        includeAll: true,
        onChanged: (value) => picked = value,
      ),
    );
    expect(find.text('All'), findsOneWidget);
    for (final status in EntryStatus.values) {
      expect(
        find.text(
          status == EntryStatus.inProgress
              ? 'In progress'
              : status.name == 'dnf'
              ? 'DNF'
              : status.name[0].toUpperCase() + status.name.substring(1),
        ),
        findsOneWidget,
      );
    }
    expect(isSelected(tester, find.text('All')), isTrue);
    expect(isSelected(tester, find.text('Done')), isFalse);

    await tester.tap(find.text('Done'));
    expect(picked, EntryStatus.done);
  });

  testWidgets('a type words the In progress segment', (tester) async {
    await pumpThemed(
      tester,
      StatusSegmentedControl(
        selected: null,
        type: MediaType.games,
        includeAll: true,
        onChanged: (_) {},
      ),
    );
    expect(find.text('Playing'), findsOneWidget);
    expect(find.text('In progress'), findsNothing);
  });

  test('segment widths share the leftover space, or split evenly', () {
    final widths = SegmentedControl.segmentWidths(
      labels: ['All', 'In progress'],
      available: 204,
      measure: (l) => l.length * 10.0,
    );
    // Usable 200: contents 48 (46, raised to the 48 dp minimum) and 126,
    // leftover 26 shared as 13 each.
    expect(widths, [61, 139]);
    final tight = SegmentedControl.segmentWidths(
      labels: ['Abcdefghij', 'Klmnopqrst'],
      available: 104,
      measure: (l) => l.length * 10.0,
    );
    // Too long to fit: full widths, and the control scrolls.
    expect(tight, [116, 116]);
  });

  testWidgets('segments are 48 dp tall and fill the row evenly', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      SegmentedControl<int>(
        segments: const [SegmentOption(1, 'One'), SegmentOption(2, 'Two')],
        selected: 1,
        onChanged: (_) {},
      ),
    );
    final one = tester.getSize(
      find.ancestor(of: find.text('One'), matching: find.byType(InkWell)).first,
    );
    final two = tester.getSize(
      find.ancestor(of: find.text('Two'), matching: find.byType(InkWell)).first,
    );
    expect(one.height, 48);
    expect(one.width, two.width);
  });

  testWidgets('accent style fills the selected segment with the accent', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      StatusSegmentedControl(
        selected: EntryStatus.want,
        style: SegmentedStyle.accent,
        inset: true,
        onChanged: (_) {},
      ),
    );
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Want'), matching: find.byType(Material))
          .first,
    );
    final scheme = Theme.of(tester.element(find.text('Want'))).colorScheme;
    expect(material.color, scheme.primaryContainer);
  });
}
