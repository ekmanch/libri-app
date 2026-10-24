import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_providers.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/features/entry/platform_picker_sheet.dart';
import 'package:library_app/widgets/chips.dart';

import '../../helpers/pump_app.dart';

const GamePlatform _snes = (
  id: 19,
  name: 'Super Nintendo',
  aka: ['SNES', 'Super Nintendo Entertainment System'],
);
const GamePlatform _pc = (id: 6, name: 'PC', aka: ['mswin']);
const GamePlatform _switch = (id: 130, name: 'Switch', aka: ['NX']);

Entry _game(String title, String? platform) => Entry(
  id: 'games/$title',
  type: MediaType.games,
  title: title,
  status: EntryStatus.done,
  added: DateTime(2026, 1, 1),
  platform: platform,
);

class _Opener extends StatelessWidget {
  const _Opener({this.pick = false, this.platform});

  final bool pick;
  final String? platform;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            if (!pick) {
              await openNewEntryScreen(context, type: MediaType.games);
              return;
            }
            final match = await openMatchPicker(
              context,
              type: MediaType.games,
              title: 'Street Fighter II',
              platform: platform,
            );
            if (match != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Picked ${match.source} on ${match.searchedPlatform}',
                  ),
                ),
              );
            }
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  group('helpers', () {
    test('a platform is found by its name or any other name, case aside', () {
      final all = [_pc, _snes, _switch];
      expect(platformNamed(all, 'Super Nintendo'), _snes);
      expect(platformNamed(all, 'super nintendo entertainment system'), _snes);
      expect(platformNamed(all, 'snes'), _snes);
      expect(platformNamed(all, 'Nintendo Switch'), _switch);
      expect(platformNamed(all, 'Amiga'), isNull);

      expect(platformMatches(_snes, 'snes'), isTrue);
      expect(platformMatches(_snes, 'entertainment'), isTrue);
      expect(platformMatches(_snes, 'genesis'), isFalse);
      expect(platformMatches(_snes, ''), isTrue);
    });

    test('your platforms: the default first, then the most used, each once '
        'and only those the lookup lists', () {
      final all = [_pc, _snes, _switch];
      expect(
        yourPlatforms(
          all,
          defaultPlatform: 'Switch',
          entries: [
            _game('a', 'PC'),
            _game('b', 'SNES, PC'),
            _game('c', 'Super Nintendo'),
            _game('d', 'Amiga'),
            _game('e', 'Nintendo Switch'),
            Entry(
              id: 'movies/x',
              type: MediaType.movies,
              title: 'x',
              status: EntryStatus.done,
              added: DateTime(2026),
              platform: 'PC',
            ),
          ],
        ),
        [_switch, _pc, _snes],
      );
      expect(yourPlatforms(all), isEmpty);
    });
  });

  /// Types, waits out the debounce and settles.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(PlatformChip),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the platform chip shows for games only and narrows the '
      'search, with the year on that platform', (tester) async {
    final container = await pumpApp(tester, const _Opener());
    final fake =
        container.read(lookupSourcesProvider).single as FakeLookupSource;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await type(tester, 'Super Street Fighter II');
    expect(find.text('GAME · 1994'), findsOneWidget);
    expect(find.text('Platform'), findsOneWidget);

    await openPicker(tester);
    expect(find.text('ANY'), findsOneWidget);
    expect(find.text('Any platform'), findsOneWidget);
    expect(find.text('YOUR PLATFORMS'), findsOneWidget);
    expect(find.text('ALL PLATFORMS'), findsOneWidget);
    // PC is the default from Settings, then the fixture's PlayStation 5
    // and Switch; PC shows again under All platforms.
    expect(find.text('PC'), findsNWidgets(2));
    expect(find.text('Switch'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).last, 'genesis');
    await tester.pumpAndSettle();
    expect(find.text('MATCHES'), findsOneWidget);
    expect(find.text('Sega Mega Drive/Genesis'), findsOneWidget);
    expect(find.text('PC'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'dreamcast');
    await tester.pumpAndSettle();
    expect(find.text('No platform called that.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'genesis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sega Mega Drive/Genesis'));
    await tester.pumpAndSettle();

    expect(
      fake.calls.last,
      'search:super street fighter ii:Sega Mega Drive/Genesis',
    );
    expect(
      find.bySemanticsLabel('Platform: Sega Mega Drive/Genesis'),
      findsOneWidget,
    );
    // Out on the Mega Drive the same year, with two other platforms.
    expect(find.text('GAME · 1994'), findsOneWidget);
    expect(
      find.text('Capcom · Sega Mega Drive/Genesis and 2 more'),
      findsOneWidget,
    );

    await openPicker(tester);
    await tester.enterText(find.byType(TextField).last, 'wii');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wii'));
    await tester.pumpAndSettle();
    expect(find.text('GAME · 2011'), findsOneWidget);
    expect(find.text('Capcom · Wii and 2 more'), findsOneWidget);

    await openPicker(tester);
    await tester.enterText(find.byType(TextField).last, 'snes');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Super Nintendo'));
    await tester.pumpAndSettle();
    await type(tester, 'The Last of Us');
    expect(
      find.text('No games called that on Super Nintendo.'),
      findsOneWidget,
    );

    // The cross goes back to any platform.
    await tester.tap(find.byTooltip('Any platform'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Platform: Any'), findsOneWidget);
    expect(find.text('GAME · 2013'), findsOneWidget);

    // Other types have no platform chip.
    final all = find.widgetWithText(PillChip, 'All');
    await tester.dragUntilVisible(
      all,
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Platform: Any'), findsNothing);
  });

  testWidgets('a match found on a platform picks it in the form', (
    tester,
  ) async {
    await pumpApp(tester, const _Opener());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await type(tester, 'Street Fighter II');
    await openPicker(tester);
    await tester.enterText(find.byType(TextField).last, 'snes');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Super Nintendo'));
    await tester.pumpAndSettle();
    expect(find.text('GAME · 1992'), findsNWidgets(1));
    await tester.tap(find.text('Street Fighter II').last);
    await tester.pumpAndSettle();
    expect(find.text('New entry'), findsOneWidget);
    final snes = find.widgetWithText(PillChip, 'Super Nintendo');
    await tester.scrollUntilVisible(
      snes,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<PillChip>(snes).selected, isTrue);
    // PC, the default, is not among its platforms, so it is not picked.
    expect(find.widgetWithText(PillChip, 'PC'), findsNothing);
  });

  testWidgets('"Look up again" starts on the entry\'s first platform', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      const _Opener(pick: true, platform: 'SNES'),
    );
    final fake =
        container.read(lookupSourcesProvider).single as FakeLookupSource;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Platform: Super Nintendo'), findsOneWidget);
    expect(fake.calls, contains('search:street fighter ii:Super Nintendo'));
    // The Games chip, past the screen edge, is scrolled into view.
    final games = tester.getRect(find.widgetWithText(PillChip, 'Games'));
    expect(games.left, greaterThanOrEqualTo(0));
    expect(games.right, lessThanOrEqualTo(360));
    await tester.tap(find.text('Super Street Fighter II'));
    await tester.pumpAndSettle();
    expect(find.text('Picked igdb:322188 on Super Nintendo'), findsOneWidget);
  });

  testWidgets('a platform the lookup does not list, or no list, searches '
      'every platform', (tester) async {
    await pumpApp(tester, const _Opener(pick: true, platform: 'Amiga'));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Platform: Any'), findsOneWidget);
    expect(find.text('GAME · 1991'), findsOneWidget);
  });

  testWidgets('the picker says when the platforms could not be had', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const _Opener(),
      lookupOverrides: fakeLookupOverrides(failure: LookupFailure.offline),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await openPicker(tester);
    expect(
      find.text(
        'Could not load the platforms. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  test('a searched platform is part of a match and survives copyWith', () {
    const match = LookupMatch(
      type: MediaType.games,
      title: 'x',
      source: 'igdb:1',
    );
    final on = match.copyWith(searchedPlatform: 'Super Nintendo');
    expect(on.searchedPlatform, 'Super Nintendo');
    expect(on == match, isFalse);
    expect(on.copyWith(creator: 'Capcom').searchedPlatform, 'Super Nintendo');
  });
}
