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
import 'package:library_app/data/models/season_span.dart';

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

  /// Frieren as AniList has it: season 1 (154587, 28 episodes), season 2
  /// (182255, 10 episodes) and season 3 (209939) not out yet, dated by
  /// month. Off season 1 hang a recap movie and the "no Mahou" ONA shorts,
  /// listed first among its sequels so the chain has to pass them over.
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
    182255,
    romaji: 'Sousou no Frieren 2nd Season',
    start: [2026, 1, 16],
    end: [2026, 3, 20],
    episodes: 10,
    duration: 24,
  );
  final frieren3 = {
    ...media(
      209939,
      romaji: 'Sousou no Frieren 3rd Season',
      status: 'NOT_YET_RELEASED',
    ),
    'startDate': {'year': 2027, 'month': 10, 'day': null},
  };
  final shorts = media(
    170068,
    format: 'ONA',
    romaji: 'Sousou no Frieren: no Mahou',
    start: [2023, 10, 11],
    episodes: 12,
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
                ...shorts,
                'relations': {'edges': []},
              }),
              edge('SEQUEL', {
                ...frieren2,
                'relations': {
                  'edges': [
                    edge('PREQUEL', frieren1),
                    edge('SEQUEL', frieren3),
                  ],
                },
              }),
              edge('SIDE_STORY', {
                ...recap,
                'relations': {'edges': []},
              }),
            ],
          },
        };
      case 182255:
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
              edge('SEQUEL', {
                ...frieren3,
                'relations': {
                  'edges': [edge('PREQUEL', frieren2)],
                },
              }),
            ],
          },
        };
      case 209939:
        return {
          ...frieren3,
          'relations': {
            'edges': [
              edge('PREQUEL', {
                ...frieren2,
                'relations': {
                  'edges': [
                    edge('PREQUEL', frieren1),
                    edge('SEQUEL', frieren3),
                  ],
                },
              }),
            ],
          },
        };
      default:
        throw StateError('no chain for $id');
    }
  }

  /// TMDB's Frieren: one season of 38 episodes, as the old link had it.
  final tmdbShow = {
    'id': 209867,
    'status': 'Returning Series',
    'seasons': [
      {'season_number': 0, 'air_date': '2023-10-01', 'episode_count': 4},
      {'season_number': 1, 'air_date': '2023-09-29', 'episode_count': 38},
    ],
  };

  /// A link an older build wrote: the TMDB show Frieren's seasons came
  /// from, waiting for the re-split.
  final oldLink = (
    kind: EntryKind.series,
    checked: DateTime(2026, 10, 20),
    tmdb: 'tmdb:tv:209867',
    tmdbChecked: null,
    resplit: true,
  );

  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// TMDB's season 1 of Frieren: all 38 episodes, titled. Four aired on
  /// the first day, then weekly; episode 29 on with AniList's season 2.
  final tmdbSeason1 = {
    'season_number': 1,
    'episodes': [
      for (var n = 1; n <= 38; n++)
        {
          'episode_number': n,
          'name': 'Title $n',
          'runtime': 25,
          'air_date': n <= 4
              ? '2023-09-29'
              : n <= 28
              ? day(DateTime(2023, 9, 29).add(Duration(days: 7 * (n - 4))))
              : day(DateTime(2026, 1, 16).add(Duration(days: 7 * (n - 29)))),
        },
    ],
  };

  /// What the search answers, by search text; each hit as the search lists
  /// it, with its prequels.
  Map<String, Object?> searchHit(
    Map<String, Object?> hit, [
    List<Map<String, Object?>> prequels = const [],
  ]) => {
    ...hit,
    'relations': {
      'edges': [for (final p in prequels) edge('PREQUEL', p)],
    },
  };
  Map<String, Object?> lite(int id, [List<Map<String, Object?>>? prequels]) => {
    'id': id,
    'format': 'TV',
    if (prequels != null)
      'relations': {
        'edges': [for (final p in prequels) edge('PREQUEL', p)],
      },
  };
  final searches = <String, List<Map<String, Object?>>>{
    'Frieren': [
      searchHit(frieren1),
      searchHit(frieren3, [
        lite(182255, [lite(154587)]),
      ]),
      searchHit(frieren2, [lite(154587, [])]),
      searchHit(shorts),
      searchHit(media(189513, format: 'ONA', romaji: 'no Mahou Part 2'), [
        {'id': 170068, 'format': 'ONA'},
      ]),
      searchHit(recap, [lite(154587)]),
    ],
    'Frieren 2nd': [
      searchHit(frieren2, [lite(154587, [])]),
    ],
  };

  /// AniList and TMDB from one handler, told apart by host; [withTmdb]
  /// false leaves TMDB out of the build, [tmdbHits] is TMDB's search.
  AniListSource source({
    bool withTmdb = true,
    List<Map<String, Object?>> tmdbHits = const [
      {
        'id': 209867,
        'name': "Frieren: Beyond Journey's End",
        'first_air_date': '2023-09-29',
      },
    ],
    Map<int, List<Map<String, Object?>>> schedule = const {},
  }) {
    sent = [];
    links = MemoryAnimeLinkStore();
    final client = MockClient((request) async {
      sent.add(request);
      if (request.url.host == 'api.themoviedb.org') {
        return switch (request.url.path) {
          '/3/search/tv' => json(200, {'results': tmdbHits}),
          '/3/tv/209867' => json(200, tmdbShow),
          '/3/tv/209867/season/1' => json(200, tmdbSeason1),
          _ => json(404, {'status_message': 'not found'}),
        };
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final variables = body['variables'] as Map<String, Object?>;
      final query = body['query'] as String;
      if (variables['search'] case final String text) {
        return json(200, {
          'data': {
            'Page': {'media': searches[text] ?? []},
          },
        });
      }
      if (variables['ids'] case final List<Object?> ids) {
        return json(200, {
          'data': {
            'Page': {
              'media': [
                for (final id in ids)
                  if (id == 154587) frieren1,
              ],
            },
          },
        });
      }
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

  List<http.Request> tmdbCalls() =>
      sent.where((r) => r.url.host == 'api.themoviedb.org').toList();

  const frierenSeasons = [
    Season(season: 1, released: Released(2023, 9, 29)),
    Season(season: 2, released: Released(2026, 1, 16)),
    Season(season: 3, released: Released(2027, 10)),
  ];

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
  });

  group('search', () {
    test('later seasons fold into the first, listed once', () async {
      final anilist = source();
      final hits = await anilist.search('Frieren', type: MediaType.anime);
      // Season 1, the shorts; the recap movie stays its own hit.
      expect(hits.map((m) => m.source), [
        'anilist:154587',
        'anilist:170068',
        'anilist:999',
      ]);
      expect(hits.first.kind, EntryKind.series);
    });

    test('a later season found alone brings its first', () async {
      final anilist = source();
      final hits = await anilist.search('Frieren 2nd', type: MediaType.anime);
      expect(hits.single.source, 'anilist:154587');
      expect(hits.single.title, "Frieren: Beyond Journey's End");
    });
  });

  test(
    'the seasons are the TV entries of the chain, the sequel to come too',
    () async {
      final anilist = source();
      final found = await anilist.seasons('anilist:154587');
      expect(found!.kind, EntryKind.series);
      // Two seasons and an announced third, not TMDB's one; the ONA shorts
      // and the recap movie are no seasons.
      expect(found.seasons, frierenSeasons);
      expect(found.canceled, isFalse);
      expect(Season.listable(found.seasons), frierenSeasons);
      expect(tmdbCalls(), isEmpty);
      expect(links.links[154587]?.kind, EntryKind.series);
      expect(await anilist.seasonSource('anilist:154587'), 'anilist:154587');
    },
  );

  test('asked from a later season, the chain starts at the first', () async {
    final anilist = source();
    final found = await anilist.seasons('anilist:209939');
    expect(found!.seasons, frierenSeasons);
  });

  test('an old TMDB link no longer decides the seasons', () async {
    final anilist = source();
    await links.write(154587, oldLink);
    final found = await anilist.seasons('anilist:154587');
    expect(found!.seasons, frierenSeasons);
    expect(tmdbCalls(), isEmpty);
  });

  test(
    'a pick fetches the seasons for a series, nothing for a movie',
    () async {
      final anilist = source();
      const series = LookupMatch(
        type: MediaType.anime,
        title: 'Frieren',
        source: 'anilist:154587',
        kind: EntryKind.series,
      );
      final picked = await anilist.details(series);
      expect(picked.seasons, frierenSeasons);
      expect(picked.tmdb, 'tmdb:tv:209867');
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

  group('which entries are seasons', () {
    AniNode node(int id, String format, {String? english}) =>
        AniNode(id: id, format: format, english: english);

    test('TV, TV short and ONA; OVAs, movies and specials left out', () {
      final chain = [
        node(1, 'TV'),
        node(2, 'OVA'),
        node(3, 'MOVIE'),
        node(4, 'TV_SHORT'),
        node(5, 'SPECIAL'),
        node(6, 'ONA'),
        node(7, 'TV', english: 'Show Recap'),
      ];
      expect(AniListSource.seasonEntries(chain).map((n) => n.id), [1, 4, 6]);
    });

    test('a series made only of OVAs has them as its seasons', () {
      final chain = [node(1, 'OVA'), node(2, 'MOVIE'), node(3, 'OVA')];
      expect(AniListSource.seasonEntries(chain).map((n) => n.id), [1, 3]);
    });
  });

  group('episodes', () {
    test('without TMDB: numbered, dated by the schedule, untitled', () async {
      final anilist = source(
        withTmdb: false,
        schedule: {
          182255: [
            {'episode': 1, 'airingAt': 1768521600}, // 2026-01-16 00:00 UTC
            {'episode': 2, 'airingAt': 1769126400}, // 2026-01-23
          ],
        },
      );
      final episodes = await anilist.seasonEpisodes('anilist:154587', 2);
      expect(episodes, hasLength(10));
      expect(episodes![0], (
        number: 1,
        title: null,
        aired: const Released(2026, 1, 16),
        runtime: 24,
      ));
      expect(episodes[1].aired, const Released(2026, 1, 23));
      // Finished: an episode without a scheduled date counts as out.
      expect(episodes[2].aired, const Released(2026, 1, 16));
    });

    test('season 1 has its own 28', () async {
      final anilist = source(withTmdb: false);
      final episodes = await anilist.seasonEpisodes('anilist:154587', 1);
      expect(episodes, hasLength(28));
      expect(
        episodes!.every((e) => e.aired == const Released(2023, 9, 29)),
        isTrue,
      );
    });

    test('titles from TMDB, found by air date across its split', () async {
      final anilist = source(
        schedule: {
          182255: [
            {'episode': 1, 'airingAt': 1768575600}, // 2026-01-16 15:00 UTC
          ],
        },
      );
      final second = await anilist.seasonEpisodes('anilist:154587', 2);
      // AniList's season 2 is TMDB's season 1, episodes 29 to 38.
      expect(second, hasLength(10));
      expect(second!.first, (
        number: 1,
        title: 'Title 29',
        aired: const Released(2026, 1, 16),
        runtime: 25,
      ));
      expect(second.last.title, 'Title 38');
      expect(second.last.aired, const Released(2026, 3, 20));
      expect(anilist.episodesProvider('anilist:154587'), 'TMDB and AniList');
      expect(links.links[154587]?.tmdb, 'tmdb:tv:209867');
      expect(links.links[154587]?.resplit, isFalse);

      final first = await anilist.seasonEpisodes('anilist:154587', 1);
      expect(first, hasLength(28));
      expect(first!.first.title, 'Title 1');
      expect(first.last.title, 'Title 28');
      // The match is kept: TMDB is not searched twice.
      expect(
        tmdbCalls().where((r) => r.url.path == '/3/search/tv'),
        hasLength(1),
      );
    });

    test('the entry\'s TMDB show comes first', () async {
      // TMDB's search finds nothing, but the entry says which show it is.
      final anilist = source(tmdbHits: const []);
      final episodes = await anilist.seasonEpisodes(
        'anilist:154587',
        2,
        tmdb: 'tmdb:tv:209867',
      );
      expect(episodes!.first.title, 'Title 29');
      expect(tmdbCalls().where((r) => r.url.path == '/3/search/tv'), isEmpty);
    });

    test('no TMDB match: untitled, credited to AniList alone', () async {
      final anilist = source(tmdbHits: const []);
      final episodes = await anilist.seasonEpisodes('anilist:154587', 2);
      expect(episodes, hasLength(10));
      expect(episodes!.every((e) => e.title == null), isTrue);
      expect(anilist.episodesProvider('anilist:154587'), 'AniList');
      expect(links.links[154587]?.tmdbChecked, isNotNull);
    });

    test('a season not out yet has none; one past the chain neither', () async {
      final anilist = source();
      expect(await anilist.seasonEpisodes('anilist:154587', 3), isEmpty);
      expect(await anilist.seasonEpisodes('anilist:154587', 4), isEmpty);
    });
  });

  group('re-split', () {
    test(
      'an old TMDB link offers TMDB\'s split and AniList\'s, once',
      () async {
        final anilist = source();
        await links.write(154587, oldLink);
        final split = await anilist.resplit('anilist:154587');
        expect(split!.before, const [
          SeasonSpan(season: 1, episodes: 38, released: Released(2023, 9, 29)),
        ]);
        expect(split.after, const [
          SeasonSpan(season: 1, episodes: 28, released: Released(2023, 9, 29)),
          SeasonSpan(season: 2, episodes: 10, released: Released(2026, 1, 16)),
          SeasonSpan(season: 3, released: Released(2027, 10)),
        ]);
        expect(tmdbCalls().single.url.path, '/3/tv/209867');

        await anilist.resplitSettled('anilist:154587');
        // The link stays, for the titles; the re-split is done.
        expect(links.links[154587]?.tmdb, 'tmdb:tv:209867');
        expect(links.links[154587]?.resplit, isFalse);
        expect(links.links[154587]?.kind, EntryKind.series);
        expect(await anilist.resplit('anilist:154587'), isNull);
      },
    );

    test('nothing to re-split without an old link or without TMDB', () async {
      var anilist = source();
      expect(await anilist.resplit('anilist:154587'), isNull);
      anilist = source(withTmdb: false);
      await links.write(154587, oldLink);
      expect(await anilist.resplit('anilist:154587'), isNull);
      expect(tmdbCalls(), isEmpty);
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
}
