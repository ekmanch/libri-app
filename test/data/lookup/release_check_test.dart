import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/check_day_store.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/movie_dates.dart';
import 'package:library_app/data/lookup/release_check.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/dev/fake_lookup.dart';

void main() {
  final now = DateTime(2026, 10, 29, 9, 30);
  final today = DateTime(2026, 10, 29);

  Entry entry(
    String id,
    MediaType type, {
    Released? released,
    String? source,
    EntryKind? kind,
    List<Season>? seasons,
  }) => Entry(
    id: id,
    type: type,
    title: id,
    released: released,
    status: EntryStatus.want,
    added: DateTime(2026, 1, 1),
    source: source,
    kind: kind,
    seasons: seasons,
  );

  final game = entry(
    'games/gta-vi',
    MediaType.games,
    released: const Released(2026, 11, 19),
    source: 'igdb:1',
  );
  final movie = entry(
    'movies/dune-3',
    MediaType.movies,
    released: const Released(2026, 12, 18),
    source: 'tmdb:movie:2',
  );
  final undated = entry('games/tba', MediaType.games, source: 'igdb:3');
  final out = entry(
    'movies/out',
    MediaType.movies,
    released: const Released(2024),
    source: 'tmdb:movie:4',
  );
  final byHand = entry(
    'books/by-hand',
    MediaType.books,
    released: const Released(2027),
  );
  final show = entry(
    'shows/wednesday',
    MediaType.shows,
    source: 'tmdb:tv:5',
    seasons: const [Season(season: 1, released: Released(2027))],
  );
  final animeSeries = entry(
    'anime/frieren',
    MediaType.anime,
    source: 'anilist:6',
    kind: EntryKind.series,
    seasons: const [Season(season: 1, released: Released(2027))],
  );
  final animeMovie = entry(
    'anime/movie',
    MediaType.anime,
    source: 'anilist:7',
    kind: EntryKind.movie,
    released: const Released(2027, 3),
  );

  late FakeLookupSource fake;
  late MemoryCheckDayStore store;
  late ReleaseCheck check;

  late MemoryMovieDateStore dates;

  void setUpCheck({
    LookupFailure? failure,
    bool configured = true,
    Map<String, Released?> released = const {},
    Map<String, MovieDates?> movieDates = const {},
    Map<String, EditionRelease?> editions = const {},
    Map<String, MovieDates> recorded = const {},
  }) {
    fake = FakeLookupSource(
      failure: failure,
      configured: configured,
      releasedBySource: released,
      movieDatesBySource: movieDates,
      editionsBySource: editions,
    );
    store = MemoryCheckDayStore();
    dates = MemoryMovieDateStore(recorded);
    check = ReleaseCheck(
      lookups: LookupService([fake]),
      store: store,
      movieDates: dates,
    );
  }

  group('movies and books (DESIGN.md 10c)', () {
    final cinema = const Released(2026, 12, 18);
    final digital = const Released(2027, 2);

    test('isAsked: a movie out within 180 days is asked for its digital '
        'date until it has one that is out', () {
      final recent = entry(
        'movies/recent',
        MediaType.movies,
        released: const Released(2026, 9, 1),
        source: 'tmdb:movie:9',
      );
      expect(ReleaseCheck.isAsked(recent, today), isTrue);
      expect(
        ReleaseCheck.isAsked(
          recent,
          today,
          dates: MovieDates(
            cinema: const Released(2026, 9, 1),
            digital: digital,
          ),
        ),
        isTrue,
      );
      expect(
        ReleaseCheck.isAsked(
          recent,
          today,
          dates: const MovieDates(
            cinema: Released(2026, 9, 1),
            digital: Released(2026, 10, 20),
          ),
        ),
        isFalse,
      );
      // Six months on it is left alone, whatever is known.
      expect(ReleaseCheck.isAsked(recent, DateTime(2027, 4, 1)), isFalse);
      // A game out is never asked.
      expect(
        ReleaseCheck.isAsked(
          game.copyWith(released: const Released(2026, 9, 1)),
          today,
        ),
        isFalse,
      );
    });

    test('a movie\'s dates by kind are recorded and the first is written; '
        'the date of the first alone when none by kind is known', () async {
      setUpCheck(
        movieDates: {
          'tmdb:movie:2': MovieDates(cinema: cinema, digital: digital),
          'tmdb:movie:4': const MovieDates(),
        },
        released: {'tmdb:movie:4': const Released(2026, 11, 5)},
      );
      final early = movie.copyWith(released: const Released(2027, 1, 8));
      // Out in September: asked for its digital date.
      final recent = out.copyWith(released: const Released(2026, 9, 1));
      final operations = await check.run(
        Library(entries: [early, recent]),
        now,
      );
      expect(fake.calls, [
        'movie-dates:tmdb:movie:2',
        'movie-dates:tmdb:movie:4',
        'released:tmdb:movie:4',
      ]);
      expect(operations.map((o) => (o as SetReleased).released), [
        cinema,
        const Released(2026, 11, 5),
      ]);
      expect(await dates.read(), {
        'tmdb:movie:2': MovieDates(cinema: cinema, digital: digital),
      });
      // Under every setting `released` is the first date: nothing else is
      // asked of the setting here.
      expect(await store.lastRun(), today);
    });

    test('a book takes its earliest edition in the languages read; one with '
        'no such edition, or no languages, keeps the work\'s date', () async {
      final book = entry(
        'books/berserk-44',
        MediaType.books,
        released: const Released(2026),
        source: 'openlibrary:OL44W',
      );
      final other = entry(
        'books/other',
        MediaType.books,
        released: const Released(2027),
        source: 'openlibrary:OL45W',
      );
      setUpCheck(
        editions: {
          'openlibrary:OL44W': (
            inLanguages: true,
            title: null,
            released: const Released(2027, 3, 10),
          ),
          'openlibrary:OL45W': (
            inLanguages: false,
            title: null,
            released: null,
          ),
        },
        released: {'openlibrary:OL45W': const Released(2027)},
      );
      final operations = await check.run(
        Library(entries: [book, other]),
        now,
        languages: {'sv', 'en'},
      );
      expect(fake.calls, [
        'editions:openlibrary:OL44W:en,sv',
        'editions:openlibrary:OL45W:en,sv',
        'released:openlibrary:OL45W',
      ]);
      expect(operations.map((o) => (o as SetReleased).released), [
        const Released(2027, 3, 10),
      ]);
      fake.calls.clear();
      await check.run(Library(entries: [book]), now, force: true);
      expect(fake.calls, ['released:openlibrary:OL44W']);
    });
  });

  test('isAsked: linked, not a show or anime series, not out or undated', () {
    expect(ReleaseCheck.isAsked(game, today), isTrue);
    expect(ReleaseCheck.isAsked(undated, today), isTrue);
    expect(ReleaseCheck.isAsked(animeMovie, today), isTrue);
    expect(ReleaseCheck.isAsked(out, today), isFalse);
    expect(ReleaseCheck.isAsked(byHand, today), isFalse);
    expect(ReleaseCheck.isAsked(show, today), isFalse);
    expect(ReleaseCheck.isAsked(animeSeries, today), isFalse);
    // A year-only date counts as out only after its year.
    final thisYear = game.copyWith(released: const Released(2026));
    expect(ReleaseCheck.isAsked(thisYear, today), isTrue);
    expect(ReleaseCheck.isAsked(thisYear, DateTime(2027, 1, 1)), isFalse);
  });

  test(
    'asks about every entry not out yet and writes a changed date',
    () async {
      setUpCheck(
        released: {
          'igdb:1': const Released(2027, 5, 26), // Delayed.
          'tmdb:movie:2': const Released(2026, 12, 18), // As stored.
          'igdb:3': const Released(2028), // Announced.
          'anilist:7': null, // Nothing known.
        },
      );
      final library = Library(
        entries: [
          game,
          movie,
          undated,
          out,
          byHand,
          show,
          animeSeries,
          animeMovie,
        ],
      );
      final operations = await check.run(library, now);
      expect(fake.calls, [
        'released:igdb:1',
        // A movie is asked for its dates by kind first; the fake has none
        // for this one, so its own date is asked next.
        'movie-dates:tmdb:movie:2',
        'released:tmdb:movie:2',
        'released:igdb:3',
        'released:anilist:7',
      ]);
      expect(operations.map((o) => (o as SetReleased).entryId), [
        game.id,
        undated.id,
      ]);
      expect(
        (operations.first as SetReleased).released,
        const Released(2027, 5, 26),
      );
      final after = operations.fold(library, (l, o) => o.apply(l));
      expect(after.entryById(game.id)!.released, const Released(2027, 5, 26));
      expect(after.entryById(undated.id)!.released, const Released(2028));
      expect(after.entryById(movie.id)!.released, const Released(2026, 12, 18));
      // The day is recorded: no second run today, one tomorrow.
      expect(await store.lastRun(), today);
      expect(await check.run(library, now), isEmpty);
      expect(fake.calls, hasLength(5));
      await check.run(library, DateTime(2026, 10, 30, 8));
      expect(fake.calls, hasLength(10));
    },
  );

  test('offline or rate limited stops the check and leaves the day', () async {
    for (final failure in [LookupFailure.offline, LookupFailure.rateLimited]) {
      setUpCheck(failure: failure);
      final operations = await check.run(Library(entries: [game, movie]), now);
      expect(operations, isEmpty);
      expect(fake.calls, ['released:igdb:1']);
      expect(await store.lastRun(), isNull);
    }
  });

  test(
    'a bad answer is nothing learned; a server error holds the day',
    () async {
      setUpCheck(failure: LookupFailure.other);
      await check.run(Library(entries: [game, movie]), now);
      expect(fake.calls, ['released:igdb:1', 'movie-dates:tmdb:movie:2']);
      expect(await store.lastRun(), today);

      final failing = _ServerErrorSource();
      store = MemoryCheckDayStore();
      check = ReleaseCheck(lookups: LookupService([failing]), store: store);
      expect(await check.run(Library(entries: [game, movie]), now), isEmpty);
      expect(failing.calls, [
        'released:igdb:1',
        'movie-dates:tmdb:movie:2',
        'released:tmdb:movie:2',
      ]);
      expect(await store.lastRun(), isNull);
    },
  );

  test(
    'a lookup that is not set up asks nothing and records the day',
    () async {
      setUpCheck(configured: false);
      expect(await check.run(Library(entries: [game]), now), isEmpty);
      expect(fake.calls, isEmpty);
      expect(await store.lastRun(), today);
    },
  );
}

/// A provider whose server is down: a 503 for every date.
class _ServerErrorSource extends FakeLookupSource {
  @override
  Future<Released?> releaseDate(String source) async {
    calls.add('released:$source');
    throw const LookupException(LookupFailure.other, status: 503);
  }
}
