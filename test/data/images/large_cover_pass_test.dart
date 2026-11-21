import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/images/image_cache_store.dart';
import 'package:library_app/data/images/image_fetcher.dart';
import 'package:library_app/data/images/large_cover_pass.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/net/http_transport.dart';
import 'package:library_app/data/net/network_kind.dart';

const _tmdb = 'https://image.tmdb.org/t/p';

/// Answers a source id with its poster at the list size.
class _Source extends LookupSource {
  final asks = <String>[];
  LookupFailure? failure;

  @override
  String get id => 'tmdb';
  @override
  Set<MediaType> get types => MediaType.values.toSet();
  @override
  bool issued(String source) => true;

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
  }) async => null;

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    asks.add(source);
    if (failure case final failure?) throw LookupException(failure);
    return source.endsWith(':none')
        ? null
        : '$_tmdb/w342/${source.split(':').last}.jpg';
  }
}

/// Answers with the URL's bytes and records the order; [status] fails the
/// URLs it names.
class _Fetcher implements ImageFetcher {
  final calls = <String>[];
  final status = <String, int>{};
  bool offline = false;
  var inFlight = 0;
  var mostInFlight = 0;

  @override
  Future<Uint8List> fetch(Uri url) async {
    calls.add('$url');
    inFlight++;
    if (inFlight > mostInFlight) mostInFlight = inFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (offline) throw const NetworkUnreachable('offline');
      if (status['$url'] case final status?) {
        throw ImageFetchException(status);
      }
      return Uint8List.fromList('$url'.codeUnits);
    } finally {
      inFlight--;
    }
  }
}

Entry _movie(String name, {String? coverFrom}) => Entry(
  id: 'movies/$name',
  type: MediaType.movies,
  title: name,
  status: EntryStatus.want,
  added: DateTime(2026),
  source: 'tmdb:movie:$name',
  coverFrom: coverFrom,
);

void main() {
  late Directory dir;
  late _Source source;
  late _Fetcher fetcher;
  late ArtworkResolver resolver;
  late ImageCacheStore small;
  late ImageCacheStore large;

  LargeCoverPass pass({bool mobile = false}) => LargeCoverPass(
    resolver: resolver,
    small: small,
    large: large,
    network: FixedNetworkKind(mobile: mobile),
    idleCheck: const Duration(milliseconds: 1),
    log: (_) {},
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('large');
    source = _Source();
    fetcher = _Fetcher();
    resolver = ArtworkResolver(lookups: LookupService([source]));
    small = ImageCacheStore(dir, fetcher: fetcher);
    large = ImageCacheStore(dir, fetcher: fetcher, folder: 'images_large');
  });
  tearDown(() => dir.delete(recursive: true));

  Library library(List<Entry> entries) => Library(entries: entries);

  test('every cover gets its list image first, then the larger versions, '
      'a few at a time and apart from the list images', () async {
    final entries = [for (var i = 0; i < 8; i++) _movie('m$i')];
    final p = pass();
    final end = await p.run(library(entries), wifiOnly: () => false);
    expect(end, LargeCoverRunEnd.done);

    expect(fetcher.calls.take(8), [
      for (var i = 0; i < 8; i++) '$_tmdb/w342/m$i.jpg',
    ]);
    expect(fetcher.calls.skip(8).toSet(), {
      for (var i = 0; i < 8; i++) '$_tmdb/w780/m$i.jpg',
    });
    expect(fetcher.mostInFlight, 3);
    expect(p.progress!.wanted, 8);
    expect(p.progress!.fetched, 8);
    expect(await small.size(), (
      files: 8,
      bytes: 8 * '$_tmdb/w342/m0.jpg'.length,
    ));
    expect((await large.size()).files, 8);
    expect(large.imagesDirectory.path, endsWith('images_large'));
    expect(small.cachedFile('$_tmdb/w780/m0.jpg'), isNull);
    expect(large.cachedFile('$_tmdb/w780/m0.jpg'), isNotNull);
  });

  test('a later run fetches only what is missing', () async {
    final entries = [_movie('a'), _movie('b')];
    await pass().run(library(entries), wifiOnly: () => false);
    fetcher.calls.clear();
    // A new session: nothing is remembered but the files and the records.
    final p = pass();
    await p.run(library([...entries, _movie('c')]), wifiOnly: () => false);
    expect(fetcher.calls, ['$_tmdb/w342/c.jpg', '$_tmdb/w780/c.jpg']);
    expect(p.progress!.wanted, 3);
    expect(p.progress!.fetched, 1);
  });

  test('nothing is asked on mobile data while Only on Wi-Fi is on, and '
      'with it off the run goes ahead', () async {
    final entries = [_movie('a')];
    final p = pass(mobile: true);
    expect(
      await p.run(library(entries), wifiOnly: () => true),
      LargeCoverRunEnd.interrupted,
    );
    expect(source.asks, isEmpty);
    expect(fetcher.calls, isEmpty);
    expect(
      await p.run(library(entries), wifiOnly: () => false),
      LargeCoverRunEnd.done,
    );
    expect(fetcher.calls.length, 2);
  });

  test('offline ends the run and removes nothing', () async {
    final entries = [_movie('a'), _movie('b')];
    await pass().run(library(entries), wifiOnly: () => false);
    fetcher.offline = true;
    final p = pass();
    expect(
      await p.run(library([_movie('c')]), wifiOnly: () => false),
      LargeCoverRunEnd.interrupted,
    );
    expect((await large.size()).files, 2);
  });

  test(
    'a deleted entry and a changed cover lose their larger version',
    () async {
      final a = _movie('a');
      final b = _movie('b');
      await pass().run(library([a, b]), wifiOnly: () => false);
      expect(large.cachedFile('$_tmdb/w780/b.jpg'), isNotNull);

      // b is deleted; a shows another match's cover now.
      final changed = _movie('a', coverFrom: 'tmdb:movie:other');
      final end = await pass().run(library([changed]), wifiOnly: () => false);
      expect(end, LargeCoverRunEnd.done);
      expect(
        File(large.fileFor('$_tmdb/w780/a.jpg').path).existsSync(),
        isFalse,
      );
      expect(
        File(large.fileFor('$_tmdb/w780/b.jpg').path).existsSync(),
        isFalse,
      );
      expect(
        File(large.fileFor('$_tmdb/w780/other.jpg').path).existsSync(),
        isTrue,
      );
      expect((await large.size()).files, 1);
    },
  );

  test('nothing is removed while a cover could not be looked up', () async {
    final a = _movie('a');
    await pass().run(library([a]), wifiOnly: () => false);
    source.failure = LookupFailure.other;
    final end = await pass().run(
      library([a, _movie('b')]),
      wifiOnly: () => false,
    );
    expect(end, LargeCoverRunEnd.done);
    expect((await large.size()).files, 1);
  });

  test('an entry with no cover, and one of the owner\'s own, have nothing '
      'fetched', () async {
    final p = pass();
    await p.run(
      library([
        _movie('none'),
        _movie('own', coverFrom: 'repo:movies/own.jpg'),
      ]),
      wifiOnly: () => false,
    );
    expect(fetcher.calls, isEmpty);
    expect(p.progress!.wanted, 0);
  });

  test('a 429 leaves that server alone for the session; one 403 is only '
      'a missing file', () async {
    final entries = [for (var i = 0; i < 6; i++) _movie('m$i')];
    fetcher.status['$_tmdb/w780/m0.jpg'] = 403;
    final p = LargeCoverPass(
      resolver: resolver,
      small: small,
      large: large,
      concurrency: 1,
      idleCheck: const Duration(milliseconds: 1),
      log: (_) {},
    );
    await p.run(library(entries), wifiOnly: () => false);
    expect((await large.size()).files, 5);

    fetcher.status['$_tmdb/w780/n0.jpg'] = 429;
    fetcher.calls.clear();
    await p.run(
      library([...entries, _movie('n0'), _movie('n1')]),
      wifiOnly: () => false,
    );
    expect(fetcher.calls.where((u) => u.contains('/w780/')), [
      '$_tmdb/w780/n0.jpg',
    ]);
  });

  test('a halt stops the run before the next fetch', () async {
    final entries = [for (var i = 0; i < 6; i++) _movie('m$i')];
    final p = pass();
    final run = p.run(library(entries), wifiOnly: () => false);
    p.halt();
    expect(await run, LargeCoverRunEnd.halted);
    expect(fetcher.calls.length, lessThan(12));
    // The next run takes it up again.
    expect(
      await p.run(library(entries), wifiOnly: () => false),
      LargeCoverRunEnd.done,
    );
    expect((await large.size()).files, 6);
  });
}
