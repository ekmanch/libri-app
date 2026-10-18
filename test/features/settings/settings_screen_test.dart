import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/settings_screen.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/app_icons.dart';
import 'package:library_app/widgets/setting_row.dart';

import '../../helpers/pump.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('shows every section, the version and the current choices', (
    tester,
  ) async {
    await pumpApp(tester, const SettingsScreen());
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.text('THEME'), findsOneWidget);
    expect(find.text('ACCENT COLOR'), findsOneWidget);
    expect(find.text('Vivid'), findsOneWidget);
    expect(find.text('Pastel'), findsOneWidget);
    expect(isSelected(tester, find.text('Dark')), isTrue);
    expect(isSelected(tester, find.bySemanticsLabel('Hot pink')), isTrue);
    // The two Blues and Greens are told apart by their group.
    expect(find.bySemanticsLabel('Blue'), findsNWidgets(2));
    // The list is lazy, so scroll to the rest.
    await tester.scrollUntilVisible(find.text('GAMES'), 150);
    expect(find.text('PLANS'), findsOneWidget);
    expect(isSelected(tester, find.text('PC')), isTrue);
    await tester.scrollUntilVisible(find.text('ABOUT'), 150);
    expect(find.text('DATA'), findsOneWidget);
    expect(find.text('Libri'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
  });

  testWidgets(
    'theme, accent, plan defaults and platform change the preferences',
    (tester) async {
      final container = await pumpApp(tester, const SettingsScreen());
      DisplayPreferences prefs() => container.read(displayPreferencesProvider);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(prefs().themeMode, ThemeMode.light);

      await tester.tap(find.bySemanticsLabel('Mauve'));
      await tester.pumpAndSettle();
      expect(prefs().accent.name, 'Mauve');
      expect(prefs().accent.group, AccentGroup.pastel);
      expect(isSelected(tester, find.bySemanticsLabel('Mauve')), isTrue);
      expect(isSelected(tester, find.bySemanticsLabel('Hot pink')), isFalse);

      expect(find.textContaining('plain checklist'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(prefs().timelineDefault, isTrue);
      expect(
        find.textContaining('place entries on a timeline'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(find.text('GAMES'), 150);
      expect(find.textContaining('themed artwork'), findsOneWidget);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(prefs().seasonalThemeDefault, isFalse);
      expect(find.textContaining('all look the same'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('None'), 200);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(prefs().defaultPlatform, isNull);
      await tester.tap(find.text('Steam Deck'));
      await tester.pumpAndSettle();
      expect(prefs().defaultPlatform, 'Steam Deck');
    },
  );

  testWidgets('a single row puts its value at the right edge', (tester) async {
    await pumpApp(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    final row = tester.getRect(find.widgetWithText(SettingRow, 'Libri'));
    final value = tester.getRect(find.text('Version 0.1.0'));
    expect(value.right, row.right);
    // With a chevron the value ends right before it.
    final chevron = tester.getRect(find.byType(StrokeIcon).last);
    final source = tester.getRect(find.text('GitHub, private repo'));
    expect(source.right, chevron.left - 6);
  });

  testWidgets('the library source row opens the connection screen', (
    tester,
  ) async {
    await pumpApp(tester, const SettingsScreen());
    // Scroll past the row, so it is fully inside the short viewport.
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 200);
    await tester.tap(find.text('Library source'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.text('Library connection'), findsOneWidget);
  });

  testWidgets('the light theme renders without overflow', (tester) async {
    await pumpApp(
      tester,
      const SettingsScreen(),
      prefs: const DisplayPreferences(themeMode: ThemeMode.light),
    );
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 200);
    expect(tester.takeException(), isNull);
  });
}
