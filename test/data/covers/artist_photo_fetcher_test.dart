import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/artist_photo_fetcher.dart';
import 'package:library_app/data/covers/artist_photos.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/lookup/apple_artists.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/net/network_kind.dart';
import 'package:library_app/dev/fake_artists.dart';
import 'package:library_app/dev/fake_covers.dart';

Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);

Entry music(
  String title,
  String? artist, {
  bool song = false,
  String? album,
  DateTime? added,
}) => Entry(
  id: 'music/${title.toLowerCase().replaceAll(' ', '-')}',
  type: MediaType.music,
  title: title,
  creator: artist,
  status: EntryStatus.done,
  added: added ?? DateTime(2026, 11, 1),
  kind: song ? EntryKind.song : EntryKind.album,
  album: album,
);

/// Apple failing as told, else the fake.
class _Apple extends FakeAppleArtists {
  _Apple({super.noPhoto});

  LookupFailure? failure;
  final failFor = <String>{};
  bool refused = false;

  @override
  bool get stopped => refused;

  @override
  Future<ArtistFound> find(String name, Iterable<String> owned) async {
    calls.add('find:$name:${owned.join('|')}');
    if (failure case final failure?) {
      if (failure == LookupFailure.rateLimited) refused = true;
      throw LookupException(failure);
    }
    if (failFor.contains(name)) {
      throw const LookupException(LookupFailure.other, status: 500);
    }
    return super.find(name, owned).whenComplete(calls.removeLast);
  }
}

void main() {
  const record = 'artists/_missing.json';
  const backfilled =
      '{\n  "version": 1,\n  "backfilled": "2026-11-15",\n  "artists": {}\n}\n';
  late DateTime now;
  late _Apple apple;

  setUp(() {
    now = DateTime(2026, 11, 20, 12);
    apple = _Apple();
  });

  final library = Library(
    entries: [
      music('Mezzanine', 'Massive Attack'),
      music('Blue Lines', 'massive attack'),
      music('Teardrop', 'Massive Attack', song: true, album: 'Mezzanine'),
      music('Untrue', 'Burial'),
      music('Archangel', 'Burial', song: true, album: 'Untrue'),
      music('Dancing Queen', 'ABBA', song: true, album: 'Arrival'),
      music('Now 42', 'Various Artists'),
      music('Mystery', null),
      music('Bang', '!!!'),
    ],
  );

  Future<(CoverStore, ArtistPhotoFetcher)> fetcher({
    Map<String, Uint8List> files = const {},
    bool mobile = false,
  }) async {
    final covers = fakeCoverStore(files: files);
    await covers.refresh();
    return (
      covers,
      ArtistPhotoFetcher(
        covers: covers,
        apple: apple,
        network: FixedNetworkKind(mobile: mobile),
        now: () => now,
        log: (_) {},
      ),
    );
  }

  test('the artists that can have a photo: one per name whatever its case, '
      'with their albums and the albums their songs name; Various Artists, '
      'no artist and a name without letters are left out', () {
    final artists = photoArtists(library);
    expect(artists.map((a) => a.name), ['Massive Attack', 'Burial', 'ABBA']);
    expect(artists.first.slug, 'massive-attack');
    expect(artists.first.owned, ['Mezzanine', 'Blue Lines', 'Mezzanine']);
    expect(artists.last.owned, ['Arrival']);
    expect(ownedTitlesOf(library, 'burial'), ['Untrue', 'Untrue']);
  });

  test('nothing is fetched until the desktop\'s first run is seen', () async {
    final (covers, f) = await fetcher();
    expect(covers.backfilled, isNull);
    expect(f.due(library), isEmpty);
    expect(await f.run(library, wifiOnly: true), 0);
    expect(apple.calls, isEmpty);

    // A record without the day is not enough either.
    final (_, g) = await fetcher(
      files: {record: bytes('{\n  "version": 1,\n  "artists": {}\n}\n')},
    );
    expect(g.due(library), isEmpty);
  });

  test('after it, only artists with no file and no fresh record are asked, '
      'in name order; a photo becomes the artist\'s file, nothing found is '
      'recorded, and both wait for the sync', () async {
    apple = _Apple(noPhoto: {'burial'});
    final (covers, f) = await fetcher(
      files: {
        record: bytes(backfilled),
        'artists/massive-attack.jpg': bytes('has one'),
      },
    );
    expect(f.due(library).map((a) => a.name), ['ABBA', 'Burial']);
    expect(await f.run(library, wifiOnly: true), 2);
    expect(apple.calls, ['find:ABBA:Arrival', 'find:Burial:Untrue|Untrue']);
    expect(covers.artistPhoto('ABBA'), isNotNull);
    expect(covers.artistPhoto('Burial'), isNull);
    expect(covers.missing.artists['burial']!.reason, MissingReason.noPhoto);
    expect(covers.missing.artists['burial']!.tried, DateTime.utc(2026, 11, 20));
    expect(covers.pendingCount, 2);
    final put = covers.pending.whereType<ArtistPhotoPut>().single;
    expect(put.picked, isFalse);
    expect(put.summary, 'Add a photo of ABBA');

    // Settled: nobody is asked again.
    apple.calls.clear();
    expect(await f.run(library, wifiOnly: true), 0);
    expect(apple.calls, isEmpty);
    expect(artistPhotoCounts(library, covers), (have: 2, total: 3));
  });

  test('an artist on the record is asked again after ninety days, or once '
      'an entry by them is added on a later day', () async {
    const tried =
        '{\n  "version": 1,\n  "backfilled": "2026-11-15",\n  "artists": {\n'
        '    "burial": {"name": "Burial", "tried": "2026-11-15", '
        '"reason": "no-match"}\n  }\n}\n';
    final files = {
      record: bytes(tried),
      'artists/massive-attack.jpg': bytes('x'),
      'artists/abba.jpg': bytes('x'),
    };
    final (_, f) = await fetcher(files: files);
    expect(f.due(library), isEmpty);
    now = DateTime(2027, 2, 13);
    expect(f.due(library).map((a) => a.name), ['Burial']);
    now = DateTime(2026, 11, 20, 12);
    final more = Library(
      entries: [
        ...library.entries,
        music('Kindred', 'Burial', added: DateTime(2026, 11, 18)),
      ],
    );
    expect(f.due(more).map((a) => a.name), ['Burial']);
  });

  test('on mobile data with Only on Wi-Fi on, nothing is asked', () async {
    final (_, f) = await fetcher(
      files: {record: bytes(backfilled)},
      mobile: true,
    );
    expect(await f.run(library, wifiOnly: true), 0);
    expect(apple.calls, isEmpty);
    expect(await f.run(library, wifiOnly: false), 3);
  });

  test(
    'a refusal stops the work for the session and records nothing; '
    'offline ends the run; another failure passes that artist over',
    () async {
      var (covers, f) = await fetcher(files: {record: bytes(backfilled)});
      apple.failure = LookupFailure.rateLimited;
      expect(await f.run(library, wifiOnly: false), 0);
      expect(apple.calls.length, 1);
      expect(covers.pendingCount, 0);
      apple.failure = null;
      expect(f.due(library), isEmpty);

      apple = _Apple()..failure = LookupFailure.offline;
      (covers, f) = await fetcher(files: {record: bytes(backfilled)});
      expect(await f.run(library, wifiOnly: false), 0);
      expect(apple.calls.length, 1);
      apple.failure = null;
      expect(f.due(library).length, 3);

      apple = _Apple()..failFor.add('ABBA');
      (covers, f) = await fetcher(files: {record: bytes(backfilled)});
      expect(await f.run(library, wifiOnly: false), 2);
      expect(covers.missing.artists, isEmpty);
      expect(covers.artistPhoto('ABBA'), isNull);
      // Not until the next session.
      expect(f.due(library), isEmpty);
    },
  );
}
