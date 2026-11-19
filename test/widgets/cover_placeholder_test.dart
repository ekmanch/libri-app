import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/cover_placeholder.dart';

import '../helpers/pump_app.dart';

Future<void> pumpCover(WidgetTester tester, Widget cover) => pumpApp(
  tester,
  Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(key: const Key('cover'), child: cover),
    ),
  ),
);

void main() {
  test('the palette is the mockup’s eight colors, in its order, in every '
      'theme', () {
    const palette = [
      Color(0xFF4B5F8A),
      Color(0xFF8A6E3F),
      Color(0xFF3F6B8A),
      Color(0xFF6B4B8A),
      Color(0xFF8A553F),
      Color(0xFF3F8A6E),
      Color(0xFF8A3F5F),
      Color(0xFF5F6B3F),
    ];
    expect(LibraryColors.dark.coverPlaceholders, palette);
    expect(LibraryColors.light.coverPlaceholders, palette);
  });

  test('an id picks its color as the desktop app does', () {
    Color color(String id) =>
        CoverPlaceholder.baseColor(LibraryColors.dark, id);
    // 'm' is 109 and '1' is 49: 109 × 3 + 49 × 4 = 523, and 523 % 8 = 3.
    expect(CoverPlaceholder.paletteIndex('m1', 8), 3);
    expect(color('m1'), const Color(0xFF6B4B8A));
    expect(color('movies/the-mummy-1999'), const Color(0xFF6B4B8A));
    expect(color('music/dirt-alice-in-chains'), const Color(0xFF8A3F5F));
    expect(CoverPlaceholder.paletteIndex('', 8), 0);
  });

  testWidgets('the base color with an elliptical highlight at the top left '
      'and a fade to dark at the bottom', (tester) async {
    // 'e' is 101: 101 × 3 = 303, and 303 % 8 = 7, the last color.
    const id = 'e';
    expect(
      CoverPlaceholder.baseColor(LibraryColors.dark, id),
      const Color(0xFF5F6B3F),
    );
    await pumpCover(
      tester,
      const CoverPlaceholder(id: id, type: MediaType.movies, width: 100),
    );
    expect(tester.getSize(find.byType(CoverPlaceholder)), const Size(100, 150));

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('cover')),
    );
    late ByteData bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      image.dispose();
    });
    // The red channel at a point of the 100 × 150 cover.
    int red(int x, int y) => bytes.getUint8((y * 100 + x) * 4);
    const base = 0x5F;
    // White over the base at [alpha].
    double lit(double alpha) => base + (255 - base) * alpha;

    // No layer reaches the middle of the left half.
    expect(red(50, 62), closeTo(base, 1));
    // The highlight is strongest at 20% along the top edge: white at 16%.
    expect(red(20, 0), closeTo(lit(0.16), 3));
    // Half its strength is 39 px to the right (0.3 of the 130 px radius)
    // and 31.5 px down (0.3 of the 105 px radius): an ellipse, wider than
    // it is tall. A circle would be as strong 39 px down as 39 px right;
    // here it has faded further there.
    expect(red(59, 0), closeTo(lit(0.08), 2));
    expect(red(20, 31), closeTo(lit(0.08), 2));
    expect(red(20, 39), closeTo(lit(0.16 * (1 - 39.5 / 105 / 0.6)), 1.5));
    expect(red(20, 39), lessThan(red(59, 0) - 2));
    // Gone at 60% of the radii: 78 px right, 63 px down. (The corner
    // itself is rounded off.)
    expect(red(99, 12), closeTo(base, 1));
    expect(red(20, 64), closeTo(base, 1));
    // The fade starts at 45% of the height and ends at black 42%.
    expect(red(50, 67), closeTo(base, 1));
    expect(red(50, 149), closeTo(base * (1 - 0.42), 3));
    expect(red(50, 108), closeTo(base * (1 - 0.42 * (108.5 - 67.5) / 82.5), 3));
  });

  testWidgets('a small cover has no text; a grid cover its title, above the '
      'series badge; a large one the title and the creator', (tester) async {
    await pumpCover(
      tester,
      const CoverPlaceholder(
        id: 'm1',
        type: MediaType.movies,
        width: 40,
        title: 'The Mummy',
        creator: 'Stephen Sommers',
      ),
    );
    expect(find.byType(Text), findsNothing);

    await pumpCover(
      tester,
      const CoverPlaceholder(
        id: 'm1',
        type: MediaType.movies,
        width: 100,
        title: 'The Mummy',
        creator: 'Stephen Sommers',
        text: CoverPlaceholderText.title,
      ),
    );
    expect(find.text('Stephen Sommers'), findsNothing);
    final title = tester.widget<Text>(find.text('The Mummy'));
    expect(title.maxLines, 3);
    expect(title.style!.color, const Color(0xFFFFFFFF));
    expect(title.style!.fontWeight, FontWeight.w700);
    final cover = tester.getRect(find.byType(CoverPlaceholder));
    final plain = tester.getRect(find.text('The Mummy'));
    expect(plain.left, cover.left + 8);
    expect(plain.bottom, cover.bottom - 8);

    await pumpCover(
      tester,
      const CoverPlaceholder(
        id: 'm1',
        type: MediaType.movies,
        width: 100,
        title: 'The Mummy',
        text: CoverPlaceholderText.title,
        badgeBelow: true,
      ),
    );
    // The badge is 22 tall, 6 from the bottom, with 5 between it and the
    // title.
    expect(tester.getRect(find.text('The Mummy')).bottom, cover.bottom - 33);

    await pumpCover(
      tester,
      const CoverPlaceholder(
        id: 'm1',
        type: MediaType.movies,
        width: 84,
        title: 'The Mummy',
        creator: 'Stephen Sommers',
        text: CoverPlaceholderText.titleAndCreator,
      ),
    );
    final creator = tester.widget<Text>(find.text('Stephen Sommers'));
    expect(
      creator.style!.fontSize,
      lessThan(tester.widget<Text>(find.text('The Mummy')).style!.fontSize!),
    );
    expect(
      tester.getTopLeft(find.text('Stephen Sommers')).dy,
      greaterThan(tester.getBottomLeft(find.text('The Mummy')).dy),
    );
  });

  testWidgets('the longest title at the largest text fits a square cover', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final (text, badge) in [
      (CoverPlaceholderText.title, true),
      (CoverPlaceholderText.titleAndCreator, false),
    ]) {
      await pumpCover(
        tester,
        CoverPlaceholder(
          id: 'm1',
          type: MediaType.music,
          width: 72,
          title: 'A very long title that will not fit on three whole lines',
          creator: 'A creator with a long name',
          text: text,
          badgeBelow: badge,
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
