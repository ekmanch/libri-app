import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/lookup/music_lookup.dart';
import 'package:library_app/data/lookup/music_source.dart';
import 'package:library_app/data/lookup/track_info.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/features/entry/music_lookup_controller.dart';

/// A music source that answers each page from [answer] and each album's
/// date from [dates], recording what was asked. [gate] holds the dates
/// until opened.
class _Scripted extends LookupSource implements MusicSource {
  _Scripted(this.answer);

  MusicPage Function(MusicRequest request) answer;
  final dates = <String, Released>{};
  final asked = <MusicRequest>[];
  final datesAsked = <String>[];
  LookupFailure? failure;
  Completer<void>? gate;

  @override
  String get id => 'deezer';

  @override
  Set<MediaType> get types => const {MediaType.music};

  @override
  Future<MusicPage> musicPage(
    MusicRequest request, {
    int limit = musicPageSize,
  }) async {
    asked.add(request);
    if (failure case final failure?) throw LookupException(failure);
    return answer(request);
  }

  @override
  Future<Released?> releaseDate(String source) async {
    datesAsked.add(source);
    await gate?.future;
    return dates[source];
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
  }) async => null;

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async =>
      null;

  @override
  Future<List<TrackInfo>> albumTracks(String albumSource) async => const [];

  @override
  Future<String?> artistPhotoUrl(String name) async => null;
}

LookupMatch _album(int n, {Released? released}) => LookupMatch(
  type: MediaType.music,
  title: 'Album $n',
  source: 'deezer:album:$n',
  released: released,
);

LookupMatch _song(
  int n,
  String title, {
  int album = 1,
  Released? released = const Released(2020),
}) => LookupMatch(
  type: MediaType.music,
  title: title,
  source: 'deezer:track:$n',
  album: 'Album $album',
  albumSource: 'deezer:album:$album',
  released: released,
);

/// Lets the pages and dates asked so far answer.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const ghost = ArtistHit(source: 'deezer:artist:7', name: 'Ghost');
  const dated = Released(2020);

  /// A list of [total] dated albums, a full page at a time.
  MusicPage paged(MusicRequest request, {int total = 60}) {
    final end = (request.cursor + musicPageSize).clamp(0, total);
    return MusicPage(
      matches: [
        for (var n = request.cursor; n < end; n++) _album(n, released: dated),
      ],
      total: total,
      next: end < total ? end : null,
      artists: request.cursor == 0 ? const [ghost] : const [],
    );
  }

  (MusicLookupController, _Scripted) build(
    MusicPage Function(MusicRequest) answer,
  ) {
    final source = _Scripted(answer);
    final music = MusicLookupController(LookupService([source]));
    addTearDown(music.dispose);
    return (music, source);
  }

  test('pages of 25, the next only when asked, with the total and the '
      'artists of the first', () async {
    final (music, source) = build(paged);
    music.search(' ghost ');
    expect(music.current.searching, isTrue);
    await _settle();
    expect(music.query, 'ghost');
    expect(music.current.searching, isFalse);
    expect(music.current.matches, hasLength(25));
    expect(music.current.total, 60);
    expect(music.artists, [ghost]);
    expect(source.asked, hasLength(1));

    music.more();
    expect(music.current.loadingMore, isTrue);
    // Nothing is asked twice while a page is on its way.
    music.more();
    await _settle();
    expect(music.current.matches, hasLength(50));
    expect(source.asked.map((r) => r.cursor), [0, 25]);
    music.more();
    await _settle();
    expect(music.current.matches, hasLength(60));
    expect(music.current.next, isNull);
    music.more();
    await _settle();
    expect(source.asked, hasLength(3));
    // The same search again asks nothing.
    music.search('ghost');
    await _settle();
    expect(source.asked, hasLength(3));
  });

  test('a page under half full asks the next at once, from where the '
      'source says it starts', () async {
    final (music, source) = build(
      (request) => switch (request.cursor) {
        0 => MusicPage(
          matches: [for (var n = 0; n < 5; n++) _album(n, released: dated)],
          total: 40,
          next: 25,
        ),
        25 => MusicPage(
          matches: [for (var n = 5; n < 20; n++) _album(n, released: dated)],
          total: 40,
          next: 50,
        ),
        _ => const MusicPage(total: 40),
      },
    );
    music.search('ghost');
    await _settle();
    await _settle();
    // 5 rows brought the next page; its 15 are over half, so it stops.
    expect(source.asked.map((r) => r.cursor), [0, 25]);
    expect(music.current.matches, hasLength(20));
    expect(music.current.next, 50);
  });

  test(
    'the switch lists the other scope when first shown and keeps both',
    () async {
      final (music, source) = build(paged);
      music.search('ghost');
      await _settle();
      music.setScope(MusicScope.songs);
      expect(music.of(MusicScope.albums).matches, hasLength(25));
      await _settle();
      expect(source.asked.last.scope, MusicScope.songs);
      expect(music.current.matches, hasLength(25));
      music.setScope(MusicScope.albums);
      await _settle();
      expect(source.asked, hasLength(2));
    },
  );

  test("an artist's songs are listed once each and counted only when all "
      'are listed; back returns to the search', () async {
    final (music, source) = build((request) {
      if (request.list is MusicSearch) return paged(request);
      expect(
        request.list,
        const MusicArtist(source: 'deezer:artist:7', name: 'Ghost'),
      );
      return switch (request.cursor) {
        0 => MusicPage(
          matches: [
            for (var n = 0; n < 20; n++) _song(n, 'Song $n'),
            _song(20, 'Mary on a Cross'),
          ],
          next: 3,
        ),
        _ => MusicPage(
          matches: [
            // The single repeats its album's song.
            _song(21, 'Mary On A Cross', album: 2),
            _song(22, 'Rats', album: 2),
          ],
        ),
      };
    });
    music
      ..setScope(MusicScope.songs)
      ..search('ghost');
    await _settle();
    music.openArtist(ghost);
    expect(music.current.matches, isEmpty);
    await _settle();
    expect(music.artist, ghost);
    expect(music.current.matches, hasLength(21));
    expect(music.current.total, isNull);
    music.more();
    await _settle();
    expect(
      music.current.matches.map((m) => m.source),
      contains('deezer:track:22'),
    );
    expect(
      music.current.matches.map((m) => m.source),
      isNot(contains('deezer:track:21')),
    );
    expect(music.current.total, 22);

    final asked = source.asked.length;
    music.closeArtist();
    await _settle();
    expect(music.artist, isNull);
    expect(music.current.matches, hasLength(25));
    // The search's page was remembered.
    expect(source.asked, hasLength(asked));
    // Other words leave the artist.
    music
      ..openArtist(ghost)
      ..search('opeth');
    await _settle();
    expect(music.artist, isNull);
    expect(source.asked.last.list, const MusicSearch('opeth'));
  });

  test('the years of rows without one are asked album by album, once, and '
      'stopped by another search', () async {
    final (music, source) = build(
      (request) => MusicPage(
        matches: request.list == const MusicSearch('ghost')
            ? [_album(1), _album(2), _album(4, released: dated)]
            : [_album(9)],
      ),
    );
    source.dates.addAll({
      'deezer:album:1': const Released(2025),
      'deezer:album:9': const Released(1999),
    });
    source.gate = Completer<void>();
    music.search('ghost');
    await _settle();
    // One at a time.
    expect(source.datesAsked, ['deezer:album:1']);
    expect(music.releasedOf(music.current.matches.first), isNull);

    music.search('opeth');
    source.gate!.complete();
    source.gate = null;
    await _settle();
    await _settle();
    // Album 2 was never asked: the search it was for is gone.
    expect(source.datesAsked, ['deezer:album:1', 'deezer:album:9']);
    expect(music.releasedOf(_album(9)), const Released(1999));
    expect(music.years['deezer:album:1'], const Released(2025));
  });

  test('two songs of one album ask its year once, and a dated row asks '
      'nothing', () async {
    final (music, source) = build(
      (request) => MusicPage(
        matches: [
          _song(31, 'A', album: 3, released: null),
          _song(32, 'B', album: 3, released: null),
          _album(4, released: dated),
        ],
      ),
    );
    source.dates['deezer:album:3'] = const Released(2018, 6, 1);
    music
      ..setScope(MusicScope.songs)
      ..search('ghost');
    await _settle();
    await _settle();
    expect(source.datesAsked, ['deezer:album:3']);
    expect(music.current.matches.map((m) => music.releasedOf(m)?.year), [
      2018,
      2018,
      2020,
    ]);
  });

  test('a first page that fails says why and can be asked again; a later '
      'one keeps the rows', () async {
    final (music, source) = build(paged);
    source.failure = LookupFailure.offline;
    music.search('ghost');
    await _settle();
    expect(music.current.failure, LookupFailure.offline);
    expect(music.current.loaded, isFalse);
    source.failure = null;
    music.retry();
    await _settle();
    expect(music.current.failure, isNull);
    expect(music.current.matches, hasLength(25));

    source.failure = LookupFailure.other;
    music.more();
    await _settle();
    expect(music.current.moreFailed, isTrue);
    expect(music.current.matches, hasLength(25));
    // Scrolling does not ask again by itself.
    music.more();
    await _settle();
    expect(source.asked, hasLength(3));
    source.failure = null;
    music.retry();
    await _settle();
    expect(music.current.moreFailed, isFalse);
    expect(music.current.matches, hasLength(50));
  });

  test('an empty search clears everything', () async {
    final (music, _) = build(paged);
    music.search('ghost');
    await _settle();
    music.search('  ');
    expect(music.query, '');
    expect(music.current.matches, isEmpty);
    expect(music.artists, isEmpty);
    expect(music.current.loaded, isFalse);
  });
}
