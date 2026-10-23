import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/library/series_groups.dart';
import 'package:library_app/features/library/series_row.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/app_icons.dart';
import 'package:library_app/widgets/cover_image.dart';

import '../../helpers/sample_library.dart';

/// [count] movies spread over the decades from 1950 on, two per year.
List<Entry> longList(int count) => [
  for (var i = 0; i < count; i++)
    mummy.copyWith(
      id: 'movies/m$i',
      title: 'Movie $i',
      released: Released(1950 + i ~/ 2),
      added: DateTime(2026, 1, 1).add(Duration(days: i)),
    ),
];

Future<void> pumpBody(
  WidgetTester tester,
  List<Entry> entries, {
  LibrarySort sort = LibrarySort.yearNewest,
  EntryView view = EntryView.text,
  bool groupSeries = false,
  void Function(SeriesGroup group)? onTapSeries,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    // The covers in the grid need the (fake) lookups and image cache.
    ProviderScope(
      overrides: fakeLookupOverrides(),
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: EntryListBody(
            entries: sortEntries(entries, sort),
            sort: sort,
            view: view,
            color: Colors.amber,
            onTap: (_) {},
            onTapSeries: onTapSeries,
            groupSeries: groupSeries,
            today: DateTime(2026, 10, 10),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The two Lord of the Rings movies, added after every entry of [longList],
/// so they lead the newest-added order.
final lotr = [
  mummy.copyWith(
    id: 'movies/fellowship',
    title: 'The Lord of the Rings: The Fellowship of the Ring',
    released: const Released(2001),
    status: EntryStatus.done,
    added: DateTime(2026, 9, 2),
    series: const Series(name: 'The Lord of the Rings', number: 1),
  ),
  mummy.copyWith(
    id: 'movies/towers',
    title: 'The Lord of the Rings: The Two Towers',
    released: const Released(2002),
    status: EntryStatus.want,
    added: DateTime(2026, 9, 1),
    series: const Series(name: 'The Lord of the Rings', number: 2),
  ),
];

void main() {
  testWidgets('a short list has no headers and no rail', (tester) async {
    await pumpBody(tester, longList(12));
    expect(find.byKey(EntryListBody.railKey), findsNothing);
    expect(find.text('1950s'), findsNothing);
    expect(find.text('Movie 0'), findsOneWidget);
  });

  testWidgets('one section never gets a rail, however long', (tester) async {
    final sameDecade = [
      for (var i = 0; i < 90; i++)
        mummy.copyWith(
          id: 'movies/m$i',
          title: 'Movie $i',
          released: const Released(1999),
        ),
    ];
    await pumpBody(tester, sameDecade);
    expect(find.byKey(EntryListBody.railKey), findsNothing);
  });

  testWidgets('a long list gets decade headers and a rail that jumps', (
    tester,
  ) async {
    await pumpBody(tester, longList(150));
    expect(find.byKey(EntryListBody.railKey), findsOneWidget);
    expect(find.text('2020s'), findsOneWidget); // Decades keep their "s".
    expect(find.text('20s'), findsOneWidget);
    expect(find.text('Older'), findsOneWidget);
    expect(find.text('1990s'), findsNothing); // Far down, not built yet.

    await tester.tap(find.text('90s'));
    await tester.pumpAndSettle();
    expect(find.text('1990s'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));
    // The 1990s header sits at the top of the list.
    expect(tester.getTopLeft(find.text('1990s')).dy, lessThan(60));
  });

  testWidgets('scrolling moves the highlight to the section at the top', (
    tester,
  ) async {
    await pumpBody(tester, longList(150));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    Color? pillColor(String label) {
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return (box.decoration as BoxDecoration?)?.color;
    }

    final selected = LibraryColors.of(
      tester.element(find.byKey(EntryListBody.railKey)),
    ).selectedFill;
    expect(pillColor('20s'), selected);
    expect(pillColor('Older'), Colors.transparent);

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(pillColor('Older'), selected);
    expect(pillColor('20s'), Colors.transparent);
  });

  testWidgets('the grid keeps no headers; the thumb shows a bubble on drag', (
    tester,
  ) async {
    await pumpBody(tester, longList(150), view: EntryView.grid);
    expect(find.byType(CoverGridTile), findsWidgets);
    expect(find.byKey(EntryListBody.railKey), findsNothing);
    // No header: the only "2020s" is the bubble, hidden until scrolling.
    expect(find.text('2020s'), findsOneWidget);
    final thumb = find.byKey(EntryListBody.thumbKey);
    expect(thumb, findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(of: thumb, matching: find.byType(AnimatedOpacity))
                .first,
          )
          .opacity,
      0,
    );

    // Scrolling the grid shows the thumb and the bubble for a moment.
    await tester.drag(find.byType(CoverGridTile).first, const Offset(0, -300));
    await tester.pump();
    double bubbleOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text('2020s'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;
    expect(bubbleOpacity(), 1);
    await tester.pump(const Duration(seconds: 2)); // The hide timer runs out.
    await tester.pumpAndSettle();
    expect(bubbleOpacity(), 0);

    // Drag the thumb zone to the bottom: the list follows and the bubble
    // names the last section.
    final gesture = await tester.startGesture(const Offset(370, 30));
    await tester.pump();
    await gesture.moveTo(const Offset(370, 830)); // Past the track's end.
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);
    expect(find.text('Older'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the grid does not overflow under a larger text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpBody(tester, longList(30), view: EntryView.grid);
    expect(find.byType(CoverGridTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('series rows', () {
    testWidgets('a long list folds a series into one row, at its lead', (
      tester,
    ) async {
      SeriesGroup? tapped;
      await pumpBody(
        tester,
        [...longList(150), ...lotr],
        sort: LibrarySort.newestAdded,
        groupSeries: true,
        onTapSeries: (g) => tapped = g,
      );
      expect(find.byType(SeriesGroupRow), findsOneWidget);
      expect(find.text('The Lord of the Rings'), findsOneWidget);
      // The subtitle is rich text: the stack icon, then the words.
      expect(find.textContaining('2 movies · 2001–2002'), findsOneWidget);
      expect(find.text('1 of 2 done'), findsOneWidget);
      expect(
        find.text('The Lord of the Rings: The Fellowship of the Ring'),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          'The Lord of the Rings, series, 2 movies · 2001–2002, 1 of 2 done',
        ),
        findsOneWidget,
      );
      // The row is first: the series' newest part was added last of all.
      expect(
        tester.getTopLeft(find.byType(SeriesGroupRow)).dy,
        lessThan(tester.getTopLeft(find.text('Movie 149')).dy),
      );
      await tester.tap(find.text('The Lord of the Rings'));
      expect(tapped?.name, 'The Lord of the Rings');
      expect(tapped?.parts.length, 2);
    });

    testWidgets('all parts done: the check instead of the count', (
      tester,
    ) async {
      await pumpBody(
        tester,
        [...longList(150), lotr[0], lotr[1].copyWith(status: EntryStatus.done)],
        sort: LibrarySort.newestAdded,
        groupSeries: true,
      );
      expect(find.text('2 of 2 done'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SeriesGroupRow),
          matching: find.byWidgetPredicate(
            (w) => w is StrokeIcon && w.data == AppIcons.check,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a short list, and a list told not to, show every part', (
      tester,
    ) async {
      await pumpBody(
        tester,
        [...longList(12), ...lotr],
        sort: LibrarySort.newestAdded,
        groupSeries: true,
      );
      expect(find.byType(SeriesGroupRow), findsNothing);
      expect(
        find.text('The Lord of the Rings: The Fellowship of the Ring'),
        findsOneWidget,
      );
      expect(
        find.text('The Lord of the Rings: The Two Towers'),
        findsOneWidget,
      );

      await pumpBody(
        tester,
        [...longList(150), ...lotr],
        sort: LibrarySort.newestAdded,
        groupSeries: false,
      );
      expect(find.byType(SeriesGroupRow), findsNothing);
      expect(
        find.text('The Lord of the Rings: The Fellowship of the Ring'),
        findsOneWidget,
      );
    });

    testWidgets('one part in the library stays a plain row', (tester) async {
      await pumpBody(
        tester,
        [...longList(150), lotr[0]],
        sort: LibrarySort.newestAdded,
        groupSeries: true,
      );
      expect(find.byType(SeriesGroupRow), findsNothing);
      expect(
        find.text('The Lord of the Rings: The Fellowship of the Ring'),
        findsOneWidget,
      );
    });

    testWidgets('the list with covers and the grid show one cover with the '
        'stack badge and the count', (tester) async {
      await pumpBody(
        tester,
        [...longList(150), ...lotr],
        sort: LibrarySort.newestAdded,
        view: EntryView.listWithPhotos,
        groupSeries: true,
      );
      expect(find.byType(SeriesGroupRow), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SeriesGroupRow),
          matching: find.byType(CoverImage),
        ),
        findsOneWidget,
      );

      SeriesGroup? tapped;
      await pumpBody(
        tester,
        [...longList(150), ...lotr],
        sort: LibrarySort.newestAdded,
        view: EntryView.grid,
        groupSeries: true,
        onTapSeries: (g) => tapped = g,
      );
      expect(find.byType(SeriesGridTile), findsOneWidget);
      expect(find.text('The Lord of the Rings'), findsOneWidget);
      expect(find.text('2 movies'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'The Lord of the Rings, series, 2 movies · 2001–2002, 1 of 2 done',
        ),
        findsOneWidget,
      );
      // The cover is part 1's: the tile wraps the Fellowship's cover.
      final tile = tester.widget<SeriesGridTile>(find.byType(SeriesGridTile));
      expect(tile.group.coverEntry.id, 'movies/fellowship');
      await tester.tap(find.text('The Lord of the Rings'));
      expect(tapped?.name, 'The Lord of the Rings');
    });

    testWidgets("a marked part's cover stands for the series", (tester) async {
      await pumpBody(
        tester,
        [
          ...longList(150),
          lotr[0],
          lotr[1].copyWith(
            series: const Series(
              name: 'The Lord of the Rings',
              number: 2,
              cover: true,
            ),
          ),
        ],
        sort: LibrarySort.newestAdded,
        view: EntryView.grid,
        groupSeries: true,
      );
      final tile = tester.widget<SeriesGridTile>(find.byType(SeriesGridTile));
      expect(tile.group.coverEntry.id, 'movies/towers');
    });
  });
}
