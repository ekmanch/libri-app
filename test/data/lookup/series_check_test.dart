import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/lookup/check_day_store.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/lookup/series_check.dart';
import 'package:library_app/data/lookup/series_service.dart';
import 'package:library_app/data/lookup/series_store.dart';
import 'package:library_app/data/lookup/text_clean.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/data/storage/json_file.dart';
import 'package:library_app/dev/fake_lookup.dart';

void main() {
  final now = DateTime(2026, 10, 29, 9, 30);
  final today = DateTime(2026, 10, 29);

  Entry part(
    String id,
    String series,
    int number, {
    EntryStatus status = EntryStatus.done,
    MediaType type = MediaType.movies,
    String? source,
  }) => Entry(
    id: id,
    type: type,
    title: id,
    status: status,
    added: DateTime(2026, 1, 1),
    source: source,
    series: Series(name: series, number: number),
  );

  SeriesPart listed(
    int number,
    String title, {
    Released? released,
    String? source,
    String? cover,
    bool extra = false,
  }) => (
    number: number,
    title: title,
    year: released?.year,
    released: released,
    source: source,
    creator: null,
    cover: cover,
    extra: extra,
  );

  final fellowship = part(
    'movies/fellowship',
    'The Lord of the Rings',
    1,
    source: 'tmdb:movie:120',
  );
  final towers = part(
    'movies/towers',
    'The Lord of the Rings',
    2,
    status: EntryStatus.want,
    source: 'tmdb:movie:121',
  );
  final dune = part(
    'movies/dune',
    'Dune',
    1,
    status: EntryStatus.want,
    source: 'tmdb:movie:438631',
  );
  final SeriesParts lotr = (
    name: 'The Lord of the Rings',
    parts: [
      listed(
        1,
        'The Fellowship of the Ring',
        released: const Released(2001, 12, 18),
        source: 'tmdb:movie:120',
      ),
      listed(
        2,
        'The Two Towers',
        released: const Released(2002, 12, 18),
        source: 'tmdb:movie:121',
      ),
      listed(
        3,
        'The Hunt for Gollum',
        released: const Released(2027, 12, 17),
        source: 'tmdb:movie:1',
        cover: 'https://image.tmdb.org/t/p/w342/gollum.jpg',
      ),
      listed(4, 'Untitled'),
    ],
  );
  final SeriesParts duneParts = (
    name: 'Dune',
    parts: [
      listed(1, 'Dune', released: const Released(2021, 10, 21)),
      listed(2, 'Dune: Part Three', released: const Released(2026, 12, 18)),
    ],
  );

  late FakeLookupSource fake;
  late MemorySeriesStore series;
  late MemoryCheckDayStore days;
  late MemoryUpcomingPartsStore upcoming;
  late SeriesCheck check;

  void setUpCheck({LookupFailure? failure, Map<String, SeriesParts?>? lists}) {
    fake = FakeLookupSource(
      failure: failure,
      seriesBySource:
          lists ??
          {
            'tmdb:movie:120': lotr,
            'tmdb:movie:121': lotr,
            'tmdb:movie:438631': duneParts,
          },
    );
    final lookups = LookupService([fake]);
    series = MemorySeriesStore();
    days = MemoryCheckDayStore();
    upcoming = MemoryUpcomingPartsStore();
    check = SeriesCheck(
      series: SeriesService(
        lookups: lookups,
        resolver: ArtworkResolver(lookups: lookups),
        store: series,
      ),
      store: days,
      upcoming: upcoming,
    );
  }

  test('a series is followed when a part is Done or In progress', () {
    expect(SeriesCheck.isFollowed([fellowship, towers]), isTrue);
    expect(SeriesCheck.isFollowed([towers]), isFalse);
    expect(
      SeriesCheck.isFollowed([towers.copyWith(status: EntryStatus.inProgress)]),
      isTrue,
    );
    expect(
      SeriesCheck.isFollowed([fellowship.copyWith(status: EntryStatus.dnf)]),
      isFalse,
    );
  });

  test(
    'asks once per followed series and records the parts still ahead',
    () async {
      setUpCheck();
      final library = Library(entries: [fellowship, towers, dune]);
      expect(await check.run(library, now), isTrue);
      // One ask, through the first linked part; Dune is not followed.
      expect(fake.calls, ['series:tmdb:movie:120']);
      expect(await upcoming.read(), [
        const UpcomingPart(
          type: MediaType.movies,
          seriesName: 'The Lord of the Rings',
          entryId: 'movies/fellowship',
          title: 'The Hunt for Gollum',
          released: Released(2027, 12, 17),
          number: 3,
          source: 'tmdb:movie:1',
          // The cover's URL only: the image is fetched when the add sheet
          // opens, never by the check.
          cover: 'https://image.tmdb.org/t/p/w342/gollum.jpg',
        ),
      ]);
      expect(await days.lastRun(), today);
      expect((await series.read('tmdb:movie:120'))!.series.parts, lotr.parts);
      // Not again today.
      expect(await check.run(library, now), isFalse);
      expect(fake.calls, hasLength(1));
    },
  );

  test(
    'a list with a part still ahead is fetched again daily, the rest weekly',
    () async {
      setUpCheck();
      final library = Library(entries: [fellowship, towers]);
      await check.run(library, now);
      // The next day: due again, since The Hunt for Gollum is still ahead.
      await check.run(library, now.add(const Duration(days: 1)));
      expect(fake.calls, hasLength(2));

      // A series with nothing ahead waits a week.
      setUpCheck(
        lists: {
          'tmdb:movie:120': (
            name: lotr.name,
            parts: lotr.parts.take(2).toList(),
          ),
        },
      );
      await check.run(library, now);
      await check.run(library, now.add(const Duration(days: 1)));
      expect(fake.calls, hasLength(1));
      await check.run(library, now.add(const Duration(days: 7)));
      expect(fake.calls, hasLength(2));
      expect(await upcoming.read(), isEmpty);
    },
  );

  test(
    'offline keeps the stored lists for the record and leaves the day',
    () async {
      setUpCheck();
      final library = Library(entries: [fellowship, towers]);
      await check.run(library, now);
      final stored = await upcoming.read();

      setUpCheck(failure: LookupFailure.offline);
      await series.write(
        'tmdb:movie:120',
        lotr,
        fetched: now.subtract(const Duration(days: 2)),
        asked: lotr.name,
      );
      expect(await check.run(library, now), isTrue);
      expect(await upcoming.read(), stored);
      expect(await days.lastRun(), isNull);
    },
  );

  test('a book part still to come is recorded only with an edition in the '
      'languages read, dated by it (DESIGN.md 10c)', () async {
    final berserk43 = part(
      'books/berserk-43',
      'Berserk',
      43,
      type: MediaType.books,
      source: 'openlibrary:OL43W',
    );
    final SeriesParts berserk = (
      name: 'Berserk',
      parts: [
        // Out in Japanese in March, in English since: asked, then skipped.
        listed(
          43,
          'Berserk, Vol. 43',
          released: const Released(2026, 3, 10),
          source: 'openlibrary:OL43W',
        ),
        listed(
          44,
          'Berserk, Vol. 44',
          released: const Released(2026, 9, 24),
          source: 'openlibrary:OL44W',
        ),
        listed(
          45,
          'Berserk, Vol. 45',
          released: const Released(2027, 3),
          source: 'openlibrary:OL45W',
        ),
        listed(
          46,
          'Berserk, Vol. 46',
          released: const Released(2027, 9),
          source: 'openlibrary:OL46W',
        ),
      ],
    );
    setUpCheck(lists: {'openlibrary:OL43W': berserk});
    fake = FakeLookupSource(
      seriesBySource: {'openlibrary:OL43W': berserk},
      editionsBySource: {
        'openlibrary:OL43W': (
          inLanguages: true,
          released: const Released(2025, 12, 2),
        ),
        'openlibrary:OL44W': (
          inLanguages: true,
          released: const Released(2027, 1, 12),
        ),
        'openlibrary:OL45W': (inLanguages: false, released: null),
        // Nothing learned: kept as listed.
        'openlibrary:OL46W': null,
      },
    );
    final lookups = LookupService([fake]);
    check = SeriesCheck(
      series: SeriesService(
        lookups: lookups,
        resolver: ArtworkResolver(lookups: lookups),
        store: MemorySeriesStore(),
      ),
      store: days,
      upcoming: upcoming,
    );
    await check.run(
      Library(entries: [berserk43]),
      DateTime(2026, 10, 29, 9),
      languages: {'en'},
    );
    final recorded = await upcoming.read();
    // Volume 44 is out in Japanese, its English edition still to come;
    // volume 43 is out in English too; 45 has no edition in English.
    expect(recorded.map((p) => p.title), [
      'Berserk, Vol. 44',
      'Berserk, Vol. 46',
    ]);
    expect(recorded.first.released, const Released(2027, 1, 12));
    expect(recorded.last.released, const Released(2027, 9));
    expect(fake.calls.where((c) => c.startsWith('editions:')), [
      'editions:openlibrary:OL43W:en',
      'editions:openlibrary:OL44W:en',
      'editions:openlibrary:OL45W:en',
      'editions:openlibrary:OL46W:en',
    ]);
  });

  test('a part that came out, or has no date, is not recorded', () async {
    setUpCheck();
    await check.run(
      Library(entries: [fellowship, towers]),
      DateTime(2027, 12, 17, 10),
    );
    expect(await upcoming.read(), isEmpty);
  });

  test('the file store round-trips the parts', () async {
    final dir = await Directory.systemTemp.createTemp('upcoming');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileUpcomingPartsStore(JsonFile(File('${dir.path}/u.json')));
    expect(await store.read(), isEmpty);
    const parts = [
      UpcomingPart(
        type: MediaType.books,
        seriesName: 'Berserk',
        entryId: 'books/berserk-43',
        title: 'Berserk, Vol. 44',
        released: Released(2027),
        number: 44,
        cover: 'https://covers.openlibrary.org/b/id/44-L.jpg',
        extra: true,
      ),
    ];
    await store.write(parts);
    expect(await store.read(), parts);
    expect(parts.single.partKey, 'title:${titleKey(parts.single.title)}');
  });
}
