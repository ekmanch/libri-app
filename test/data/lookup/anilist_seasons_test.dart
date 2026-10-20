import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/anilist_source.dart';
import 'package:library_app/data/lookup/anime_link_store.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/tmdb_source.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';

/// An AniList entry as the chain query returns it, with its relations when
/// [relations] is given.
Map<String, Object?> media(
  int id, {
  String format = 'TV',
  String status = 'FINISHED',
  String? english,
  String? romaji,
  List<int>? start,
  List<int>? end,
  int? episodes,
  int? duration,
  List<Map<String, Object?>>? relations,
}) => {
  'id': id,
  'format': format,
  'status': status,
  'title': {'english': english, 'romaji': romaji ?? english},
  'startDate': start == null
      ? {'year': null}
      : {'year': start[0], 'month': start[1], 'day': start[2]},
  'endDate': end == null
      ? {'year': null}
      : {'year': end[0], 'month': end[1], 'day': end[2]},
  'episodes': episodes,
  'duration': duration,
  if (relations != null) 'relations': {'edges': relations},
};

Map<String, Object?> edge(String type, Map<String, Object?> node) => {
  'relationType': type,
  'node': node,
};

void main() {
  late List<http.Request> sent;
  late MemoryAnimeLinkStore links;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// Frieren: season 1 (154587) with a sequel, season 2 (177709), plus a
  /// recap movie hanging off season 1.
  final frieren1 = media(
    154587,
    english: "Frieren: Beyond Journey's End",
    romaji: 'Sousou no Frieren',
    start: [2023, 9, 29],
    end: [2024, 3, 22],
    episodes: 28,
    duration: 24,
  );
  final frieren2 = media(
    177709,
    english: "Frieren: Beyond Journey's End Season 2",
    start: [2026, 1, 16],
    status: 'RELEASING',
    episodes: 28,
    duration: 24,
  );
  final recap = media(
    999,
    format: 'MOVIE',
    english: "Frieren: Beyond Journey's End Recap",
    start: [2025, 1, 1],
  );

  /// The chain query's answer for [id], relations two deep.
  Map<String, Object?> chainFor(int id) {
    switch (id) {
      case 154587:
        return {
          ...frieren1,
          'relations': {
            'edges': [
              edge('SEQUEL', {
                ...frieren2,
                'relations': {
                  'edges': [edge('PREQUEL', frieren1)],
                },
              }),
              edge('SIDE_STORY', {
                ...recap,
                'relations': {'edges': []},
              }),
            ],
          },
        };
      case 177709:
        return {
          ...frieren2,
          'relations': {
            'edges': [
              edge('PREQUEL', {
                ...frieren1,
                'relations': {
                  'edges': [edge('SEQUEL', frieren2)],
                },
              }),
            ],
          },
        };
      default:
        throw StateError('no chain for $id');
    }
  }

  /// AniList and TMDB from one handler, told apart by host. [tmdbShows] is
  /// TMDB's search answer; null leaves TMDB out of the build.
  AniListSource source({
    Map<String, Object?>? tmdbSearch,
    Map<String, Object?>? tmdbShow,
    bool withTmdb = true,
    Map<int, List<Map<String, Object?>>> schedule = const {},
  }) {
    sent = [];
    links = MemoryAnimeLinkStore();
    final client = MockClient((request) async {
      sent.add(request);
      if (request.url.host == 'api.themoviedb.org') {
        if (request.url.path.startsWith('/3/search/tv')) {
          return json(200, tmdbSearch ?? {'results': []});
        }
        return json(200, tmdbShow ?? {});
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final variables = body['variables'] as Map<String, Object?>;
      final query = body['query'] as String;
      final id = variables['id'] as int;
      if (query.contains('airingSchedule')) {
        return json(200, {
          'data': {
            'Media': {
              'airingSchedule': {
                'pageInfo': {'hasNextPage': false},
                'nodes': schedule[id] ?? [],
              },
            },
          },
        });
      }
      return json(200, {
        'data': {'Media': chainFor(id)},
      });
    });
    return AniListSource(
      client,
      tmdb: withTmdb ? TmdbSource(client, token: 'tok') : null,
      links: links,
    );
  }

  List<http.Request> anilistCalls() =>
      sent.where((r) => r.url.host == 'graphql.anilist.co').toList();

  test('the format tells a series from a movie', () {
    expect(AniListSource.kindOf('TV'), EntryKind.series);
    expect(AniListSource.kindOf('TV_SHORT'), EntryKind.series);
    expect(AniListSource.kindOf('ONA'), EntryKind.series);
    expect(AniListSource.kindOf('OVA'), EntryKind.series);
    expect(AniListSource.kindOf('MOVIE'), EntryKind.movie);
    expect(AniListSource.kindOf('SPECIAL'), EntryKind.movie);
    expect(AniListSource.kindOf('MUSIC'), EntryKind.movie);
    expect(AniListSource.kindOf(null), isNull);
    expect(AniListSource.kindOf('MANGA'), isNull);
  });

  test('the search carries the kind', () async {
    final anilist = source();
    sent = [];
    final client = MockClient(
      (_) async => json(200, {
        'data': {
          'Page': {
            'media': [
              {
                ...frieren1,
                'coverImage': {},
                'studios': {'nodes': []},
                'genres': [],
              },
              {
                ...recap,
                'coverImage': {},
                'studios': {'nodes': []},
                'genres': [],
              },
            ],
          },
        },
      }),
    );
    final hits = await AniListSource(client)
        .search('frieren', type: MediaType.anime);
    expect(hits[0].kind, EntryKind.series);
    expect(hits[1].kind, EntryKind.movie);
    expect(anilist.links, links);
  });

  group('with a TMDB match', () {
    final tmdbSearch = {
      'results': [
        {
          'id': 209867,
          'name': "Frieren: Beyond Journey's End",
          'first_air_date': '2023-09-29',
        },
      ],
    };
    final tmdbShow = {
      'id': 209867,
      'status': 'Returning Series',
      'seasons': [
        {'season_number': 0, 'air_date': '2023-10-01'},
        {'season_number': 1, 'air_date': '2023-09-29'},
        {'season_number': 2, 'air_date': '2026-01-16'},
      ],
    };

    test('seasons come from TMDB, found by the chain\'s first entry', () async {
      final anilist = source(tmdbSearch: tmdbSearch, tmdbShow: tmdbShow);
      // Asked from season 2: the chain is walked back to season 1 first.
      final found = await anilist.seasons('anilist:177709');
      expect(found!.kind, EntryKind.series);
      expect(found.seasons, const [
        Season(season: 1, released: Released(2023, 9, 29)),
        Season(season: 2, released: Released(2026, 1, 16)),
      ]);
      final search = sent.firstWhere(
        (r) => r.url.path.startsWith('/3/search/tv'),
      );
      expect(
        search.url.queryParameters['query'],
        "Frieren: Beyond Journey's End",
      );
      expect(links.links[177709]?.tmdb, 'tmdb:tv:209867');
      expect(links.links[177709]?.kind, EntryKind.series);

      // Asked again: the link is remembered, so only TMDB is asked.
      sent = [];
      await anilist.seasons('anilist:177709');
      expect(anilistCalls(), isEmpty);
      expect(sent.single.url.path, '/3/tv/209867');
    });

    test('the episodes are read under the TMDB show', () async {
      final anilist = source(tmdbSearch: tmdbSearch, tmdbShow: tmdbShow);
      expect(await anilist.seasonSource('anilist:154587'), 'tmdb:tv:209867');
    });

    test(
      'a pick fetches the seasons for a series, nothing for a movie',
      () async {
        final anilist = source(tmdbSearch: tmdbSearch, tmdbShow: tmdbShow);
        const series = LookupMatch(
          type: MediaType.anime,
          title: 'Frieren',
          source: 'anilist:154587',
          kind: EntryKind.series,
        );
        expect((await anilist.details(series)).seasons, hasLength(2));
        const movie = LookupMatch(
          type: MediaType.anime,
          title: 'Akira',
          source: 'anilist:47',
          kind: EntryKind.movie,
        );
        sent = [];
        expect(await anilist.details(movie), movie);
        expect(sent, isEmpty);
      },
    );
  });

  group('without a TMDB match', () {
    test(
      'the seasons are the chain, one per entry, the recap left out',
      () async {
        final anilist = source();
        final found = await anilist.seasons('anilist:154587');
        expect(found!.kind, EntryKind.series);
        expect(found.seasons, const [
          Season(season: 1, released: Released(2023, 9, 29)),
          Season(season: 2, released: Released(2026, 1, 16)),
        ]);
        expect(found.canceled, isFalse);
        // One chain query: the relations came two deep.
        expect(anilistCalls(), hasLength(1));
        expect(links.links[154587]?.tmdb, isNull);
        expect(await anilist.seasonSource('anilist:154587'), 'anilist:154587');
      },
    );

    test('a build without TMDB never asks it', () async {
      final anilist = source(withTmdb: false);
      final found = await anilist.seasons('anilist:154587');
      expect(found!.seasons, hasLength(2));
      expect(sent.every((r) => r.url.host == 'graphql.anilist.co'), isTrue);
    });

    test(
      'the episodes are numbered, dated by the schedule, untitled',
      () async {
        final anilist = source(
          schedule: {
            177709: [
              {'episode': 1, 'airingAt': 1768521600}, // 2026-01-16 00:00 UTC
              {'episode': 2, 'airingAt': 1769126400}, // 2026-01-23
            ],
          },
        );
        final episodes = await anilist.seasonEpisodes('anilist:154587', 2);
        expect(episodes, hasLength(28));
        expect(episodes![0], (
          number: 1,
          title: null,
          aired: const Released(2026, 1, 16),
          runtime: 24,
        ));
        expect(episodes[1].aired, const Released(2026, 1, 23));
        // Not scheduled yet, and the season is still airing: undated.
        expect(episodes[2].aired, isNull);
        expect(episodes[2].runtime, 24);
      },
    );

    test('a finished entry\'s unscheduled episodes count as out', () async {
      final anilist = source();
      final episodes = await anilist.seasonEpisodes('anilist:154587', 1);
      expect(episodes, hasLength(28));
      expect(
        episodes!.every((e) => e.aired == const Released(2023, 9, 29)),
        isTrue,
      );
    });

    test('a season the chain does not have has no episodes', () async {
      final anilist = source();
      expect(await anilist.seasonEpisodes('anilist:154587', 3), isEmpty);
    });
  });

  test('a movie is a movie: no chain walk, no seasons', () async {
    sent = [];
    links = MemoryAnimeLinkStore();
    final client = MockClient((request) async {
      sent.add(request);
      return json(200, {
        'data': {
          'Media': {
            ...media(
              47,
              format: 'MOVIE',
              english: 'Akira',
              start: [1988, 7, 16],
            ),
            'relations': {
              'edges': [
                edge('ADAPTATION', media(1, format: 'MANGA', english: 'Akira')),
              ],
            },
          },
        },
      });
    });
    final anilist = AniListSource(
      client,
      tmdb: TmdbSource(client, token: 'tok'),
      links: links,
    );
    final found = await anilist.seasons('anilist:47');
    expect(found!.kind, EntryKind.movie);
    expect(found.seasons, isEmpty);
    expect(sent, hasLength(1));
    expect(links.links[47]?.kind, EntryKind.movie);
    // Remembered for good.
    sent = [];
    await anilist.seasons('anilist:47');
    expect(sent, isEmpty);
  });

  test('a stored miss is asked again after two weeks', () async {
    final anilist = source();
    await links.write(154587, (
      tmdb: null,
      kind: EntryKind.series,
      checked: DateTime.now().subtract(const Duration(days: 15)),
    ));
    await anilist.seasons('anilist:154587');
    expect(sent.any((r) => r.url.host == 'api.themoviedb.org'), isTrue);
  });
}
