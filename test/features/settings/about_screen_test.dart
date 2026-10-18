import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/features/settings/about_screen.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/widgets/libri_logo.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('shows the icon, the name, the version and build, and the '
      'licenses row', (tester) async {
    await pumpApp(tester, const AboutScreen());
    expect(find.text('About'), findsOneWidget);
    expect(find.byType(LibriLogo), findsOneWidget);
    expect(find.text('Libri'), findsOneWidget);
    expect(find.text('Version 0.1.0 (build 1)'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
    expect(find.text('DATA SOURCES'), findsOneWidget);
  });

  testWidgets('credits every lookup source, TMDB with its logo and sentence', (
    tester,
  ) async {
    await pumpApp(tester, const AboutScreen());
    for (final name in [
      'TMDB',
      'IGDB',
      'Google Books',
      'Open Library',
      'Deezer',
      'AniList',
    ]) {
      await tester.scrollUntilVisible(find.text(name), 200);
      expect(find.text(name), findsOneWidget, reason: name);
      expect(find.bySemanticsLabel('$name, opens website'), findsOneWidget);
    }
    // Wikipedia is not a source, so it is not credited.
    expect(find.text('Wikipedia'), findsNothing);
    await tester.scrollUntilVisible(find.text('TMDB'), -200);
    expect(
      find.textContaining(
        'This product uses the TMDB API but is not endorsed or certified '
        'by TMDB.',
      ),
      findsOneWidget,
    );
    final logo = tester.widget<Image>(find.byType(Image));
    expect((logo.image as AssetImage).assetName, 'assets/logos/tmdb.png');
    expect(logo.height, 26);
  });

  testWidgets('tapping a source opens its website', (tester) async {
    final opened = <Uri>[];
    await pumpApp(tester, AboutScreen(openUrl: (url) async => opened.add(url)));
    await tester.tap(find.text('TMDB'));
    await tester.scrollUntilVisible(find.text('AniList'), 200);
    await tester.tap(find.text('AniList'));
    expect(opened.map((u) => u.toString()), [
      'https://www.themoviedb.org',
      'https://anilist.co',
    ]);
  });

  testWidgets('Open-source licenses opens the license page', (tester) async {
    await pumpApp(tester, const AboutScreen());
    await tester.tap(find.text('Open-source licenses'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
  });

  testWidgets('the light theme and a large text size render without '
      'overflow', (tester) async {
    await pumpApp(
      tester,
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: AboutScreen(),
      ),
      prefs: const DisplayPreferences(themeMode: ThemeMode.light),
    );
    await tester.scrollUntilVisible(find.text('AniList'), 200);
    expect(tester.takeException(), isNull);
  });
}
