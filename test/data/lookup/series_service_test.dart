import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/lookup/series_service.dart';
import 'package:library_app/data/lookup/series_store.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/dev/fake_lookup.dart';

const _source = 'tmdb:movie:120';

final _fellowship = Entry(
  id: 'movies/the-fellowship-of-the-ring-2001',
  type: MediaType.movies,
  title: 'The Fellowship of the Ring',
  status: EntryStatus.done,
  added: DateTime(2026, 1, 1),
  source: _source,
  series: const Series(name: 'The Lord of the Rings', number: 1),
);

const SeriesParts _lotr = (
  name: 'The Lord of the Rings',
  parts: [
    (
      number: 1,
      title: 'The Fellowship of the Ring',
      year: 2001,
      released: null,
      source: _source,
      creator: null,
      cover: null,
      extra: false,
    ),
    (
      number: 2,
      title: 'The Two Towers',
      year: 2002,
      released: null,
      source: 'tmdb:movie:121',
      creator: null,
      cover: null,
      extra: false,
    ),
  ],
);

void main() {
  final now = DateTime(2026, 10, 19, 12);

  setUp(() => seasonClock = () => now);
  tearDown(() => seasonClock = DateTime.now);

  ({SeriesService service, FakeLookupSource fake, MemorySeriesStore store})
  build({
    LookupFailure? failure,
    bool configured = true,
    Map<String, SeriesParts?> series = const {_source: _lotr},
  }) {
    final fake = FakeLookupSource(
      failure: failure,
      configured: configured,
      seriesBySource: series,
    );
    final lookups = LookupService([fake]);
    final store = MemorySeriesStore();
    return (
      service: SeriesService(
        lookups: lookups,
        resolver: ArtworkResolver(lookups: lookups),
        store: store,
      ),
      fake: fake,
      store: store,
    );
  }

  test('fetches once, stores, then answers from the phone', () async {
    final b = build();
    final first = await b.service.load(_fellowship).toList();
    expect(first.single!.series.name, _lotr.name);
    expect(first.single!.series.parts, _lotr.parts);
    expect(first.single!.fromCache, isFalse);
    expect(b.fake.calls, ['series:$_source']);
    expect((await b.store.read(_source))!.series.parts, _lotr.parts);

    // Within a week: the stored list alone.
    final again = await b.service.load(_fellowship).toList();
    expect(again.single!.fromCache, isTrue);
    expect(b.fake.calls, hasLength(1));
  });

  test('a stored list a week old shows at once and is fetched again', () async {
    final b = build();
    await b.store.write(_source, (
      name: 'Old',
      parts: const [],
    ), fetched: now.subtract(const Duration(days: 8)));
    final results = await b.service.load(_fellowship).toList();
    expect(results.map((r) => r!.fromCache), [true, false]);
    expect(results.last!.series.name, 'The Lord of the Rings');
  });

  test('a renamed series shows the stored list and is fetched again with '
      'the new name', () async {
    final b = build();
    await b.service.load(_fellowship).toList();
    final renamed = _fellowship.copyWith(
      series: const Series(name: 'Middle-earth', number: 1),
    );
    final results = await b.service.load(renamed).toList();
    expect(results.map((r) => r!.fromCache), [true, false]);
    expect(b.fake.calls, hasLength(2));
    expect((await b.store.read(_source))!.asked, 'Middle-earth');
    // Asked under that name, the list is trusted again.
    await b.service.load(renamed).toList();
    expect(b.fake.calls, hasLength(2));
  });

  test('a failed refetch keeps the stored list and says so; nothing stored '
      'fails', () async {
    final b = build(failure: LookupFailure.offline);
    await b.store.write(
      _source,
      _lotr,
      fetched: now.subtract(const Duration(days: 8)),
    );
    final results = await b.service.load(_fellowship).toList();
    expect(results.map((r) => (r!.fromCache, r.updateFailed)), [
      (true, false),
      (true, true),
    ]);
    expect(results.last!.series.parts, _lotr.parts);

    final empty = build(failure: LookupFailure.offline);
    await expectLater(
      empty.service.load(_fellowship).toList(),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.offline,
        ),
      ),
    );
  });

  test('no series known, or no lookup id, is null', () async {
    final none = build(series: const {_source: null});
    expect(await none.service.load(_fellowship).toList(), [null]);
    expect(await none.store.read(_source), isNull);

    final byHand = _fellowship.copyWith(source: null, title: 'Nothing matches');
    final b = build();
    // The resolver matches the title on the fake, so a part found that way
    // is asked by the fake's own id.
    final results = await b.service.load(byHand).toList();
    expect(results, [null]);
    expect(b.fake.calls, contains('series:fake:nothing-matches'));
  });

  test('the series name the entry carries is passed along', () async {
    final b = build();
    await b.service.load(_fellowship).toList();
    expect(b.fake.calls, ['series:$_source']);
  });

  test('prune drops the series of entries that are gone', () async {
    final b = build();
    await b.service.load(_fellowship).toList();
    await b.store.write('tmdb:movie:999', _lotr, fetched: now);
    await b.service.prune([_fellowship]);
    expect(await b.store.read(_source), isNotNull);
    expect(await b.store.read('tmdb:movie:999'), isNull);
  });

  test('the file store round-trips a series and prunes by id', () async {
    final dir = await Directory.systemTemp.createTemp('series');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileSeriesStore(dir);
    await store.write(_source, _lotr, fetched: now, asked: _lotr.name);
    final stored = await store.read(_source);
    expect(stored!.series.name, _lotr.name);
    expect(stored.asked, _lotr.name);
    expect(stored.series.parts, _lotr.parts);
    expect(stored.fetched.toUtc(), now.toUtc());
    expect(await store.read('tmdb:movie:121'), isNull);
    await store.write('tmdb:movie:121', _lotr, fetched: now);
    await store.prune({_source});
    expect(await store.read('tmdb:movie:121'), isNull);
    expect(await store.read(_source), isNotNull);
  });

  test('the file store keeps the authors of a part and its extra mark, and a list from before '
      'version 2 counts as stale', () async {
    final dir = await Directory.systemTemp.createTemp('series');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileSeriesStore(dir);
    const SeriesParts dune = (
      name: 'Dune',
      parts: [
        (
          number: 7,
          title: 'Hunters of Dune',
          year: 2006,
          released: null,
          source: 'wikidata:Q7',
          creator: 'Brian Herbert, Kevin J. Anderson',
          cover: null,
          extra: true,
        ),
      ],
    );
    await store.write('openlibrary:OL1W', dune, fetched: now);
    expect((await store.read('openlibrary:OL1W'))!.series.parts, dune.parts);
    final file = File(
      '${dir.path}/series/${FileSeriesStore.fileNameFor('openlibrary:OL1W')}',
    );
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>
      ..remove('version');
    await file.writeAsString(jsonEncode(json));
    final old = await store.read('openlibrary:OL1W');
    expect(old!.series.parts, dune.parts);
    expect(old.fetched.year, 1970);
  });

  test('the file store keeps a part\'s date and cover; a list from before version 5 counts as stale', () async {
    final dir = await Directory.systemTemp.createTemp('series');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileSeriesStore(dir);
    const SeriesParts dated = (
      name: 'The Lord of the Rings',
      parts: [
        (
          number: 4,
          title: 'The Hunt for Gollum',
          year: 2027,
          released: Released(2027, 12, 17),
          source: 'tmdb:movie:1',
          creator: null,
          cover: 'https://image.tmdb.org/t/p/w342/gollum.jpg',
          extra: false,
        ),
      ],
    );
    await store.write(_source, dated, fetched: now);
    final stored = await store.read(_source);
    expect(stored!.series.parts, dated.parts);
    expect(stored.fetched.toUtc(), now.toUtc());
    final file = File(
      '${dir.path}/series/${FileSeriesStore.fileNameFor(_source)}',
    );
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(json['version'], 5);
    await file.writeAsString(jsonEncode({...json, 'version': 4}));
    final old = await store.read(_source);
    expect(old!.series.parts, dated.parts);
    expect(old.fetched, DateTime.utc(1970));
  });

  group('refresh (the daily series check)', () {
    const SeriesParts withUpcoming = (
      name: 'The Lord of the Rings',
      parts: [
        (
          number: 1,
          title: 'The Fellowship of the Ring',
          year: 2001,
          released: Released(2001, 12, 18),
          source: _source,
          creator: null,
          cover: null,
          extra: false,
        ),
        (
          number: 4,
          title: 'The Hunt for Gollum',
          year: 2027,
          released: Released(2027, 12, 17),
          source: 'tmdb:movie:1',
          creator: null,
          cover: null,
          extra: false,
        ),
      ],
    );

    test(
      'fetches when nothing is stored, then not again within a day',
      () async {
        final b = build(series: {_source: withUpcoming});
        final first = await b.service.refresh(_fellowship, now: now);
        expect(first.parts!.parts, withUpcoming.parts);
        expect(first.failure, isNull);
        expect(b.fake.calls, ['series:$_source']);
        final again = await b.service.refresh(
          _fellowship,
          now: now.add(const Duration(hours: 20)),
        );
        expect(again.parts!.parts, withUpcoming.parts);
        expect(b.fake.calls, hasLength(1));
        // A day on, with a part still ahead: due.
        await b.service.refresh(
          _fellowship,
          now: now.add(const Duration(days: 1)),
        );
        expect(b.fake.calls, hasLength(2));
      },
    );

    test('with nothing ahead it waits a week, as the details do', () async {
      final b = build();
      await b.service.refresh(_fellowship, now: now);
      await b.service.refresh(
        _fellowship,
        now: now.add(const Duration(days: 6)),
      );
      expect(b.fake.calls, hasLength(1));
      await b.service.refresh(
        _fellowship,
        now: now.add(const Duration(days: 7)),
      );
      expect(b.fake.calls, hasLength(2));
    });

    test('a failed fetch gives the stored list and the failure', () async {
      final b = build();
      await b.service.refresh(_fellowship, now: now);
      final failing = build(failure: LookupFailure.offline);
      await failing.store.write(
        _source,
        _lotr,
        fetched: now.subtract(const Duration(days: 8)),
        asked: _lotr.name,
      );
      final result = await failing.service.refresh(_fellowship, now: now);
      expect(result.parts!.parts, _lotr.parts);
      expect(result.failure!.failure, LookupFailure.offline);
      // Told not to ask: the stored list, no call, no failure.
      final quiet = await failing.service.refresh(
        _fellowship,
        now: now,
        askLookup: false,
      );
      expect(quiet.parts!.parts, _lotr.parts);
      expect(quiet.failure, isNull);
      expect(failing.fake.calls, hasLength(1));
    });

    test('hasUpcoming: a part dated ahead of today', () {
      final today = DateTime(2026, 10, 29);
      expect(SeriesService.hasUpcoming(withUpcoming, today), isTrue);
      expect(SeriesService.hasUpcoming(_lotr, today), isFalse);
      expect(
        SeriesService.hasUpcoming(withUpcoming, DateTime(2027, 12, 17)),
        isFalse,
      );
    });
  });
}
