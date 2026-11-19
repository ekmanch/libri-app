import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/app_icons.dart';
import 'package:library_app/widgets/cached_image.dart';
import 'package:library_app/widgets/check_box_mark.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/entry_row.dart';
import 'package:library_app/widgets/section_heading.dart';
import 'package:library_app/widgets/type_kicker.dart';

import '../helpers/pump.dart';

// The light theme's rule (DESIGN.md section 11): colors are fills, text is
// neutral. Each test checks the light side and that dark is as it was.
void main() {
  const pink = Color(0xFFF74F9E);
  final tint = AccentColors.mix(pink, AccentColors.tintStrength);
  final half = AccentColors.mix(pink, AccentColors.tickStrength);
  const darkGray = Color(0xFF2F343B);

  Color? textColor(WidgetTester tester, String text) {
    final widget = tester.widget<Text>(find.text(text));
    return widget.style?.color;
  }

  Material chipMaterial(WidgetTester tester, Type chip) => tester.widget(
    find.descendant(of: find.byType(chip), matching: find.byType(Material)),
  );

  BoxDecoration boxOf(WidgetTester tester, Finder finder) =>
      tester
              .widget<Container>(
                find.descendant(of: finder, matching: find.byType(Container)),
              )
              .decoration!
          as BoxDecoration;

  for (final brightness in Brightness.values) {
    final light = brightness == Brightness.light;
    final name = brightness.name;

    testWidgets('$name: a selected status chip and an active filter chip', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        Column(
          children: [
            PillChip(label: 'Done', selected: true, onTap: () {}),
            RemovableChip(label: 'Movies', onRemove: () {}),
          ],
        ),
        brightness: brightness,
      );
      final expected = light ? tint : LibraryColors.dark.selectedFill;
      expect(chipMaterial(tester, PillChip).color, expected);
      expect(chipMaterial(tester, RemovableChip).color, expected);
    });

    testWidgets('$name: a tick box, ticked and empty', (tester) async {
      await pumpThemed(
        tester,
        const Column(
          children: [
            CheckBoxMark(key: Key('on'), checked: true, round: true),
            CheckBoxMark(key: Key('off'), checked: false),
          ],
        ),
        brightness: brightness,
      );
      final on = boxOf(tester, find.byKey(const Key('on')));
      final off = boxOf(tester, find.byKey(const Key('off')));
      expect(on.shape, BoxShape.circle);
      if (light) {
        // Half strength, a white empty box, both raised.
        expect(on.color, half);
        expect(off.color, const Color(0xFFFFFFFF));
        expect(on.boxShadow, isNotEmpty);
        expect(off.boxShadow, on.boxShadow);
        expect((off.border! as Border).top.width, 1);
      } else {
        expect(on.color, Accents.hotPink.fill);
        expect(off.color, const Color(0x00000000));
        expect(on.boxShadow, isEmpty);
        expect((off.border! as Border).top.width, 2);
        expect(
          (off.border! as Border).top.color,
          LibraryColors.dark.placeholder,
        );
      }
    });

    testWidgets('$name: the Done check and an outlined badge', (tester) async {
      await pumpThemed(
        tester,
        const Row(
          children: [StatusMark(EntryStatus.done), OutlineBadge('New season')],
        ),
        brightness: brightness,
      );
      final expected = light ? darkGray : Accents.hotPink.fill;
      final check = tester.widget<StrokeIcon>(find.byType(StrokeIcon));
      expect(check.color, expected);
      expect(textColor(tester, 'New season'), expected);
    });

    testWidgets('$name: a type kicker and a type heading', (tester) async {
      await pumpThemed(
        tester,
        Column(
          children: [
            const TypeKicker(
              'MOVIE · 2024',
              type: MediaType.movies,
              style: TextStyle(fontSize: 12),
            ),
            const SectionHeading('Movies', type: MediaType.movies),
            const SectionHeading('Recently added'),
          ],
        ),
        brightness: brightness,
      );
      final colors = light ? LibraryColors.light : LibraryColors.dark;
      final dots = tester.widgetList<TypeDot>(find.byType(TypeDot)).toList();
      if (light) {
        // A dot in the type's color beside neutral words.
        expect(dots, hasLength(2));
        expect(dots.every((d) => d.color == const Color(0xFFFFC400)), isTrue);
        expect(textColor(tester, 'MOVIE · 2024'), colors.muted);
        expect(textColor(tester, 'MOVIES'), const Color(0xFF17181B));
      } else {
        expect(dots, isEmpty);
        expect(textColor(tester, 'MOVIE · 2024'), colors.movies);
        expect(textColor(tester, 'MOVIES'), colors.movies);
      }
      // A plain heading is the heading gray on both.
      expect(textColor(tester, 'RECENTLY ADDED'), colors.muted);
    });

    testWidgets('$name: the hash of a tag', (tester) async {
      await pumpThemed(
        tester,
        const Center(child: TagChip('horror')),
        brightness: brightness,
      );
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(TagChip),
          matching: find.byType(RichText),
        ),
      );
      expect(rich.text.toPlainText(), '#horror');
      Color? hash;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '#') hash = span.style?.color;
        return true;
      });
      expect(hash, light ? const Color(0xFF9AA0A8) : null);
    });

    testWidgets('$name: a cover is lifted by the shadow for its size', (
      tester,
    ) async {
      Widget cover(double width) => CachedImage(
        url: null,
        width: width,
        height: width * 1.5,
        placeholder: const ColoredBox(color: Colors.blueGrey),
        borderRadius: BorderRadius.circular(8),
      );
      await pumpThemed(
        tester,
        Row(children: [cover(40), const SizedBox(width: 20), cover(110)]),
        brightness: brightness,
      );
      final lifted = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(CachedImage),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).boxShadow)
          .toList();
      if (light) {
        expect(lifted, [
          LibraryColors.light.smallCoverShadow,
          LibraryColors.light.coverShadow,
        ]);
      } else {
        expect(lifted, isEmpty);
      }
    });
  }
}
