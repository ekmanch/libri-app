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
import 'package:library_app/features/library/upcoming.dart';
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
    List<Season>? seasons,
    EntryKind? kind,
    Series? series,
  }) => Entry(
    id: id,
    type: type,
    title: title ?? id,
    released: released,
    creator: creator,
    status: status,
    added: DateTime(2026, 1, 1),
    seasons: seasons,
    kind: kind,
    series: series,
  );

  const gollum = UpcomingPart(
    type: MediaType.movies,
    seriesName: 'The Lord of the Rings',
    entryId: 'fellowship',
    title: 'The Lord of the Rings: The Hunt for Gollum',
    released: Released(2027, 12, 17),
    number: 4,
    source: 'fake:gollum',
  );
  final fellowship = entry(
    'fellowship',
    MediaType.movies,
    title: 'The Fellowship of the Ring',
    released: const Released(2001),
    status: EntryStatus.done,
    series: const Series(name: 'The Lord of the Rings', number: 1),
  );
  final towers = entry(
    'towers',
    MediaType.movies,
    title: 'The Two Towers',
    released: const Released(2002),
    status: EntryStatus.done,
    series: const Series(name: 'The Lord of the Rings', number: 2),
  );

  group('upcomingItems', () {
    test('lists releases ahead of every status, coming seasons, undated wants and series parts, nearest first', () {
      final strangerThings = entry(
        'stranger-things',
        MediaType.shows,
        title: 'Stranger Things',
        status: EntryStatus.done,
        seasons: const [
          Season(season: 1, released: Released(2016), status: EntryStatus.done),
          Season(season: 2, released: Released(2017), status: EntryStatus.done),
          Season(season: 5, released: Released(2026, 11, 26)),
        ],
      );
      final items = upcomingItems(
        [
          entry('out', MediaType.movies, released: const Released(2024)),
          entry(
            'werwulf',
            MediaType.movies,
            title: 'Werwulf',
            released: const Released(2026, 12, 25),
            creator: 'Robert Eggers',
          ),
          entry(
            'king',
            MediaType.books,
            title: 'Other Worlds Than These',
            released: const Released(2026, 11, 10),
            creator: 'Stephen King',
          ),
          entry(
            'winds',
            MediaType.books,
            title: 'The Winds of Winter',
            creator: 'George R. R. Martin',
          ),
          // Not Want and undated: out, like any undated entry.
          entry('old', MediaType.books, status: EntryStatus.done),
          entry(
            'silksong',
            MediaType.games,
            title: 'Silksong',
            released: const Released(2027),
            status: EntryStatus.inProgress,
          ),
          entry(
            'junji',
            MediaType.anime,
            title: 'Strange: Junji Ito',
            released: const Released(2027, 1),
            kind: EntryKind.movie,
          ),
          strangerThings,
          fellowship,
          towers,
        ],
        parts: const [gollum],
        prefs: const DisplayPreferences(),
        today: today,
      );
      expect(items.map((i) => i.title), [
        'Other Worlds Than These',
        'Stranger Things',
        'Werwulf',
        'Strange: Junji Ito',
        // A year alone counts as out from the next year, so it sorts
        // after that year's dates.
        'The Hunt for Gollum',
        'Silksong',
        'The Winds of Winter',
      ]);
      expect(items.map((i) => i.wanted), [
        true,
        false,
        true,
        true,
        false,
        false,
        true,
      ]);
      expect(items.map((i) => i.kind), [
        UpcomingKind.entry,
        UpcomingKind.season,
        UpcomingKind.entry,
        UpcomingKind.entry,
        UpcomingKind.part,
        UpcomingKind.entry,
        UpcomingKind.entry,
      ]);
      expect(items.map((i) => i.detail), [
        'Stephen King',
        'Season 5',
        'Robert Eggers',
        null,
        'The Lord of the Rings',
        null,
        'George R. R. Martin',
      ]);
      expect(items.map((i) => i.rightLabel(today)), [
        'Nov 10',
        'Nov 26',
        'Dec 25',
        'Jan 2027',
        'Dec 17, 2027',
        '2027',
        'Date not set',
      ]);
      expect(items.map((i) => i.emphasized), [
        true,
        true,
        true,
        false,
        true,
        false,
        false,
      ]);
      expect(items[1].id, 'stranger-things#5');
      expect(items[4].id, 'part:movies/The Lord of the Rings/fake:gollum');
      expect(
        items[1].reason,
        'Stranger Things is in your library; seasons 1 and 2 are Done.',
      );
      expect(
        items[4].reason,
        'Part 4 of The Lord of the Rings; parts 1 and 2 are in your library.',
      );
      expect(items[5].reason, 'Silksong is in your library (In progress).');
      expect(items[0].sheetTitle, 'Other Worlds Than These');
      expect(items[1].sheetTitle, 'Stranger Things, Season 5');
      expect(items[4].sheetTitle, 'The Lord of the Rings: The Hunt for Gollum');

      expect(wantedUpcoming(items).map((i) => i.title), [
        'Other Worlds Than These',
        'Werwulf',
        'Strange: Junji Ito',
        'The Winds of Winter',
      ]);
    });

    test('a season set Want is wanted; a show set Want with no coming season is not listed', () {
      final wednesday = entry(
        'wednesday',
        MediaType.shows,
        title: 'Wednesday',
        status: EntryStatus.done,
        seasons: const [
          Season(season: 1, released: Released(2022), status: EntryStatus.done),
          Season(season: 3, released: Released(2027), status: EntryStatus.want),
        ],
      );
      final bear = entry(
        'bear',
        MediaType.shows,
        title: 'The Bear',
        seasons: const [
          Season(season: 1, released: Released(2022), status: EntryStatus.want),
        ],
      );
      final items = upcomingItems(
        [wednesday, bear],
        parts: const [],
        prefs: const DisplayPreferences(),
        today: today,
      );
      expect(items.map((i) => i.title), ['Wednesday']);
      expect(items.single.wanted, isTrue);
      expect(items.single.detail, 'Season 3');
    });

    test('Not interested rows stay out; a hidden part through its series', () {
      final show = entry(
        'show',
        MediaType.shows,
        status: EntryStatus.done,
        seasons: const [
          Season(season: 1, released: Released(2020), status: EntryStatus.done),
          Season(season: 2, released: Released(2027, 3)),
        ],
      );
      final movie = entry(
        'movie',
        MediaType.movies,
        released: const Released(2027),
        status: EntryStatus.done,
      );
      List<String> titles(DisplayPreferences prefs) => upcomingItems(
        [show, movie, fellowship, towers],
        parts: const [gollum],
        prefs: prefs,
        today: today,
      ).map((i) => i.title).toList();
      expect(titles(const DisplayPreferences()), [
        'show',
        'The Hunt for Gollum',
        'movie',
      ]);
      expect(
        titles(const DisplayPreferences(hiddenUpcoming: {'show#2', 'movie'})),
        ['The Hunt for Gollum'],
      );
      expect(
        titles(
          DisplayPreferences(
            hiddenSeriesParts: {
              seriesKey(MediaType.movies, 'The Lord of the Rings'): {
                'fake:gollum',
              },
            },
          ),
        ),
        ['show', 'movie'],
      );
    });
  });

  group('upcomingGroups', () {
    test(
      'months of this year, months with their year, years, then Date not set',
      () {
        final items = upcomingItems(
          [
            entry(
              'a',
              MediaType.movies,
              released: const Released(2026, 11, 10),
            ),
            entry('b', MediaType.movies, released: const Released(2026, 11)),
            entry('c', MediaType.movies, released: const Released(2026)),
            entry('d', MediaType.movies, released: const Released(2027, 1, 5)),
            entry('e', MediaType.movies, released: const Released(2027, 3)),
            entry('f', MediaType.movies, released: const Released(2027)),
            entry('g', MediaType.movies),
            entry('h', MediaType.movies, released: const Released(2026, 11, 2)),
          ],
          parts: const [],
          prefs: const DisplayPreferences(),
          today: today,
        );
        final groups = upcomingGroups(items, today: today);
        expect(groups.map((g) => g.name), [
          'November',
          '2026',
          'January 2027',
          'March 2027',
          '2027',
          'Date not set',
        ]);
        // Exact dates in day order, then the month alone.
        expect(groups.first.items.map((i) => i.id), ['h', 'a', 'b']);
      },
    );
  });

  group('reasons', () {
    test('a season names the seasons with the show\'s status', () {
      expect(
        seasonReason(
          entry(
            'frieren',
            MediaType.anime,
            title: 'Frieren',
            kind: EntryKind.series,
            status: EntryStatus.inProgress,
            seasons: const [
              Season(
                season: 1,
                released: Released(2023),
                status: EntryStatus.done,
              ),
              Season(
                season: 2,
                released: Released(2026, 1),
                status: EntryStatus.inProgress,
              ),
              Season(season: 3, released: Released(2027, 1)),
            ],
          ),
          today: today,
        ),
        'Frieren is in your library; season 2 is In progress.',
      );
      expect(
        seasonReason(
          entry(
            'new',
            MediaType.shows,
            title: 'New',
            seasons: const [Season(season: 1, released: Released(2027))],
          ),
          today: today,
        ),
        // One season takes its status, Want while not set, but no season
        // carries it.
        'New is in your library.',
      );
    });

    test('a part counts the parts in the library when numbers are missing', () {
      final unnumbered = towers.copyWith(
        series: const Series(name: 'The Lord of the Rings'),
      );
      expect(
        partReason(gollum, owned: [fellowship, unnumbered]),
        'The Lord of the Rings is in your library (2 movies).',
      );
      expect(
        partReason(gollum, owned: [fellowship]),
        'Part 4 of The Lord of the Rings; part 1 is in your library.',
      );
    });

    test('numberedPhrase', () {
      expect(numberedPhrase('part', [3]), 'part 3');
      expect(numberedPhrase('part', [2, 1]), 'parts 1 and 2');
      expect(numberedPhrase('part', [3, 1, 2]), 'parts 1–3');
      expect(numberedPhrase('part', [1, 2, 4]), 'parts 1, 2 and 4');
    });
  });
}
