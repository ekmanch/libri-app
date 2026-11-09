import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_providers.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/music_results.dart';
import 'package:library_app/features/entry/new_entry_screen.dart';
import 'package:library_app/widgets/chips.dart';
import 'package:library_app/widgets/segmented_control.dart';
import 'package:library_app/widgets/underline_tabs.dart';

import '../../helpers/pump_app.dart';

/// Opens Add / edit entry › New entry on Music, or with [pick] "Look up
/// again" for an album or a song.
class _Opener extends StatelessWidget {
  const _Opener({this.title, this.pick});
  final String? title;
  final EntryKind? pick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            if (pick case final kind?) {
              final match = await openMatchPicker(
                context,
                type: MediaType.music,
                title: title ?? '',
                kind: kind,
              );
              if (match != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Picked ${match.source}')),
                );
              }
              return;
            }
            await openNewEntryScreen(
              context,
              type: MediaType.music,
              title: title,
            );
          },
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  Future<FakeLookupSource> open(
    WidgetTester tester, {
    String? title = 'ghost',
    EntryKind? pick,
    LookupFailure? failure,
  }) async {
    final container = await pumpApp(
      tester,
      _Opener(title: title, pick: pick),
      lookupOverrides: fakeLookupOverrides(failure: failure),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container.read(lookupSourcesProvider).single as FakeLookupSource;
  }

  Finder scopeChip(String label) => find.widgetWithText(PillChip, label);

  bool selected(WidgetTester tester, String label) =>
      tester.widget<PillChip>(scopeChip(label)).selected;

  Future<void> pickScope(WidgetTester tester, String label) async {
    await tester.tap(scopeChip(label));
    await tester.pumpAndSettle();
  }

  /// The list of the page in view.
  Finder list() => find
      .descendant(
        of: find.byType(MusicResults),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .hitTestable();

  /// The music calls the fake got.
  List<String> music(FakeLookupSource fake) => [
    for (final call in fake.calls)
      if (call.startsWith('music:')) call,
  ];

  testWidgets('the type row is underline tabs, with the Albums | Songs '
      'chips under them for music only', (tester) async {
    await open(tester);
    expect(find.byType(ScrollingTabs<MediaType?>), findsOneWidget);
    expect(
      tester
          .widget<ScrollingTab>(find.widgetWithText(ScrollingTab, 'Music'))
          .selected,
      isTrue,
    );
    expect(selected(tester, 'Albums'), isTrue);
    expect(selected(tester, 'Songs'), isFalse);
    // The Library's small status chips: 32 dp.
    expect(
      tester
          .getSize(
            find.descendant(
              of: scopeChip('Albums'),
              matching: find.byType(InkWell),
            ),
          )
          .height,
      32,
    );
    expect(
      tester.getTopLeft(scopeChip('Albums')).dy,
      greaterThan(tester.getBottomLeft(find.byType(ScrollingTab).first).dy - 1),
    );

    // Tabs past the screen edge are not built until scrolled to.
    final anime = find.widgetWithText(ScrollingTab, 'Anime');
    await tester.dragUntilVisible(
      anime,
      find.descendant(
        of: find.byType(ScrollingTabs<MediaType?>),
        matching: find.byType(ListView),
      ),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(anime);
    await tester.pumpAndSettle();
    expect(scopeChip('Albums'), findsNothing);
    expect(find.byType(MusicResults), findsNothing);
  });

  testWidgets('a search leads with the matching artists and counts the '
      'whole list; the switch lists songs', (tester) async {
    final fake = await open(tester);
    expect(find.text('ARTISTS'), findsOneWidget);
    expect(find.text('Artist · 38 albums'), findsOneWidget);
    expect(find.text('Ghostface Killah'), findsOneWidget);
    expect(find.text('Ghostemane'), findsOneWidget);
    expect(find.text('All albums'), findsNWidgets(3));
    expect(find.text('412 albums'), findsOneWidget);
    expect(find.text('IS IT ONE OF THESE?'), findsNothing);
    expect(find.text('Not listed?'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Impera'),
      100,
      scrollable: list(),
    );
    expect(find.text('ALBUM · 2025'), findsOneWidget);
    expect(find.text('Skeletá'), findsOneWidget);
    // Square 56 dp covers.
    expect(MusicRow.coverSize, 56);
    expect(music(fake), ['music:albums:ghost:0']);

    await pickScope(tester, 'Songs');
    expect(selected(tester, 'Songs'), isTrue);
    expect(find.text('2,960 songs'), findsOneWidget);
    expect(find.text('All songs'), findsNWidgets(3));
    await tester.scrollUntilVisible(
      find.text('Justin Bieber · Justice'),
      100,
      scrollable: list(),
    );
    expect(find.text('SONG · 2021'), findsOneWidget);
    expect(music(fake), ['music:albums:ghost:0', 'music:songs:ghost:0']);
  });

  testWidgets('swiping the results sideways flips the switch', (tester) async {
    await open(tester);
    await tester.fling(list(), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected(tester, 'Songs'), isTrue);
    expect(find.text('2,960 songs'), findsOneWidget);
    await tester.fling(list(), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected(tester, 'Albums'), isTrue);
    expect(find.text('412 albums'), findsOneWidget);
  });

  testWidgets('the next page of 25 is asked near the end of the list, not '
      'before', (tester) async {
    final fake = await open(tester);
    expect(music(fake), ['music:albums:ghost:0']);
    // Rows 8 on are generated: "Ghost Notes, Vol. 1" is the eighth.
    await tester.scrollUntilVisible(
      find.text('Ghost Notes, Vol. 5'),
      100,
      scrollable: list(),
    );
    expect(music(fake), ['music:albums:ghost:0']);
    await tester.scrollUntilVisible(
      find.text('Ghost Notes, Vol. 18'),
      100,
      scrollable: list(),
    );
    await tester.pumpAndSettle();
    expect(music(fake), ['music:albums:ghost:0', 'music:albums:ghost:25']);
    await tester.scrollUntilVisible(
      find.text('Ghost Notes, Vol. 30'),
      100,
      scrollable: list(),
    );
    expect(find.text('Ghost Notes, Vol. 30'), findsOneWidget);
  });

  testWidgets('"Loading more…" shows while the next page is on its way', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const _Opener(title: 'ghost'),
      lookupOverrides: fakeLookupOverrides(
        latency: const Duration(milliseconds: 300),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('412 albums'), findsOneWidget);
    await tester.drag(list(), const Offset(0, -1800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(list(), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Loading more…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Loading more…'), findsNothing);
    // The covers of the new rows come with the same latency.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets("an artist's row lists only theirs, newest first, and the "
      'switch keeps working inside', (tester) async {
    final fake = await open(tester);
    await tester.tap(find.text('Artist · 38 albums'));
    await tester.pumpAndSettle();
    expect(find.text('All results for “ghost”'), findsOneWidget);
    expect(find.text('Ghost · 38 albums, newest first'), findsOneWidget);
    expect(find.text('ARTISTS'), findsNothing);
    expect(find.text('ALBUM · 2025'), findsOneWidget);
    expect(find.text('EP · 2023'), findsOneWidget);
    expect(find.text('Phantomime'), findsOneWidget);
    // An album inside an artist has no line under its title.
    expect(
      find.descendant(of: find.byType(MusicRow), matching: find.text('Ghost')),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.text('SINGLE · 2019'),
      100,
      scrollable: list(),
    );
    expect(music(fake).last, 'music:albums:fake:artist:ghost:0');

    await pickScope(tester, 'Songs');
    expect(find.text('All results for “ghost”'), findsOneWidget);
    expect(find.text('Ghost · 39 songs, newest first'), findsOneWidget);
    expect(find.text('Satanized'), findsOneWidget);
    // A song inside an artist names its album only.
    expect(
      find.descendant(
        of: find.widgetWithText(MusicRow, 'Satanized'),
        matching: find.text('Skeletá'),
      ),
      findsOneWidget,
    );
    expect(music(fake).last, 'music:songs:fake:artist:ghost:0');

    await tester.tap(find.text('All results for “ghost”'));
    await tester.pumpAndSettle();
    expect(find.text('2,960 songs'), findsOneWidget);
    expect(find.text('ARTISTS'), findsOneWidget);
  });

  testWidgets('Back from an artist returns to the results before it '
      'leaves the page', (tester) async {
    await open(tester);
    await tester.tap(find.text('Ghostemane'));
    await tester.pumpAndSettle();
    expect(find.text('Ghostemane · 45 albums, newest first'), findsOneWidget);
    // The system gesture.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('412 albums'), findsOneWidget);
    expect(find.byType(NewEntryScreen), findsOneWidget);

    await tester.tap(find.text('Ghostemane'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('412 albums'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(NewEntryScreen), findsNothing);
  });

  testWidgets('typing other words leaves the artist', (tester) async {
    await open(tester);
    await tester.tap(find.text('Ghostemane'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hounds');
    await tester.pump(NewEntryScreen.debounce);
    await tester.pumpAndSettle();
    expect(find.textContaining('All results for'), findsNothing);
    expect(find.text('1 album'), findsOneWidget);
    expect(find.text('Hounds of Love'), findsOneWidget);
    expect(find.text('Kate Bush'), findsOneWidget);
  });

  testWidgets('"Fill in the details myself" keeps the switch\'s choice', (
    tester,
  ) async {
    await open(tester, title: 'Unlisted');
    expect(find.text('No albums called that.'), findsOneWidget);
    await pickScope(tester, 'Songs');
    expect(find.text('No songs called that.'), findsOneWidget);
    await tester.tap(find.text('Fill in the details myself'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedControl<EntryKind>>(
            find.byType(SegmentedControl<EntryKind>),
          )
          .selected,
      EntryKind.song,
    );
    expect(find.widgetWithText(TextField, 'Unlisted'), findsOneWidget);
  });

  testWidgets('a song picked from Songs makes a song', (tester) async {
    final fake = await open(tester);
    await pickScope(tester, 'Songs');
    await tester.scrollUntilVisible(
      find.text('Justin Bieber · Justice'),
      100,
      scrollable: list(),
    );
    await tester.tap(find.text('Justin Bieber · Justice'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('details:fake:track:justin-bieber-ghost'));
    expect(
      tester
          .widget<SegmentedControl<EntryKind>>(
            find.byType(SegmentedControl<EntryKind>),
          )
          .selected,
      EntryKind.song,
    );
    expect(find.widgetWithText(TextField, 'Justin Bieber'), findsOneWidget);
  });

  testWidgets('"Look up again" on a song opens on Songs and hands the '
      'pick back', (tester) async {
    final fake = await open(tester, pick: EntryKind.song);
    expect(find.text('Look up again'), findsOneWidget);
    expect(selected(tester, 'Songs'), isTrue);
    expect(find.text('2,960 songs'), findsOneWidget);
    expect(music(fake), ['music:songs:ghost:0']);
    expect(find.text('Fill in the details myself'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Justin Bieber · Justice'),
      100,
      scrollable: list(),
    );
    await tester.tap(find.text('Justin Bieber · Justice'));
    await tester.pumpAndSettle();
    expect(find.text('Picked fake:track:justin-bieber-ghost'), findsOneWidget);
  });

  testWidgets('"Look up again" on an album opens on Albums', (tester) async {
    await open(tester, pick: EntryKind.album);
    expect(selected(tester, 'Albums'), isTrue);
  });

  testWidgets('offline says so and offers to try again', (tester) async {
    await open(tester, failure: LookupFailure.offline);
    expect(
      find.text(
        'Could not reach the lookup. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Not listed?'), findsNothing);
    expect(find.text('Fill in the details myself'), findsOneWidget);
  });
}
