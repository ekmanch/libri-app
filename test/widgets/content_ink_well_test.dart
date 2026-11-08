import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/widgets/content_ink_well.dart';

void main() {
  Future<Rect> inkRect(WidgetTester tester, {required bool marked}) async {
    const content = SizedBox(width: 60, height: 20);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: ContentInkWell(
              onTap: () {},
              child: SizedBox(
                width: 100,
                height: 48,
                child: Center(
                  child: marked ? const InkBounds(child: content) : content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final well = tester.widget<ContentInkWell>(find.byType(ContentInkWell));
    final box = tester.renderObject<RenderBox>(find.byType(ContentInkWell));
    return well.getRectCallback(box)();
  }

  testWidgets('the ink hugs the marked content, padded', (tester) async {
    // The 60 x 20 content sits at (20, 14) in the 100 x 48 control.
    expect(
      await inkRect(tester, marked: true),
      const Rect.fromLTRB(20 - 12, 14 - 6.0, 80 + 12, 34 + 6.0),
    );
  });

  testWidgets('without InkBounds the ink fills the control', (tester) async {
    expect(
      await inkRect(tester, marked: false),
      const Rect.fromLTWH(0, 0, 100, 48),
    );
  });

  testWidgets('a tap outside the ink still counts', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: ContentInkWell(
              onTap: () => taps++,
              child: const SizedBox(
                width: 100,
                height: 48,
                child: Center(
                  child: InkBounds(child: SizedBox(width: 20, height: 20)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(2, 2));
    expect(taps, 1);
  });
}
