import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/entry/entry_header.dart';
import 'package:library_app/features/library/cover_grid_tile.dart';
import 'package:library_app/features/library/entry_list_body.dart';
import 'package:library_app/features/library/home_sections.dart';
import 'package:library_app/features/library/larger_cover.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/library/series_row.dart';
import 'package:library_app/features/music/music_type_body.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/theme/app_theme.dart';
import 'package:library_app/widgets/cover_choice.dart';
import 'package:library_app/widgets/cover_image.dart';
import 'package:library_app/widgets/cover_placeholder.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/sample_library.dart';

/// A title the fake lookup has no cover for.
final gatto = mummy.copyWith(
  id: 'movies/gatto',
  title: 'Gatto',
  released: const Released(2027),
  status: EntryStatus.want,
);

final rooster = Entry(
  id: 'music/rooster-alice-in-chains',
  type: MediaType.music,
  title: 'Rooster',
  released: const Released(1992),
  creator: 'Alice in Chains',
  album: 'Dirt',
  status: EntryStatus.done,
  added: DateTime(2026, 1, 16),
  kind: EntryKind.song,
);

final show = mummy.copyWith(
  id: 'shows/thrones',
  type: MediaType.shows,
  title: 'Thrones',
  released: null,
  seasons: const [
    Season(season: 1, released: Released(2011, 4, 17)),
    Season(season: 2, released: Released(2019, 4, 14)),
  ],
);

/// Three parts of one series, and enough movies around them for the list
/// to fold them into one row.
final panda = [
  for (final (i, year) in [2008, 2011, 2016].indexed)
    mummy.copyWith(
      id: 'movies/panda-${i + 1}',
      title: 'Kung Fu Panda${i == 0 ? '' : ' ${i + 1}'}',
      released: Released(year),
      added: DateTime(2026, 9, 10 - i),
      series: Series(name: 'Kung Fu Panda', number: i + 1),
    ),
];

List<Entry> filler(int count) => [
  for (var i = 0; i < count; i++)
    mummy.copyWith(
      id: 'movies/m$i',
      title: 'Movie $i',
      released: Released(1950 + i ~/ 2),
      added: DateTime(2026, 1, 1).add(Duration(days: i)),
    ),
];

void main() {
  /// The haptics asked of the platform.
  final haptics = <Object?>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ProviderContainer> pumpList(
    WidgetTester tester,
    List<Entry> entries, {
    EntryView view = EntryView.text,
    bool groupSeries = false,
    Brightness brightness = Brightness.dark,
    LibrarySort sort = LibrarySort.newestAdded,
  }) async {
    final container = await pumpApp(
      lookupOverrides: fakeLookupOverrides(
        source: FakeLookupSource(noMatches: const {'gatto'}),
      ),
      tester,
      Theme(
        data: buildTheme(brightness: brightness),
        child: Scaffold(
          body: EntryListBody(
            entries: sortEntries(entries, sort),
            sort: sort,
            view: view,
            color: Colors.amber,
            onTap: (_) {},
            groupSeries: groupSeries,
            today: DateTime(2026, 10, 10),
          ),
        ),
      ),
      library: Library(entries: entries),
    );
    return container;
  }

  final view = find.byType(LargerCoverView);

  for (final listView in EntryView.values) {
    testWidgets('a long press on a title in the ${listView.name} view opens '
        'its cover large: the name, the second line and Change cover, with '
        'a short vibration', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpList(tester, [mummy, show], view: listView);
      await tester.longPress(find.text('The Mummy').last);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpAndSettle();
      expect(haptics, hasLength(1));

      expect(view, findsOneWidget);
      expect(find.bySemanticsLabel('Cover'), findsOneWidget);
      final cover = tester.widget<CoverImage>(
        find.descendant(of: view, matching: find.byType(CoverImage)),
      );
      expect(cover.entry.id, mummy.id);
      // 2:3, two thirds of the screen wide.
      expect(cover.width, moreOrLessEquals(360 * 260 / 390, epsilon: 0.01));
      expect(
        find.descendant(of: view, matching: find.text('The Mummy')),
        findsWidgets,
      );
      expect(find.descendant(of: view, matching: find.text('1999')), findsOne);
      expect(find.text('No cover yet.'), findsNothing);
      expect(find.text('Add a cover'), findsNothing);

      // The button closes the view and opens Pick a cover; never the long
      // press itself.
      expect(find.text('Pick a cover'), findsNothing);
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();
      expect(view, findsNothing);
      expect(find.text('Pick a cover'), findsOneWidget);
      expect(find.textContaining('Only the cover changes.'), findsOneWidget);
    });
  }

  testWidgets('a show says its years and seasons, and the grid tile under '
      'it the years only', (tester) async {
    await pumpList(tester, [mummy, show], view: EntryView.grid);
    final tile = find.ancestor(
      of: find.text('Thrones').last,
      matching: find.byType(CoverGridTile),
    );
    expect(
      find.descendant(of: tile, matching: find.text('2011–2019')),
      findsOneWidget,
    );
    await tester.longPress(find.text('Thrones').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: view, matching: find.text('2011–2019 · 2 seasons')),
      findsOneWidget,
    );
  });

  testWidgets('it is dark in the light theme too', (tester) async {
    await pumpList(tester, [mummy], brightness: Brightness.light);
    expect(
      Theme.of(tester.element(find.text('The Mummy'))).brightness,
      Brightness.light,
    );
    await tester.longPress(find.text('The Mummy'));
    await tester.pumpAndSettle();
    final button = tester.element(find.text('Change cover'));
    expect(Theme.of(button).brightness, Brightness.dark);
    final route = ModalRoute.of(button)! as RawDialogRoute<Object?>;
    expect(route.barrierColor, LibraryColors.dark.scrim.withValues(alpha: 0.9));
  });

  testWidgets('a tap outside, the close button, Back and a swipe down close '
      'it; a tap on the cover does not', (tester) async {
    await pumpList(tester, [mummy]);
    Future<void> open() async {
      await tester.longPress(find.text('The Mummy'));
      await tester.pumpAndSettle();
      expect(view, findsOneWidget);
    }

    await open();
    await tester.tap(
      find.descendant(of: view, matching: find.byType(CoverImage)),
    );
    await tester.pumpAndSettle();
    expect(view, findsOneWidget);
    await tester.tapAt(const Offset(20, 740));
    await tester.pumpAndSettle();
    expect(view, findsNothing);

    await open();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(view, findsNothing);

    await open();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(view, findsNothing);

    await open();
    // A short pull lets go; a long one closes.
    await tester.drag(view, const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(view, findsOneWidget);
    await tester.drag(view, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(view, findsNothing);

    await open();
    await tester.fling(view, const Offset(0, 60), 1500);
    await tester.pumpAndSettle();
    expect(view, findsNothing);
  });

  testWidgets('a title with no cover: the placeholder, "No cover yet." and '
      'Add a cover, which opens Pick a cover', (tester) async {
    await pumpList(tester, [mummy, gatto]);
    await tester.longPress(find.text('Gatto'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: view, matching: find.byType(CoverPlaceholder)),
      findsOneWidget,
    );
    expect(find.text('Not released yet'), findsWidgets);
    expect(find.text('No cover yet.'), findsOneWidget);
    expect(find.text('Change cover'), findsNothing);
    await tester.tap(find.text('Add a cover'));
    await tester.pumpAndSettle();
    expect(view, findsNothing);
    expect(find.text('Pick a cover'), findsOneWidget);
  });

  testWidgets('a pick from Change cover is saved at once', (tester) async {
    final container = await pumpList(tester, [mummy]);
    await tester.longPress(find.text('The Mummy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change cover'));
    await tester.pumpAndSettle();
    final choices = tester
        .widgetList<CoverChoice>(find.byType(CoverChoice))
        .where((choice) => !choice.picked)
        .toList();
    expect(choices, isNotEmpty);
    choices.first.onTap();
    await tester.pumpAndSettle();
    final library = await container.read(libraryRepositoryProvider).load();
    expect(library.entryById(mummy.id)!.coverFrom, isNotNull);
  });

  for (final listView in EntryView.values) {
    testWidgets('a series in the ${listView.name} view: the cover that '
        'stands for it and Choose series cover; a tap on a part marks it, '
        'unmarks the one before and closes the sheet', (tester) async {
      final entries = [...filler(150), ...panda];
      final container = await pumpList(
        tester,
        entries,
        view: listView,
        groupSeries: true,
      );
      final row = listView == EntryView.grid
          ? find.byType(SeriesGridTile)
          : find.byType(SeriesGroupRow);
      expect(row, findsOneWidget);
      await tester.longPress(row);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Series cover'), findsOneWidget);
      CoverImage shown() => tester.widget<CoverImage>(
        find.descendant(of: view, matching: find.byType(CoverImage)),
      );
      expect(shown().entry.id, 'movies/panda-1');
      expect(
        find.descendant(of: view, matching: find.text('Kung Fu Panda')),
        findsWidgets,
      );
      expect(
        find.descendant(of: view, matching: find.text('3 movies · 2008–2016')),
        findsOneWidget,
      );

      await tester.tap(find.text('Choose series cover'));
      await tester.pumpAndSettle();
      expect(
        find.text('The cover that stands for Kung Fu Panda in lists.'),
        findsOneWidget,
      );
      expect(find.text('Done'), findsNothing);
      // The parts in the library, in series order, part 1 ringed.
      List<CoverChoice> choices() =>
          tester.widgetList<CoverChoice>(find.byType(CoverChoice)).toList();
      expect(
        [for (final choice in choices()) choice.title],
        ['Kung Fu Panda', 'Kung Fu Panda 2', 'Kung Fu Panda 3'],
      );
      expect(
        [for (final choice in choices()) choice.picked],
        [true, false, false],
      );
      // The sheet is dark like the view under it.
      expect(
        Theme.of(tester.element(find.byType(CoverChoice).first)).brightness,
        Brightness.dark,
      );

      Future<Map<String, bool?>> marks() async {
        final library = await container.read(libraryRepositoryProvider).load();
        return {
          for (final part in panda)
            part.id: library.entryById(part.id)!.series!.cover,
        };
      }

      await tester.tap(find.byType(CoverChoice).at(2));
      await tester.pumpAndSettle();
      expect(find.byType(CoverChoice), findsNothing);
      expect(view, findsOneWidget);
      expect(shown().entry.id, 'movies/panda-3');
      expect(await marks(), {
        'movies/panda-1': null,
        'movies/panda-2': null,
        'movies/panda-3': true,
      });

      // Another pick moves the mark.
      await tester.tap(find.text('Choose series cover'));
      await tester.pumpAndSettle();
      expect(
        [for (final choice in choices()) choice.picked],
        [false, false, true],
      );
      await tester.tap(find.byType(CoverChoice).at(1));
      await tester.pumpAndSettle();
      expect(shown().entry.id, 'movies/panda-2');
      expect(await marks(), {
        'movies/panda-1': null,
        'movies/panda-2': true,
        'movies/panda-3': null,
      });
    });
  }

  for (final listView in EntryView.values) {
    testWidgets('a song in the ${listView.name} view shows its album\'s '
        'cover, square, and opens the song\'s own picker', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: SongList(
            songs: [rooster],
            view: listView,
            color: Colors.amber,
            onTap: (_) {},
          ),
        ),
        library: Library(entries: [dirt, rooster]),
      );
      await tester.longPress(find.text('Rooster').last);
      await tester.pumpAndSettle();
      final cover = tester.widget<CoverImage>(
        find.descendant(of: view, matching: find.byType(CoverImage)),
      );
      expect(cover.entry.id, rooster.id);
      expect(cover.width, moreOrLessEquals(360 * 290 / 390, epsilon: 0.01));
      expect(tester.getSize(find.byWidget(cover)).aspectRatio, 1);
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Rooster uses its album’s cover.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('a home row and a search result open it on a long press', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => HomeRow(
            HomeRowData(mummy),
            onLongPress: () => showLargerCover(context, mummy),
          ),
        ),
      ),
      library: Library(entries: [mummy]),
    );
    await tester.longPress(find.text('The Mummy'));
    await tester.pumpAndSettle();
    expect(find.text('Change cover'), findsOneWidget);
  });

  testWidgets('a tap on the cover in details opens the same view', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Scaffold(body: EntryHeader(entry: mummy, showCover: true)),
      library: Library(entries: [mummy]),
    );
    await tester.tap(
      find.bySemanticsLabel(
        'The Mummy, cover. Tap to see it larger and change it',
      ),
    );
    await tester.pumpAndSettle();
    expect(view, findsOneWidget);
    expect(find.text('Change cover'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('nothing overflows at text scale $scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpList(tester, [gatto]);
      await tester.longPress(find.text('Gatto'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add a cover'), findsOneWidget);
      expect(
        tester.getRect(find.text('Add a cover')).bottom,
        lessThanOrEqualTo(780),
      );
    });
  }
}
