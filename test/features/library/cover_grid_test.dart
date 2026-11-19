import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/library/cover_grid.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/cover_image.dart';
import 'package:library_app/widgets/cover_mark.dart';

import '../../helpers/sample_library.dart';

const _long = 'A title long enough to take two lines';

/// [count] movies in title order; every title in [wrapping] (by index) is
/// long enough to wrap.
List<Entry> _movies(int count, {Set<int> wrapping = const {}}) => [
  for (var i = 0; i < count; i++)
    mummy.copyWith(
      id: 'movies/m$i',
      // Zero-padded, so title order is index order.
      title: wrapping.contains(i)
          ? '${i.toString().padLeft(3, '0')} $_long'
          : 'M${i.toString().padLeft(3, '0')}',
      released: Released(1990 + i % 30),
      status: EntryStatus.want,
    ),
];

Future<void> _pump(
  WidgetTester tester,
  List<Entry> entries, {
  Brightness brightness = Brightness.dark,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: fakeLookupOverrides(),
      child: MaterialApp(
        theme: buildTheme(brightness: brightness),
        home: Scaffold(
          body: EntryListBody(
            entries: entries,
            sort: LibrarySort.titleAz,
            view: EntryView.grid,
            color: Colors.amber,
            onTap: (_) {},
            today: DateTime(2026, 10, 10),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tile(String title) => find.ancestor(
  of: find.text(title).last,
  matching: find.byType(CoverGridTile),
);

/// The title and the second line under the cover of the tile for [title].
(Rect, Rect) _lines(WidgetTester tester, String title, String caption) {
  final tile = _tile(title);
  final texts = find.descendant(of: tile, matching: find.byType(Text));
  // The placeholder cover writes the title too; the lines under the cover
  // are the last two.
  final count = tester.widgetList(texts).length;
  return (
    tester.getRect(texts.at(count - 2)),
    tester.getRect(texts.at(count - 1)),
  );
}

void main() {
  setUp(debugClearGridMeasurements);

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('text scale $scale: the second line sits right under the '
        'title, and a row is as tall as its tallest cell', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Row 0 has no wrapping title, row 1 has one, row 2 none.
      final entries = _movies(9, wrapping: {4});
      await _pump(tester, entries);
      expect(tester.takeException(), isNull);

      final (shortTitle, shortYear) = _lines(tester, 'M003', '1993');
      final (longTitle, longYear) = _lines(tester, entries[4].title, '1994');
      // One line and two lines of title, at the text size (1.3 at most).
      // The engine rounds a line's height, which is why rows are measured
      // and not worked out from the font size.
      final titleLine = shortTitle.height;
      final unscaled = GridTileText.titleLineHeight;
      expect(
        titleLine,
        moreOrLessEquals(
          unscaled * scale.clamp(1.0, GridTileText.maxTextScale),
          epsilon: 0.5,
        ),
      );
      expect(longTitle.height, moreOrLessEquals(titleLine * 2, epsilon: 0.01));
      // The year directly under each title, so at different heights.
      expect(
        shortYear.top - shortTitle.bottom,
        moreOrLessEquals(GridTileText.captionGap, epsilon: 0.01),
      );
      expect(
        longYear.top - longTitle.bottom,
        moreOrLessEquals(GridTileText.captionGap, epsilon: 0.01),
      );
      expect(
        longYear.top - shortYear.top,
        moreOrLessEquals(titleLine, epsilon: 0.01),
      );
      // Cells are aligned at the top: covers and first lines line up.
      expect(shortTitle.top, longTitle.top);
      expect(
        tester.getTopLeft(_tile('M003')).dy,
        tester.getTopLeft(_tile(entries[4].title)).dy,
      );

      // Row 0 ends where its (one-line) cells end plus the spacing; row 1
      // is one title line taller; nothing is clipped and no sliver is left.
      final row0 = tester.getRect(_tile('M000'));
      final row1 = tester.getRect(_tile(entries[4].title));
      final row2 = tester.getRect(_tile('M006'));
      expect(row1.top - row0.bottom, moreOrLessEquals(16, epsilon: 0.01));
      expect(row2.top - row1.bottom, moreOrLessEquals(16, epsilon: 0.01));
      expect(
        row1.height - row0.height,
        moreOrLessEquals(titleLine, epsilon: 0.01),
      );
      expect(row2.height, moreOrLessEquals(row0.height, epsilon: 0.01));
    });
  }

  testWidgets('the scroll extent is exact from the first frame, so the '
      'thumb does not drift; only rows near the screen are built', (
    tester,
  ) async {
    // Wrapping titles only far down: an average of the first rows would
    // come out too short.
    final entries = _movies(
      300,
      wrapping: {for (var i = 150; i < 300; i += 3) i},
    );
    await _pump(tester, entries);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final extentAtTop = position.maxScrollExtent;

    // The same layout the list asked for (the cache hands it back).
    final spec = tester
        .widget<CoverGridSliver>(find.byType(CoverGridSliver))
        .spec;
    final layout = spec.layoutFor(390 - 40);
    expect(identical(layout, spec.layoutFor(390 - 40)), isTrue);
    expect(layout.rowCount, 100);
    expect(
      extentAtTop,
      moreOrLessEquals(
        10 + layout.height + AppShell.contentBottomPadding - 844,
        epsilon: 0.01,
      ),
    );
    // 50 rows are one title line taller than the rest.
    expect(
      layout.height,
      moreOrLessEquals(
        100 * layout.extentOf(0)! - 16 + 50 * GridTileText.titleLineHeight,
        epsilon: 0.01,
      ),
    );

    // Lazy: far fewer tiles (and so covers asked for) than entries.
    expect(tester.widgetList(find.byType(CoverImage)).length, lessThan(40));
    expect(find.text('M299'), findsNothing);

    for (final offset in [1234.0, 9000.0, position.maxScrollExtent]) {
      position.jumpTo(offset);
      await tester.pump();
      expect(position.maxScrollExtent, extentAtTop);
      expect(tester.takeException(), isNull);
    }
    // At the end the last row is on screen.
    expect(find.text('M299'), findsWidgets);
    expect(tester.widgetList(find.byType(CoverImage)).length, lessThan(40));
  });

  testWidgets('heights are measured once and again only for new titles, a '
      'new width or a new text size', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    CoverGridSpec spec(List<String> titles, {TextScaler? scaler}) {
      final text = GridTileText.of(context);
      return CoverGridSpec(
        titles: titles,
        text: scaler == null
            ? text
            : GridTileText(
                title: text.title,
                caption: text.caption,
                scaler: scaler,
                direction: text.direction,
                locale: text.locale,
              ),
        coverAspectRatio: 2 / 3,
      );
    }

    final first = spec(['One', 'Two', _long, 'Four']).layoutFor(350);
    expect(first.rowCount, 2);
    // Another list object with the same titles: the same layout.
    expect(
      identical(first, spec(['One', 'Two', _long, 'Four']).layoutFor(350)),
      isTrue,
    );
    // The first row holds the wrapping title; the last has no spacing.
    expect(
      first.extentOf(0)! - first.extentOf(1)!,
      moreOrLessEquals(16 + GridTileText.titleLineHeight, epsilon: 0.01),
    );
    expect(first.topOf(1), first.extentOf(0));
    expect(first.extentOf(2), isNull);

    final renamed = spec(['One', 'Two', 'Three', 'Four']).layoutFor(350);
    expect(identical(first, renamed), isFalse);
    expect(renamed.extentOf(0)! - renamed.extentOf(1)!, 16);

    // Narrower: "Two wor" no longer fits one line.
    final wide = spec(['Two wor']).layoutFor(350);
    final narrow = spec(['Two wor']).layoutFor(200);
    expect(narrow.tileWidth, lessThan(wide.tileWidth));
    expect(
      narrow.height - narrow.tileWidth * 1.5,
      greaterThan(wide.height - wide.tileWidth * 1.5),
    );

    final larger = spec([
      'One',
    ], scaler: const TextScaler.linear(1.3)).layoutFor(350);
    final normal = spec(['One']).layoutFor(350);
    expect(larger.height, greaterThan(normal.height + 8));
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: the Done disc and the series badge '
        'share one style', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: fakeLookupOverrides(),
          child: MaterialApp(
            theme: buildTheme(brightness: brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 110,
                  child: CoverGridTile(
                    entry: mummy,
                    seriesCount: 3,
                    done: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final marks = find.byType(CoverMark);
      expect(marks, findsNWidgets(2));
      BoxDecoration decoration(int i) =>
          tester
                  .widget<Container>(
                    find.descendant(
                      of: marks.at(i),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      final disc = decoration(0);
      final badge = decoration(1);
      expect(badge.color, disc.color);
      expect(badge.boxShadow, disc.boxShadow);
      final count = tester.widget<Text>(find.text('3'));
      if (brightness == Brightness.light) {
        // Solid white, a hairline ring and a small shadow; dark gray ink.
        expect(disc.color, const Color(0xFFFFFFFF));
        expect(disc.boxShadow, const [
          BoxShadow(color: Color(0x1F14161C), spreadRadius: 1),
          BoxShadow(
            color: Color(0x4014161C),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ]);
        expect(count.style!.color, const Color(0xFF2F343B));
      } else {
        expect(disc.color, const Color(0xD9131416));
        expect(disc.boxShadow, isEmpty);
      }
    });
  }
}
