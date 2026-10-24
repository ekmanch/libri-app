import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/widgets/row_ink_well.dart';

void main() {
  testWidgets('the press highlight is rounded and reaches past the row', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 300,
                height: 56,
                child: RowInkWell(onTap: () => taps++),
              ),
            ),
          ),
        ),
      ),
    );

    final press = await tester.startGesture(
      tester.getCenter(find.byType(RowInkWell)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final ink = tester.allRenderObjects.firstWhere(
      (o) => o.runtimeType.toString() == '_RenderInkFeatures',
    );
    // The row spans 20..320; the ink 8 dp more on each side.
    expect(
      ink,
      paints..rrect(
        rrect: RRect.fromLTRBR(12, 20, 328, 76, const Radius.circular(12)),
      ),
    );
    await press.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('the touch area stays the row', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 300,
                height: 56,
                child: RowInkWell(onTap: () => taps++),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(14, 48));
    expect(taps, 0);
  });
}
