import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/release_dates.dart';
import 'package:library_app/features/settings/about_screen.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/language_picker_sheet.dart';
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
      Future<AppSettings> settings() =>
          container.read(libraryRepositoryProvider).loadSettings();

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
      expect((await settings()).timelineDefault, isTrue);
      expect(
        find.textContaining('place entries on a timeline'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(find.text('GAMES'), 150);
      expect(find.textContaining('themed artwork'), findsOneWidget);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect((await settings()).seasonalThemeDefault, isFalse);
      // The list's extent is re-measured on the rebuild (the test font is
      // wide), so the row may have left the viewport: scroll back to it.
      await tester.scrollUntilVisible(
        find.textContaining('all look the same'),
        -150,
      );
      expect(find.textContaining('all look the same'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('None'), 200);
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect((await settings()).defaultPlatform, isNull);
      await tester.ensureVisible(find.text('Steam Deck'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Steam Deck'));
      await tester.pumpAndSettle();
      expect((await settings()).defaultPlatform, 'Steam Deck');
    },
  );

  testWidgets('Books lists the languages read as chips, the last one not '
      'removable, and + Add language opens the sheet', (tester) async {
    final container = await pumpApp(tester, const SettingsScreen());
    Future<AppSettings> settings() =>
        container.read(libraryRepositoryProvider).loadSettings();
    await tester.scrollUntilVisible(find.text('BOOKS'), 150);
    expect(find.text('Languages you read'), findsOneWidget);
    expect(find.text(SettingsScreen.languagesHelp), findsOneWidget);
    // The fake phone speaks Swedish and English.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Swedish'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove Swedish'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Remove Swedish'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Remove Swedish'));
    await tester.pumpAndSettle();
    expect((await settings()).languages, ['en']);
    expect(find.text('Swedish'), findsNothing);
    // The last one has no cross and is no button.
    expect(find.bySemanticsLabel('Remove English'), findsNothing);
    expect(find.text('English'), findsOneWidget);

    await tester.ensureVisible(find.bySemanticsLabel('Add language'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add language'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePickerSheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'turk');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-tr')));
    await tester.pumpAndSettle();
    expect((await settings()).languages, ['en', 'tr']);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePickerSheet), findsNothing);
    expect(find.text('Turkish'), findsOneWidget);
  });

  testWidgets('Movies picks the release dates shown, with a help line per '
      'pick', (tester) async {
    final container = await pumpApp(tester, const SettingsScreen());
    Future<AppSettings> settings() =>
        container.read(libraryRepositoryProvider).loadSettings();
    await tester.scrollUntilVisible(find.text('Release dates'), 150);
    await tester.pumpAndSettle();
    expect(find.text('MOVIES'), findsOneWidget);
    expect(isSelected(tester, find.text('Both')), isTrue);
    expect(
      find.text(SettingsScreen.releaseDatesHelp(ReleaseDates.both)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Digital'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Digital'));
    await tester.pumpAndSettle();
    expect((await settings()).releaseDates, ReleaseDates.digital);
    expect(isSelected(tester, find.text('Digital')), isTrue);
    expect(
      find.text(SettingsScreen.releaseDatesHelp(ReleaseDates.digital)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Cinema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cinema'));
    await tester.pumpAndSettle();
    expect((await settings()).releaseDates, ReleaseDates.cinema);
    expect(find.textContaining('opens in cinemas'), findsOneWidget);
  });

  testWidgets('a single row puts its value at the right edge', (tester) async {
    await pumpApp(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 300);
    // Both rows open a screen, so the value ends right before the chevron,
    // which sits at the row's right edge.
    for (final (label, value) in [
      ('Library source', 'GitHub, private repo'),
      ('Libri', 'Version 0.1.0'),
    ]) {
      final row = find.widgetWithText(SettingRow, label);
      final chevron = tester.getRect(
        find.descendant(of: row, matching: find.byType(StrokeIcon)),
      );
      expect(chevron.right, tester.getRect(row).right, reason: label);
      expect(tester.getRect(find.text(value)).right, chevron.left - 6);
    }
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

  testWidgets('the Libri row opens About', (tester) async {
    await pumpApp(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Version 0.1.0'), 200);
    await tester.ensureVisible(find.text('Libri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libri'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
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
