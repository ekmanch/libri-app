import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/theme/app_theme.dart';

void main() {
  test('accent ids are unique and resolvable', () {
    final ids = Accents.all.map((a) => a.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(Accents.byId('vivid/Hot pink'), Accents.hotPink);
    expect(Accents.byId('pastel/Blue')?.group, AccentGroup.pastel);
    expect(Accents.byId('nope'), isNull);
    expect(Accents.vivid.length, 5);
    expect(Accents.pastel.length, 10);
  });

  test('dark uses the accent fill for text, light uses the ink', () {
    final dark = buildTheme(brightness: Brightness.dark);
    final light = buildTheme(brightness: Brightness.light);
    expect(dark.colorScheme.primary, Accents.hotPink.fill);
    expect(light.colorScheme.primary, Accents.hotPink.ink);
    expect(dark.colorScheme.primaryContainer, Accents.hotPink.fill);
    expect(light.colorScheme.primaryContainer, Accents.hotPink.fill);
  });

  test('a seasonal color replaces both accent slots', () {
    final theme = buildTheme(
      brightness: Brightness.light,
      seasonal: SeasonalAccents.halloween,
    );
    expect(theme.colorScheme.primary, SeasonalAccents.halloween);
    expect(theme.colorScheme.primaryContainer, SeasonalAccents.halloween);
  });

  test('titles are Figtree ExtraBold, tightened; body is Figtree', () {
    final theme = buildTheme(brightness: Brightness.dark);
    for (final style in [
      theme.textTheme.headlineLarge,
      theme.textTheme.headlineMedium,
      theme.textTheme.headlineSmall,
      theme.textTheme.titleLarge,
    ]) {
      expect(style?.fontFamily, 'Figtree');
      expect(style?.fontWeight, FontWeight.w800);
      expect(style?.letterSpacing, -0.03 * style!.fontSize!);
    }
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Figtree');
    expect(theme.textTheme.bodyMedium?.fontWeight, isNot(FontWeight.w800));
    expect(theme.textTheme.headlineLarge?.fontSize, 34);
  });
}
