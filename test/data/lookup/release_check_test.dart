import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/check_day_store.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
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

  void setUpCheck({
    LookupFailure? failure,
    bool configured = true,
    Map<String, Released?> released = const {},
  }) {
    fake = FakeLookupSource(
      failure: failure,
      configured: configured,
      releasedBySource: released,
    );
    store = MemoryCheckDayStore();
    check = ReleaseCheck(lookups: LookupService([fake]), store: store);
  }

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
      expect(fake.calls, hasLength(4));
      await check.run(library, DateTime(2026, 10, 30, 8));
      expect(fake.calls, hasLength(8));
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
      expect(fake.calls, ['released:igdb:1', 'released:tmdb:movie:2']);
      expect(await store.lastRun(), today);

      final failing = _ServerErrorSource();
      store = MemoryCheckDayStore();
      check = ReleaseCheck(lookups: LookupService([failing]), store: store);
      expect(await check.run(Library(entries: [game, movie]), now), isEmpty);
      expect(failing.calls, ['released:igdb:1', 'released:tmdb:movie:2']);
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
