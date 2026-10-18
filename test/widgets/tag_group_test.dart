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

  group('opening a group low in the list', () {
    Future<void> pumpGroups(WidgetTester tester, {int tagCount = 6}) {
      return pumpThemed(
        tester,
        SizedBox(height: 400, child: _Groups(tagCount: tagCount)),
      );
    }

    double listOffset(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    testWidgets('scrolls its chips into view', (tester) async {
      await pumpGroups(tester);
      await tester.ensureVisible(find.text('Group 7'));
      await tester.pumpAndSettle();
      final before = listOffset(tester);
      await tester.tap(find.text('Group 7'));
      await tester.pumpAndSettle();
      expect(listOffset(tester), greaterThan(before));
      final list = tester.getRect(find.byType(Scrollable));
      final lastChip = tester.getRect(find.text('#tag-7-5'));
      expect(lastChip.bottom, lessThanOrEqualTo(list.bottom));
      expect(
        tester.getRect(find.text('Group 7')).top,
        greaterThanOrEqualTo(list.top),
      );
    });

    testWidgets('a group taller than the list keeps its header in view', (
      tester,
    ) async {
      await pumpGroups(tester, tagCount: 40);
      await tester.ensureVisible(find.text('Group 7'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group 7'));
      await tester.pumpAndSettle();
      final list = tester.getRect(find.byType(Scrollable));
      // The header, 44 px with the label centered, sits at the top.
      final label = tester.getRect(find.text('Group 7'));
      expect(label.top, greaterThanOrEqualTo(list.top));
      expect(label.bottom, lessThanOrEqualTo(list.top + 44));
    });

    testWidgets('a group the sheet opens by itself leaves the list', (
      tester,
    ) async {
      await pumpGroups(tester);
      await tester.ensureVisible(find.text('Group 7'));
      await tester.pumpAndSettle();
      final before = listOffset(tester);
      tester.state<_GroupsState>(find.byType(_Groups)).openGroup(7);
      await tester.pumpAndSettle();
      expect(listOffset(tester), before);
    });

    testWidgets('a group already in view does not move the list', (
      tester,
    ) async {
      await pumpGroups(tester);
      await tester.tap(find.text('Group 0'));
      await tester.pumpAndSettle();
      expect(listOffset(tester), 0);
    });
  });
}

/// Eight groups in a 400 px list, one open at a time, like the filter
/// sheet.
class _Groups extends StatefulWidget {
  const _Groups({required this.tagCount});

  final int tagCount;

  @override
  State<_Groups> createState() => _GroupsState();
}

class _GroupsState extends State<_Groups> {
  int? _open;

  void openGroup(int group) => setState(() => _open = group);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var g = 0; g < 8; g++)
            TagGroup(
              label: 'Group $g',
              tags: [for (var t = 0; t < widget.tagCount; t++) 'tag-$g-$t'],
              selected: const [],
              open: _open == g,
              onToggleOpen: () => setState(() => _open = _open == g ? null : g),
              onToggleTag: (_) {},
            ),
        ],
      ),
    );
  }
}
