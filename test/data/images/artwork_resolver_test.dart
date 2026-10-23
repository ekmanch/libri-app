import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_providers.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/images/image_cache_store.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/dev/fake_images.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/lookup/music_source.dart';
import 'package:library_app/data/lookup/track_info.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/storage/json_file.dart';

/// A source that records every ask and answers from [covers] (by title)
/// and [bySource] (by id), or throws [failure]. [gate] holds every answer
/// until opened, to watch how many run at once.
class _Stub extends LookupSource implements MusicSource {
  _Stub();

  final covers = <String, String>{};
  final bySource = <String, String>{};
  final photos = <String, String>{};
  final asks = <String>[];
  LookupFailure? failure;
  int? failureStatus;
  Completer<void>? gate;
  var inFlight = 0;
  var mostInFlight = 0;

  @override
  String get id => 'stub';
  @override
  Set<MediaType> get types => MediaType.values.toSet();
  @override
  bool issued(String source) => true;

  Future<T> _run<T>(String ask, T Function() answer) async {
    asks.add(ask);
    inFlight++;
    if (inFlight > mostInFlight) mostInFlight = inFlight;
    try {
      if (gate case final gate?) await gate.future;
      if (failure case final failure?) {
        throw LookupException(failure, status: failureStatus);
      }
      return answer();
    } finally {
      inFlight--;
    }
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async => const [];

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) => _run('match:$title:${type.name}:$year:$creator', () {
    final url = covers[title];
    return url == null
        ? null
        : LookupMatch(
            type: type,
            title: title,
            source: 'stub:$title',
            coverUrl: '$url-small',
            largeCoverUrl: url,
          );
  });

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) =>
      _run('cover:$source', () => bySource[source]);

  @override
  Future<List<TrackInfo>> albumTracks(String albumSource) async => const [];

  @override
  Future<String?> artistPhotoUrl(String name) =>
      _run('photo:$name', () => photos[name]);
}

Entry entry(
  String id, {
  MediaType type = MediaType.movies,
  String? title,
  int? year,
  String? creator,
  String? source,
  EntryKind? kind,
  String? album,
}) => Entry(
  id: id,
  type: type,
  title: title ?? id,
  released: year == null ? null : Released(year),
  creator: creator,
  status: EntryStatus.want,
  added: DateTime(2026),
  source: source,
  kind: kind,
  album: album,
);

void main() {
  late Directory dir;
  late _Stub stub;
  late JsonFile file;
  var now = DateTime(2026, 10, 15, 12);

  ArtworkResolver resolver({int concurrency = 2}) {
    final r = ArtworkResolver(
      lookups: LookupService([stub]),
      cache: file,
      concurrency: concurrency,
      now: () => now,
      writeDelay: Duration.zero,
    );
    // Every write lands before the folder goes.
    addTearDown(r.flush);
    return r;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('artwork');
    file = JsonFile(File('${dir.path}/artwork.json'));
    stub = _Stub();
  });
  tearDown(() => dir.delete(recursive: true));

  test('an entry with a source asks its provider for the cover', () async {
    stub.bySource['tmdb:movie:564'] = 'https://img/mummy.jpg';
    final r = resolver();
    final mummy = entry(
      'movies/the-mummy-1999',
      title: 'The Mummy',
      source: 'tmdb:movie:564',
    );
    expect(r.cachedCoverUrl(mummy), isNull);
    expect(await r.coverUrl(mummy), 'https://img/mummy.jpg');
    expect(stub.asks, ['cover:tmdb:movie:564']);
    expect(r.cachedCoverUrl(mummy), 'https://img/mummy.jpg');
    expect(await r.coverUrl(mummy), 'https://img/mummy.jpg');
    expect(stub.asks.length, 1);

    // The record is on disk for the next run.
    await r.flush();
    final again = resolver();
    expect(await again.coverUrl(mummy), 'https://img/mummy.jpg');
    expect(stub.asks.length, 1);
  });

  test(
    'an entry without a source is matched by title, year and creator',
    () async {
      stub.covers['Dracula'] = 'https://img/dracula.jpg';
      stub.covers['Dirt'] = 'https://img/dirt.jpg';
      final r = resolver();
      final dracula = entry(
        'books/dracula-1897',
        type: MediaType.books,
        title: 'Dracula',
        year: 1897,
        creator: 'Bram Stoker',
      );
      expect(await r.coverUrl(dracula), 'https://img/dracula.jpg');
      expect(stub.asks, ['match:Dracula:books:1897:Bram Stoker']);

      // A song is matched by its album, with no year.
      final rooster = entry(
        'music/rooster-alice-in-chains',
        type: MediaType.music,
        title: 'Rooster',
        year: 1992,
        creator: 'Alice in Chains',
        kind: EntryKind.song,
        album: 'Dirt',
      );
      expect(await r.coverUrl(rooster), 'https://img/dirt.jpg');
      expect(stub.asks.last, 'match:Dirt:music:null:Alice in Chains');
    },
  );

  test('a changed title, year, creator or source means a new lookup', () async {
    stub.covers['Dune'] = 'https://img/dune.jpg';
    final r = resolver();
    final dune = entry('movies/dune-2021', title: 'Dune', year: 2021);
    await r.coverUrl(dune);
    expect(r.cachedCoverUrl(dune.copyWith(title: 'Dune: Part One')), isNull);
    stub.bySource['tmdb:movie:438631'] = 'https://img/dune-tmdb.jpg';
    expect(
      await r.coverUrl(dune.copyWith(source: 'tmdb:movie:438631')),
      'https://img/dune-tmdb.jpg',
    );
    expect(stub.asks.length, 2);
  });

  test('a cover from another match is asked by that id, and only it', () async {
    stub.bySource['openlibrary:OL2918756W'] = 'https://img/own.jpg';
    stub.bySource['itunes:123456'] = 'https://img/picked.jpg';
    final r = resolver();
    final shogun = entry(
      'books/shogun-1975',
      type: MediaType.books,
      title: 'Shōgun',
      source: 'openlibrary:OL2918756W',
    );
    expect(await r.coverUrl(shogun), 'https://img/own.jpg');
    final picked = shogun.copyWith(coverFrom: 'itunes:123456');
    // A new cover_from means a new lookup, of the picked id alone.
    expect(r.cachedCoverUrl(picked), isNull);
    expect(await r.coverUrl(picked), 'https://img/picked.jpg');
    expect(stub.asks.last, 'cover:itunes:123456');
    // The match's own cover, for the picker, leaves the record alone.
    expect(await r.ownCoverUrl(picked), 'https://img/own.jpg');
    expect(r.cachedCoverUrl(picked), 'https://img/picked.jpg');
  });

  test('an entry without a source and a picked cover is still matched for '
      'its id', () async {
    stub.covers['Dracula'] = 'https://img/dracula.jpg';
    stub.bySource['itunes:9'] = 'https://img/picked.jpg';
    final r = resolver();
    final dracula = entry(
      'books/dracula-1897',
      type: MediaType.books,
      title: 'Dracula',
    ).copyWith(coverFrom: 'itunes:9');
    expect(await r.coverUrl(dracula), 'https://img/picked.jpg');
    expect(r.cachedSource(dracula), 'stub:Dracula');
  });

  test('a miss is remembered and tried again after a fortnight', () async {
    final r = resolver();
    final nothing = entry('movies/nothing-2000', title: 'Nothing', year: 2000);
    expect(await r.coverUrl(nothing), isNull);
    expect(await r.coverUrl(nothing), isNull);
    expect(stub.asks.length, 1);
    now = now.add(const Duration(days: 15));
    stub.covers['Nothing'] = 'https://img/nothing.jpg';
    expect(await r.coverUrl(nothing), 'https://img/nothing.jpg');
    expect(stub.asks.length, 2);
  });

  test('no failure is ever recorded as a miss, for covers or photos, so '
      'the next session asks again', () async {
    final failures = <(LookupFailure, int?)>[
      (LookupFailure.offline, null), // a timeout too
      (LookupFailure.rateLimited, 429),
      (LookupFailure.notConfigured, null),
      (LookupFailure.other, 500),
      (LookupFailure.other, 503),
      (LookupFailure.other, 404),
      (LookupFailure.other, null), // a malformed answer
    ];
    for (final (i, (failure, status)) in failures.indexed) {
      stub
        ..failure = failure
        ..failureStatus = status;
      final r = resolver();
      final x = entry('movies/x$i', title: 'X$i');
      expect(await r.coverUrl(x), isNull);
      expect(await r.artistPhotoUrl('Artist $i'), isNull);
      await r.flush();
      expect(
        (await file.read())?['entries'] as Map? ?? const {},
        isNot(contains('movies/x$i')),
        reason: '$failure $status',
      );

      // The next session: the provider answers now.
      stub
        ..failure = null
        ..failureStatus = null;
      stub.covers['X$i'] = 'https://img/x$i.jpg';
      stub.photos['Artist $i'] = 'https://img/a$i.jpg';
      final next = resolver();
      expect(await next.coverUrl(x), 'https://img/x$i.jpg');
      expect(await next.artistPhotoUrl('Artist $i'), 'https://img/a$i.jpg');
    }
  });

  test('a real "no cover" is a miss, on disk for the next session', () async {
    final r = resolver();
    final y = entry('movies/y-2000', title: 'Y');
    expect(await r.coverUrl(y), isNull);
    expect(await r.artistPhotoUrl('Nobody'), isNull);
    await r.flush();
    stub.covers['Y'] = 'https://img/y.jpg';
    stub.photos['Nobody'] = 'https://img/nobody.jpg';
    final next = resolver();
    expect(await next.coverUrl(y), isNull);
    expect(await next.artistPhotoUrl('Nobody'), isNull);
    expect(stub.asks, ['match:Y:movies:null:null', 'photo:Nobody']);
  });

  test(
    'the misses of version 1 are looked for again, its covers kept',
    () async {
      final resolved = now.toUtc().toIso8601String();
      final a = entry('movies/a', title: 'A');
      final b = entry('movies/b', title: 'B');
      await file.write({
        'version': 1,
        'entries': {
          'movies/a': {
            'key': ArtworkResolver.keyFor(a),
            'url': 'https://img/a.jpg',
            'resolved': resolved,
          },
          'movies/b': {'key': ArtworkResolver.keyFor(b), 'resolved': resolved},
        },
        'artists': {
          'kate bush': {'key': 'kate bush', 'resolved': resolved},
        },
      });
      stub.covers['B'] = 'https://img/b.jpg';
      stub.photos['Kate Bush'] = 'https://img/kate.jpg';
      final r = resolver();
      expect(await r.coverUrl(a), 'https://img/a.jpg');
      expect(await r.coverUrl(b), 'https://img/b.jpg');
      expect(await r.artistPhotoUrl('Kate Bush'), 'https://img/kate.jpg');
      expect(stub.asks, ['match:B:movies:null:null', 'photo:Kate Bush']);
      await r.flush();
      expect((await file.read())!['version'], 2);
    },
  );

  test(
    'at most two lookups run at once, and a released one never starts',
    () async {
      for (final t in ['A', 'B', 'C', 'D']) {
        stub.covers[t] = 'https://img/$t.jpg';
      }
      final r = resolver();
      await r.load();
      stub.gate = Completer<void>();
      final futures = [
        for (final t in ['A', 'B', 'C', 'D'])
          r.coverUrl(entry('movies/$t', title: t)),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(stub.inFlight, 2);
      r.release('movies/D');
      stub.gate!.complete();
      final results = await Future.wait(futures);
      expect(results, [
        'https://img/A.jpg',
        'https://img/B.jpg',
        'https://img/C.jpg',
        null,
      ]);
      expect(stub.mostInFlight, 2);
      expect(stub.asks.length, 3);
      // Asked again later, D is looked up.
      expect(
        await r.coverUrl(entry('movies/D', title: 'D')),
        'https://img/D.jpg',
      );
    },
  );

  test(
    'artist photos go through the music source and skip Various Artists',
    () async {
      stub.photos['Alice in Chains'] = 'https://img/aic.jpg';
      final r = resolver();
      expect(await r.artistPhotoUrl('Alice in Chains'), 'https://img/aic.jpg');
      expect(r.cachedArtistPhotoUrl('alice in chains'), 'https://img/aic.jpg');
      expect(await r.artistPhotoUrl('Various Artists'), isNull);
      expect(await r.artistPhotoUrl('Nobody'), isNull);
      expect(stub.asks, ['photo:Alice in Chains', 'photo:Nobody']);
    },
  );

  test(
    'forget drops a record; prune drops the records of what is gone',
    () async {
      stub.covers['A'] = 'https://img/A.jpg';
      stub.covers['B'] = 'https://img/B.jpg';
      stub.photos['Kate Bush'] = 'https://img/kate.jpg';
      stub.photos['Old Artist'] = 'https://img/old.jpg';
      final r = resolver();
      final a = entry('movies/A', title: 'A');
      await r.coverUrl(a);
      await r.coverUrl(entry('movies/B', title: 'B'));
      await r.artistPhotoUrl('Kate Bush');
      await r.artistPhotoUrl('Old Artist');

      r.forget('movies/A');
      expect(r.cachedCoverUrl(a), isNull);
      await r.coverUrl(a);
      expect(stub.asks.where((s) => s == 'match:A:movies:null:null').length, 2);

      final kept = await r.prune(entries: [a], artists: ['kate bush']);
      expect(kept, {'https://img/A.jpg', 'https://img/kate.jpg'});
      final json = await file.read();
      expect((json!['entries'] as Map).keys, ['movies/A']);
      expect((json['artists'] as Map).keys, ['kate bush']);
    },
  );

  test('the pruner keeps the images of what is still in the library', () async {
    stub.covers['A'] = 'fake://cover/poster/a';
    stub.covers['B'] = 'fake://cover/poster/b';
    final r = resolver();
    final images = ImageCacheStore(dir, fetcher: FakeImageFetcher());
    final a = entry('movies/A', title: 'A');
    final b = entry('movies/B', title: 'B');
    for (final e in [a, b]) {
      await images.get((await r.coverUrl(e))!);
    }
    expect(images.cachedFile('fake://cover/poster/b'), isNotNull);

    await ArtworkPruner(resolver: r, images: images).run(Library(entries: [a]));
    expect(images.cachedFile('fake://cover/poster/a'), isNotNull);
    expect(images.cachedFile('fake://cover/poster/b'), isNull);
    expect(r.cachedCoverUrl(b), isNull);
  });
}
