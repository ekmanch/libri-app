import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/series_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/features/entry/series.dart';
import 'package:library_app/features/library/home_sections.dart';
import 'package:library_app/features/settings/display_preferences.dart';

void main() {
  final today = DateTime(2026, 10, 28);
  setUp(() => seasonClock = () => today);
  tearDown(() => seasonClock = DateTime.now);

  Entry entry(
    String id,
    MediaType type, {
    String? title,
    Released? released,
    String? creator,
    EntryStatus status = EntryStatus.want,
    DateTime? added,
    List<Season>? seasons,
    EntryKind? kind,
  }) => Entry(
    id: id,
    type: type,
    title: title ?? id,
    released: released,
    creator: creator,
    status: status,
    added: added ?? DateTime(2026, 1, 1),
    seasons: seasons,
    kind: kind,
  );

  HomeSection? section(List<HomeSection> sections, HomeSectionKind kind) =>
      sections.where((s) => s.kind == kind).firstOrNull;

  group('Coming soon', () {
    test('releases still ahead the owner wants, exact dates first, then months, then years', () {
      final entries = [
        entry('out', MediaType.movies, released: const Released(2024)),
        // Not Want: a release ahead the owner has not asked for stays out.
        entry(
          'done-movie',
          MediaType.movies,
          released: const Released(2026, 12, 1),
          status: EntryStatus.done,
        ),
        entry(
          'game',
          MediaType.games,
          title: "Castlevania: Belmont's Curse",
          released: const Released(2027),
          creator: 'Konami',
        ),
        entry(
          'show',
          MediaType.shows,
          title: 'Wednesday',
          status: EntryStatus.inProgress,
          seasons: [
            const Season(
              season: 1,
              released: Released(2022, 11, 23),
              status: EntryStatus.done,
            ),
            const Season(
              season: 2,
              released: Released(2025, 8, 6),
              status: EntryStatus.done,
            ),
            // The coming season set Want: the owner asked for it.
            const Season(
              season: 3,
              released: Released(2027),
              status: EntryStatus.want,
            ),
          ],
        ),
        entry(
          'anime',
          MediaType.anime,
          title: 'Strange: Junji Ito',
          released: const Released(2027, 1),
        ),
        entry(
          'movie',
          MediaType.movies,
          title: 'Werwulf',
          released: const Released(2026, 12, 25),
          creator: 'Robert Eggers',
        ),
        entry(
          'book',
          MediaType.books,
          title: 'Other Worlds Than These',
          released: const Released(2026, 11, 10),
          creator: 'Stephen King',
        ),
        entry(
          'soon-show',
          MediaType.shows,
          title: 'Haunted Hotel',
          status: EntryStatus.done,
          seasons: [
            const Season(
              season: 1,
              released: Released(2025, 9, 19),
              status: EntryStatus.done,
            ),
            const Season(
              season: 2,
              released: Released(2026, 11),
              status: EntryStatus.want,
            ),
          ],
        ),
        // A Done show whose announced season is not set stays out.
        entry(
          'unset-show',
          MediaType.shows,
          status: EntryStatus.done,
          seasons: [
            const Season(
              season: 1,
              released: Released(2024, 3, 1),
              status: EntryStatus.done,
            ),
            const Season(season: 2, released: Released(2026, 12)),
          ],
        ),
        // A season without a date counts as out, like an entry.
        entry(
          'undated-show',
          MediaType.shows,
          seasons: [const Season(season: 1)],
        ),
      ];
      final soon = section(
        homeSections(entries, today: today),
        HomeSectionKind.comingSoon,
      )!;
      expect(soon.total, 6);
      expect(soon.rows.map((r) => r.id), [
        'book',
        'movie',
        'soon-show',
        'anime',
        'game',
        'show',
      ]);
      expect(soon.rows.map((r) => r.right), [
        'Nov 10',
        'Dec 25',
        'Nov 2026',
        'Jan 2027',
        '2027',
        '2027',
      ]);
      expect(soon.rows.map((r) => r.emphasized), [
        true,
        true,
        false,
        false,
        false,
        false,
      ]);
      expect(soon.rows.map((r) => r.subtitle), [
        'Book · Stephen King',
        'Movie · Robert Eggers',
        'Show · Season 2',
        'Anime',
        'Game · Konami',
        'Show · Season 3',
      ]);
    });

    test('a date in another year names it', () {
      expect(
        comingSoonLabel(const Released(2027, 11, 10), today: today),
        'Nov 10, 2027',
      );
      expect(
        comingSoonLabel(const Released(2026, 11, 10), today: today),
        'Nov 10',
      );
    });
  });

  group('In progress', () {
    test('the most recently changed first, then newest added', () {
      final entries = [
        entry(
          'a',
          MediaType.books,
          title: 'Dune Messiah',
          status: EntryStatus.inProgress,
          released: const Released(1969),
          added: DateTime(2026, 9, 1),
        ),
        entry(
          'b',
          MediaType.games,
          title: 'Hollow Knight: Silksong',
          status: EntryStatus.inProgress,
          creator: 'Team Cherry',
          released: const Released(2025),
          added: DateTime(2026, 9, 20),
        ),
        entry(
          'c',
          MediaType.shows,
          title: 'Haunted Hotel',
          status: EntryStatus.inProgress,
          added: DateTime(2026, 10, 1),
          seasons: [
            const Season(
              season: 1,
              released: Released(2025, 9, 19),
              status: EntryStatus.done,
            ),
            const Season(
              season: 2,
              released: Released(2026, 9, 18),
              status: EntryStatus.inProgress,
            ),
          ],
        ),
        entry('d', MediaType.movies, status: EntryStatus.done),
      ];
      final going = section(
        homeSections(
          entries,
          today: today,
          changes: {'a': DateTime(2026, 10, 27, 12)},
        ),
        HomeSectionKind.inProgress,
      )!;
      expect(going.total, 3);
      expect(going.rows.map((r) => r.id), ['a', 'c', 'b']);
      expect(going.rows.map((r) => r.subtitle), [
        'Book · 1969',
        'Show · Season 2',
        'Game · Team Cherry',
      ]);
      expect(going.rows.every((r) => r.right.isEmpty), isTrue);

      // Without a change record, newest added first.
      final byAdded = section(
        homeSections(entries, today: today),
        HomeSectionKind.inProgress,
      )!;
      expect(byAdded.rows.map((r) => r.id), ['c', 'b', 'a']);
    });

    test('a show with Done and Want seasons names the next to watch', () {
      final show = entry(
        's',
        MediaType.shows,
        status: EntryStatus.inProgress,
        seasons: [
          const Season(
            season: 1,
            released: Released(2025, 1, 1),
            status: EntryStatus.done,
          ),
          const Season(
            season: 2,
            released: Released(2026, 1, 1),
            status: EntryStatus.want,
          ),
          const Season(season: 3, released: Released(2027)),
        ],
      );
      expect(inProgressDetail(show), 'Season 2');
    });

    test('ten rows at most, the total kept for See all', () {
      final entries = [
        for (var i = 0; i < 12; i++)
          entry(
            'e$i',
            MediaType.books,
            status: EntryStatus.inProgress,
            added: DateTime(2026, 9, 1 + i),
          ),
      ];
      final going = section(
        homeSections(entries, today: today),
        HomeSectionKind.inProgress,
      )!;
      expect(going.rows.length, HomeSection.limit);
      expect(going.total, 12);
      expect(going.rows.first.id, 'e11');
    });
  });

  group('Recently added', () {
    test('the last 30 days, newest first, with when', () {
      final entries = [
        entry(
          'old',
          MediaType.movies,
          added: DateTime(2026, 9, 27),
          released: const Released(2001),
        ),
        entry(
          'edge',
          MediaType.movies,
          title: 'The Mist',
          added: DateTime(2026, 9, 28),
          released: const Released(2007),
        ),
        entry(
          'week',
          MediaType.books,
          title: 'Dune Messiah',
          creator: 'Frank Herbert',
          released: const Released(1969),
          added: DateTime(2026, 10, 21),
        ),
        entry(
          'six',
          MediaType.music,
          title: 'Goo Goo Muck',
          creator: 'The Cramps',
          released: const Released(1981),
          kind: EntryKind.song,
          added: DateTime(2026, 10, 22),
        ),
        entry(
          'three',
          MediaType.shows,
          title: 'Haunted Hotel',
          added: DateTime(2026, 10, 25),
          seasons: [
            const Season(season: 1, released: Released(2025, 9, 19)),
            const Season(season: 2, released: Released(2026, 9, 18)),
          ],
        ),
        entry('yesterday', MediaType.anime, added: DateTime(2026, 10, 27)),
        entry(
          'today',
          MediaType.movies,
          title: 'Nosferatu',
          released: const Released(2024),
          added: DateTime(2026, 10, 28),
        ),
      ];
      final recent = section(
        homeSections(entries, today: today),
        HomeSectionKind.recentlyAdded,
      )!;
      expect(recent.total, 6);
      expect(recent.rows.map((r) => r.id), [
        'today',
        'yesterday',
        'three',
        'six',
        'week',
        'edge',
      ]);
      expect(recent.rows.map((r) => r.right), [
        'Today',
        'Yesterday',
        '3 days ago',
        '6 days ago',
        'Oct 21',
        'Sep 28',
      ]);
      expect(recent.rows.map((r) => r.emphasized), [
        true,
        true,
        false,
        false,
        false,
        false,
      ]);
      expect(recent.rows.map((r) => r.subtitle), [
        'Movie · 2024',
        'Anime',
        'Show · 2025–2026',
        'Music · The Cramps · 1981',
        'Book · Frank Herbert · 1969',
        'Movie · 2007',
      ]);
    });

    test('a date in another year names it', () {
      expect(
        addedLabel(DateTime(2025, 12, 30), today: DateTime(2026, 1, 10)),
        'Dec 30, 2025',
      );
    });
  });

  test('empty sections are left out', () {
    final entries = [
      entry('done', MediaType.movies, released: const Released(2001)),
    ];
    expect(homeSections(entries, today: today), isEmpty);
    expect(homeSections(const [], today: today), isEmpty);
  });

  group('upcomingPartsToShow (for the place that lists everything coming)', () {
    final fellowship = entry(
      'movies/fellowship',
      MediaType.movies,
      title: 'The Lord of the Rings: The Fellowship of the Ring',
      released: const Released(2001),
      status: EntryStatus.done,
    ).copyWith(series: const Series(name: 'The Lord of the Rings', number: 1));
    final towers = fellowship.copyWith(
      id: 'movies/towers',
      title: 'The Lord of the Rings: The Two Towers',
      status: EntryStatus.want,
      series: const Series(name: 'The Lord of the Rings', number: 2),
    );
    const gollum = UpcomingPart(
      type: MediaType.movies,
      seriesName: 'The Lord of the Rings',
      entryId: 'movies/fellowship',
      title: 'The Lord of the Rings: The Hunt for Gollum',
      released: Released(2027, 12, 17),
      number: 4,
      source: 'tmdb:movie:1',
    );
    const prefs = DisplayPreferences();

    test('drops unfollowed, owned and hidden parts', () {
      // Followed and not in the library: shown.
      expect(
        upcomingPartsToShow(
          const [gollum],
          library: [fellowship, towers],
          prefs: prefs,
        ),
        [gollum],
      );
      // No part Done or In progress: not followed.
      expect(
        upcomingPartsToShow(const [gollum], library: [towers], prefs: prefs),
        isEmpty,
      );
      // Added since, by id or by title: in the library.
      final byId = towers.copyWith(id: 'movies/gollum', source: 'tmdb:movie:1');
      expect(
        upcomingPartsToShow(
          const [gollum],
          library: [fellowship, byId],
          prefs: prefs,
        ),
        isEmpty,
      );
      final byTitle = towers.copyWith(
        id: 'movies/gollum',
        title: 'The Lord of the Rings: The Hunt for Gollum',
        series: const Series(name: 'The Lord of the Rings', number: null),
      );
      expect(
        upcomingPartsToShow(
          const [gollum],
          library: [fellowship, byTitle],
          prefs: prefs,
        ),
        isEmpty,
      );
      // Hidden in Choose what to show, or an extra not shown.
      final key = seriesKey(MediaType.movies, 'The Lord of the Rings');
      expect(
        upcomingPartsToShow(
          const [gollum],
          library: [fellowship],
          prefs: DisplayPreferences(
            hiddenSeriesParts: {
              key: {'tmdb:movie:1'},
            },
          ),
        ),
        isEmpty,
      );
      const extra = UpcomingPart(
        type: MediaType.movies,
        seriesName: 'The Lord of the Rings',
        entryId: 'movies/fellowship',
        title: 'Appendices',
        released: Released(2027),
        extra: true,
      );
      expect(
        upcomingPartsToShow(const [extra], library: [fellowship], prefs: prefs),
        isEmpty,
      );
      expect(
        upcomingPartsToShow(
          const [extra],
          library: [fellowship],
          prefs: DisplayPreferences(
            shownSeriesParts: {
              key: {extra.partKey},
            },
          ),
        ),
        [extra],
      );
      // The same part twice is one row.
      expect(
        upcomingPartsToShow(
          const [gollum, gollum],
          library: [fellowship],
          prefs: prefs,
        ),
        [gollum],
      );
    });
  });
}
