import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/widgets/tag_group.dart';

import '../helpers/pump.dart';

void main() {
  testWidgets('a group header folds on tap with no press highlight', (
    tester,
  ) async {
    var toggles = 0;
    await pumpThemed(
      tester,
      TagGroup(
        label: 'Season',
        tags: const ['christmas', 'halloween'],
        selected: const [],
        open: false,
        onToggleOpen: () => toggles++,
        onToggleTag: (_) {},
      ),
    );
    await tester.tap(find.text('Season'));
    expect(toggles, 1);
    expect(
      find.ancestor(of: find.text('Season'), matching: find.byType(InkWell)),
      findsNothing,
    );
    // A screen reader can still open it.
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Season')),
      matchesSemantics(
        isButton: true,
        hasExpandedState: true,
        hasTapAction: true,
        label: 'Season',
      ),
    );
    handle.dispose();
  });

  testWidgets('a long group row opens on tap with no press highlight', (
    tester,
  ) async {
    var taps = 0;
    await pumpThemed(
      tester,
      TagGroupRow(label: 'Authors', detail: '64 authors', onTap: () => taps++),
    );
    await tester.tap(find.text('Authors'));
    expect(taps, 1);
    expect(
      find.ancestor(of: find.text('Authors'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });
}
