import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/iso_languages.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/settings/language_picker_sheet.dart';

import '../../helpers/pump_app.dart';

class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showLanguagePicker(context),
        child: const Text('Open'),
      ),
    ),
  );
}

void main() {
  /// The fixture, with Japanese among its Languages tags.
  Library library() {
    final fixture = loadFixture();
    return fixture.copyWith(
      tags: {
        ...fixture.tags,
        TagCategory.languages: const ['japanese'],
      },
    );
  }

  Future<Future<AppSettings> Function()> open(
    WidgetTester tester, {
    AppSettings? settings,
    List<String> systemLanguages = const ['sv-SE', 'en-US'],
  }) async {
    final container = await pumpApp(
      tester,
      const _Opener(),
      library: library(),
      settings: settings,
      lookupOverrides: fakeLookupOverrides(systemLanguages: systemLanguages),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => container.read(libraryRepositoryProvider).loadSettings();
  }

  /// Whether the All languages row carries the check.
  bool checked(WidgetTester tester, String code) => tester
      .widget<LanguageRow>(find.byKey(ValueKey('language-$code')))
      .checked;

  /// The sheet's own scrollable, not the search field's.
  final list = find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: find.byType(Scrollable),
  );

  test('suggested: the phone\'s languages, then the library\'s Languages '
      'tags, each once', () {
    final library = Library(
      tags: const {
        TagCategory.languages: ['japanese', 'swedish', 'klingon'],
      },
    );
    final suggested = suggestedLanguages(['sv-SE', 'en', 'sv'], library);
    expect(suggested.map((c) => c.language.code), ['sv', 'en', 'ja']);
    expect(suggested.map((c) => c.why), ['Phone', 'Phone', 'In your library']);
    expect(suggestedLanguages([], null), isEmpty);
  });

  testWidgets('lists Suggested and All languages with both names; a tap '
      'toggles; the last one stays; Done closes', (tester) async {
    final settings = await open(tester);
    expect(find.text('Languages you read'), findsOneWidget);
    expect(find.text('SUGGESTED'), findsOneWidget);
    expect(find.text('ALL LANGUAGES'), findsOneWidget);
    // Swedish and English are the phone's, and chosen by default.
    expect(find.text('Svenska · Phone'), findsOneWidget);
    expect(checked(tester, 'sv'), isTrue);
    expect(checked(tester, 'en'), isTrue);
    // The fixture's library tags Japanese among others.
    expect(find.text('日本語 · In your library'), findsOneWidget);
    expect(checked(tester, 'ja'), isFalse);

    await tester.tap(find.byKey(const ValueKey('suggested-ja')));
    await tester.pumpAndSettle();
    expect((await settings()).languages, ['en', 'ja', 'sv']);
    expect(checked(tester, 'ja'), isTrue);

    await tester.tap(find.byKey(const ValueKey('suggested-sv')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('suggested-ja')));
    await tester.pumpAndSettle();
    expect((await settings()).languages, ['en']);
    // The last one cannot be unticked.
    await tester.tap(find.byKey(const ValueKey('suggested-en')));
    await tester.pumpAndSettle();
    expect((await settings()).languages, ['en']);
    expect(checked(tester, 'en'), isTrue);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePickerSheet), findsNothing);
  });

  testWidgets('a search matches both names, in one Matches group, or says '
      'there is no such language', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'türkç');
    await tester.pumpAndSettle();
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.text('SUGGESTED'), findsNothing);
    expect(find.text('Turkish'), findsOneWidget);
    expect(find.text('Türkçe'), findsOneWidget);
    expect(find.text('Turkmen'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Turk');
    await tester.pumpAndSettle();
    expect(find.text('Turkish'), findsOneWidget);
    // "Türkmençe" matches too.
    expect(find.text('Turkmen'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Klingon');
    await tester.pumpAndSettle();
    expect(find.text(LanguagePickerSheet.noMatch), findsOneWidget);
  });

  testWidgets('every ISO language is listed', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-zu')),
      400,
      scrollable: list,
    );
    expect(find.text('Zulu'), findsOneWidget);
    expect(isoLanguage('zu')!.ownName, 'isiZulu');
  });
}
