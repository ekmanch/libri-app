import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/lookup/episode_info.dart';
import 'package:library_app/data/lookup/episode_service.dart';
import 'package:library_app/data/lookup/episode_store.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/dev/fake_lookup.dart';

const _source = 'tmdb:tv:2190';

final _show = Entry(
  id: 'shows/south-park-1997',
  type: MediaType.shows,
  title: 'South Park',
  status: EntryStatus.inProgress,
  added: DateTime(2026, 1, 1),
  source: _source,
);

const List<EpisodeInfo> _old = [
  (number: 1, title: 'Pilot', aired: Released(2020, 3, 1), runtime: 22),
  (number: 2, title: 'Two', aired: Released(2020, 3, 8), runtime: 22),
];

const List<EpisodeInfo> _airing = [
  (number: 1, title: 'Out', aired: Released(2026, 10, 15), runtime: 22),
  (number: 2, title: null, aired: Released(2026, 10, 22), runtime: null),
];

void main() {
  final now = DateTime(2026, 10, 19, 12);

  setUp(() => seasonClock = () => now);
  tearDown(() => seasonClock = DateTime.now);

  ({EpisodeService service, FakeLookupSource fake, MemoryEpisodeStore store})
  build({LookupFailure? failure, bool configured = true}) {
    final fake = FakeLookupSource(
      failure: failure,
      configured: configured,
      episodesBySeason: {(_source, 1): _old, (_source, 2): _airing},
    );
    final lookups = LookupService([fake]);
    final store = MemoryEpisodeStore();
    return (
      service: EpisodeService(
        lookups: lookups,
        resolver: ArtworkResolver(lookups: lookups),
        store: store,
      ),
      fake: fake,
      store: store,
    );
  }

  group('isSettled', () {
    test('a list fetched today is kept', () {
      expect(
        EpisodeService.isSettled(DateTime(2026, 10, 19, 8), _airing, now),
        isTrue,
      );
    });

    test('an airing season is asked again on a later day', () {
      expect(
        EpisodeService.isSettled(DateTime(2026, 10, 18), _airing, now),
        isFalse,
      );
    });

    test('a season over for a month when fetched is kept for good', () {
      expect(EpisodeService.isSettled(DateTime(2020, 4, 8), _old, now), isTrue);
      expect(
        EpisodeService.isSettled(DateTime(2020, 4, 6), _old, now),
        isFalse,
      );
    });
  });

  test('fetches once, stores, then answers from the phone', () async {
    final b = build();
    expect(await b.service.load(_show, 1).toList(), [
      isA<SeasonEpisodes>()
          .having((e) => e.fromCache, 'fromCache', isFalse)
          .having((e) => e.episodes, 'episodes', _old),
    ]);
    expect(b.fake.calls, ['episodes:$_source:1']);
    final again = await b.service.load(_show, 1).toList();
    expect(again.single!.fromCache, isTrue);
    expect(b.fake.calls, hasLength(1));
  });

  test('a stored airing season shows, then is fetched again', () async {
    final b = build();
    await b.store.write(
      _source,
      2,
      _airing.take(1).toList(),
      fetched: DateTime(2026, 10, 15),
    );
    final answers = await b.service.load(_show, 2).toList();
    expect([for (final a in answers) a!.episodes.length], [1, 2]);
    expect([for (final a in answers) a!.fromCache], [true, false]);
    expect((await b.store.read(_source, 2))!.fetched, now);
  });

  test('offline: the stored list stays, and without one it fails', () async {
    final b = build(failure: LookupFailure.offline);
    await expectLater(
      b.service.load(_show, 2).toList(),
      throwsA(isA<LookupException>()),
    );
    await b.store.write(_source, 2, _airing, fetched: DateTime(2026, 10, 15));
    final answers = await b.service.load(_show, 2).toList();
    expect(answers.single!.fromCache, isTrue);
  });

  test('without the key a stored list still shows', () async {
    final b = build(configured: false);
    await expectLater(
      b.service.load(_show, 2).toList(),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.notConfigured,
        ),
      ),
    );
    expect(b.fake.calls, isEmpty);
    await b.store.write(_source, 2, _airing, fetched: DateTime(2026, 10, 15));
    final answers = await b.service.load(_show, 2).toList();
    expect(answers.single!.episodes, _airing);
  });

  test('a season the lookup has no episodes for ends with null', () async {
    final b = build();
    expect(await b.service.load(_show, 9).toList(), [null]);
  });

  test('the file store keeps seasons per show and prunes gone shows', () async {
    final dir = Directory.systemTemp.createTempSync('libri-episodes-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = FileEpisodeStore(dir);
    await store.write(_source, 1, _old, fetched: now);
    await store.write(_source, 2, _airing, fetched: now);
    await store.write('tmdb:tv:1', 1, _old, fetched: now);
    final read = await FileEpisodeStore(dir).read(_source, 2);
    expect(read!.episodes, _airing);
    expect(read.fetched.isAtSameMomentAs(now), isTrue);
    expect((await store.read(_source, 1))!.episodes, _old);
    await store.prune({_source});
    expect(await store.read('tmdb:tv:1', 1), isNull);
    expect(await store.read(_source, 1), isNotNull);
  });
}
