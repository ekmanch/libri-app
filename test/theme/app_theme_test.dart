import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/media_type.dart';
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

  test('dark uses the one accent for fills, text and icons', () {
    final dark = buildTheme(brightness: Brightness.dark);
    final accent = dark.extension<AccentColors>()!;
    expect(dark.colorScheme.primary, Accents.hotPink.fill);
    expect(dark.colorScheme.primaryContainer, Accents.hotPink.fill);
    expect(accent.full, Accents.hotPink.fill);
    expect(accent.tint, Accents.hotPink.fill);
    expect(accent.tick, Accents.hotPink.fill);
    expect(accent.link, Accents.hotPink.fill);
    expect(accent.selection, LibraryColors.dark.selectedFill);
    expect(accent.tickShadow, isEmpty);
  });

  test('light works three strengths out of the light accent, text neutral', () {
    final light = buildTheme(brightness: Brightness.light);
    final accent = light.extension<AccentColors>()!;
    // Hot pink's light value, #F74F9E.
    expect(Accents.hotPink.light, const Color(0xFFF74F9E));
    expect(light.colorScheme.primary, const Color(0xFFF74F9E));
    expect(accent.full, const Color(0xFFF74F9E));
    // 50 % on white for a ticked box, 20 % on white (the tint) for
    // selections and main buttons, as the canvas rounds them.
    expect(accent.tick.toARGB32(), 0xFFFBA7CF);
    expect(accent.tint.toARGB32(), 0xFFFDDCEC);
    expect(light.colorScheme.primaryContainer, accent.tint);
    expect(accent.selection, accent.tint);
    expect(accent.onTint, const Color(0xFF17181B));
    expect(accent.link, const Color(0xFF2F343B));
    expect(accent.tickShadow, isNotEmpty);
    expect(accent.boxFill, const Color(0xFFFFFFFF));
  });

  test('every accent has a light value, shown by the theme in light', () {
    for (final option in Accents.all) {
      expect(option.of(Brightness.dark), option.fill);
      expect(option.of(Brightness.light), option.light);
      final theme = buildTheme(brightness: Brightness.light, accent: option);
      expect(theme.colorScheme.primary, option.light, reason: option.id);
    }
    expect(Accents.byId('vivid/Amber')!.light, const Color(0xFFFFB300));
    expect(Accents.byId('pastel/Green')!.light, const Color(0xFF40A02B));
  });

  test('light type colors are bright fills; dark ones are unchanged', () {
    const light = LibraryColors.light, dark = LibraryColors.dark;
    expect(light.typeColorsAreFills, isTrue);
    expect(dark.typeColorsAreFills, isFalse);
    expect(light.movies, const Color(0xFFFFC400));
    expect(light.shows, const Color(0xFF0A84FF));
    expect(light.books, const Color(0xFF34C759));
    expect(light.games, const Color(0xFFFF5A4F));
    expect(light.anime, const Color(0xFFF74F9E));
    expect(light.music, const Color(0xFFAF52DE));
    expect(dark.movies, const Color(0xFFF2B544));
    expect(dark.music, const Color(0xFFC4A7FF));
    // A heading in a type's list: the type color on dark, gray on light.
    expect(light.typeHeading(MediaType.movies), light.muted);
    expect(dark.typeHeading(MediaType.movies), dark.movies);
    // Covers are lifted on light only, small ones by the smaller shadow.
    expect(dark.coverShadowFor(40), isEmpty);
    expect(light.coverShadowFor(40), light.smallCoverShadow);
    expect(light.coverShadowFor(110), light.coverShadow);
  });

  test('a seasonal color replaces every accent strength, light too', () {
    final theme = buildTheme(
      brightness: Brightness.light,
      seasonal: SeasonalAccents.halloween,
    );
    expect(theme.colorScheme.primary, SeasonalAccents.halloween);
    expect(theme.colorScheme.primaryContainer, SeasonalAccents.halloween);
    final accent = theme.extension<AccentColors>()!;
    expect(accent.tick, SeasonalAccents.halloween);
    expect(accent.link, SeasonalAccents.halloween);
    expect(accent.selection, LibraryColors.light.selectedFill);
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
