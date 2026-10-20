import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/track_list_service.dart';
import 'package:library_app/data/lookup/track_list_store.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/dev/fake_lookup.dart';

Entry album(String id, {String? title, String? source}) => Entry(
  id: id,
  type: MediaType.music,
  title: title ?? id,
  creator: 'Alice in Chains',
  status: EntryStatus.done,
  added: DateTime(2026),
  kind: EntryKind.album,
  source: source,
);

void main() {
  late FakeLookupSource fake;
  late TrackListStore store;

  TrackListService service() => TrackListService(
    lookups: LookupService([fake]),
    resolver: ArtworkResolver(lookups: LookupService([fake])),
    store: store,
  );

  setUp(() {
    fake = FakeLookupSource();
    store = MemoryTrackListStore();
  });

  test(
    'an album with a source is fetched once, then served from the store',
    () async {
      final s = service();
      final dirt = album(
        'music/dirt',
        title: 'Dirt',
        source: 'deezer:album:91627',
      );
      final first = await s.load(dirt);
      expect(first!.fromCache, isFalse);
      expect(first.tracks.length, 13);
      expect(first.tracks.first, (
        id: 'deezer:track:1016550',
        title: 'Them Bones',
      ));
      final again = await s.load(dirt);
      expect(again!.fromCache, isTrue);
      expect(fake.calls.where((c) => c.startsWith('tracks:')).length, 1);
      // No cover lookup was needed: the source was known.
      expect(fake.calls.where((c) => c.startsWith('match:')), isEmpty);
    },
  );

  test('an album without a source goes through the device match', () async {
    final s = service();
    final list = await s.load(
      album('music/dirt-alice-in-chains', title: 'Dirt'),
    );
    expect(list!.tracks.length, 13);
    expect(fake.calls, ['match:Dirt:music', 'tracks:fake:dirt']);
  });

  test('no list at the source is null; offline is an error', () async {
    final s = service();
    expect(await s.load(album('music/x', title: 'Nothing Here')), isNull);
    fake = FakeLookupSource(failure: LookupFailure.offline);
    expect(
      service().load(
        album('music/d', title: 'Dirt', source: 'deezer:album:91627'),
      ),
      throwsA(isA<LookupException>()),
    );
    // Without a source the match itself fails offline; still an error,
    // not a miss.
    expect(
      service().load(album('music/dirt-alice-in-chains', title: 'Dirt')),
      throwsA(
        isA<LookupException>().having(
          (e) => e.failure,
          'failure',
          LookupFailure.offline,
        ),
      ),
    );
  });

  test('prune keeps the lists of the albums given', () async {
    final s = service();
    final dirt = album(
      'music/dirt',
      title: 'Dirt',
      source: 'deezer:album:91627',
    );
    final dark = album('music/dark', title: 'The Dark Side of the Moon');
    await s.load(dirt);
    await s.load(dark);
    await s.prune([dirt]);
    expect(await store.read('deezer:album:91627'), isNotNull);
    expect(await store.read('fake:the-dark-side-of-the-moon'), isNull);
  });

  test('the file store round-trips and prunes by album id', () async {
    final dir = await Directory.systemTemp.createTemp('tracks');
    addTearDown(() => dir.delete(recursive: true));
    final files = FileTrackListStore(dir);
    await files.write('deezer:album:91627', const [
      (id: 'deezer:track:1', title: 'Them Bones'),
    ]);
    expect(
      FileTrackListStore.fileNameFor('deezer:album:91627'),
      'deezer-album-91627.json',
    );
    expect(await files.read('deezer:album:91627'), [
      (id: 'deezer:track:1', title: 'Them Bones'),
    ]);
    expect(await files.read('deezer:album:2'), isNull);
    await files.write('fake:dirt', const [(id: 't', title: 'Dirt')]);
    await files.prune({'fake:dirt'});
    expect(await files.read('deezer:album:91627'), isNull);
    expect(await files.read('fake:dirt'), isNotNull);
  });
}
