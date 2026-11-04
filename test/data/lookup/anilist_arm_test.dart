import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_app/data/lookup/anilist_source.dart';
import 'package:library_app/data/lookup/anime_chain_store.dart';
import 'package:library_app/data/lookup/anime_link_store.dart';
import 'package:library_app/data/lookup/arm_ids.dart';
import 'package:library_app/data/lookup/tmdb_source.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/season_span.dart';
import 'package:library_app/data/models/season_split.dart';

/// AniList's chain with ARM's map beside it (section 10c; owner's decision,
/// 2026-11-04): the prequel guard, a sequel without a format, parts folded
/// by TVDB season, the parts split, the coming parts, the long run, and
/// the TMDB show from ARM instead of a title match.
void main() {
  late List<http.Request> sent;
  late MemoryAnimeLinkStore links;

  http.Response json(int status, Object? body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, Object?> media(
    int id, {
    String? format = 'TV',
    String status = 'FINISHED',
    String? english,
    List<int>? start,
    int? episodes,
  }) => {
    'id': id,
    'format': format,
    'status': status,
    'title': {'english': english, 'romaji': english},
    'startDate': start == null
        ? {'year': null}
        : {
            'year': start[0],
            'month': start.elementAtOrNull(1),
            'day': start.elementAtOrNull(2),
          },
    'endDate': {'year': null},
    'episodes': episodes,
    'duration': 24,
  };

  /// Attack on Titan, shortened: three seasons, the third in two parts
  /// and a third part announced without a format; MONSTERS, an ONA from
  /// 2024, listed as season 1's prequel.
  final nodes = {
    1: media(1, english: 'Attack on Titan', start: [2013, 4, 7], episodes: 25),
    2: media(2, english: 'Season 2', start: [2017, 4, 1], episodes: 12),
    3: media(3, english: 'Season 3', start: [2018, 7, 23], episodes: 12),
    4: media(4, english: 'Season 3 Part 2', start: [2019, 4, 29], episodes: 10),
    5: media(
      5,
      format: null,
      status: 'NOT_YET_RELEASED',
      english: 'Season 3 Part 3',
      start: [2027, 1, 10],
    ),
    99: media(
      99,
      format: 'ONA',
      english: 'MONSTERS',
      start: [2024, 1, 21],
      episodes: 1,
    ),
    // Hunter x Hunter (2011): one entry of 148.
    11061: media(
      11061,
      english: 'Hunter x Hunter (2011)',
      start: [2011, 10, 2],
      episodes: 148,
    ),
  };
  final relations = {
    1: [('PREQUEL', 99), ('SEQUEL', 2)],
    2: [('PREQUEL', 1), ('SEQUEL', 3)],
    3: [('PREQUEL', 2), ('SEQUEL', 4)],
    4: [('PREQUEL', 3), ('SEQUEL', 5)],
    5: [('PREQUEL', 4)],
    99: [('SEQUEL', 1)],
    11061: <(String, int)>[],
  };

  /// The chain query's answer: relations two deep.
  Map<String, Object?> withRelations(int id, int depth) => {
    ...nodes[id]!,
    if (depth > 0)
      'relations': {
        'edges': [
          for (final (type, other) in relations[id]!)
            {'relationType': type, 'node': withRelations(other, depth - 1)},
        ],
      },
  };

  final arm = {
    1: {'themoviedb': 1429, 'thetvdb': 267440, 'thetvdb-season': 1},
    2: {'themoviedb': 1429, 'thetvdb': 267440, 'thetvdb-season': 2},
    3: {'themoviedb': 1429, 'thetvdb': 267440, 'thetvdb-season': 3},
    4: {'themoviedb': 1429, 'thetvdb': 267440, 'thetvdb-season': 3},
    5: {'themoviedb': 1429, 'thetvdb': 267440, 'thetvdb-season': 3},
    11061: {'themoviedb': 46298, 'thetvdb': 252322, 'thetvdb-season': null},
  };

  AniListSource source({
    bool withArm = true,
    Map<int, Object?>? armRows,
    MemoryAnimeChainStore? chains,
  }) {
    sent = [];
    links = MemoryAnimeLinkStore();
    final client = MockClient((request) async {
      sent.add(request);
      switch (request.url.host) {
        case 'arm.haglund.dev':
          final id = int.parse(request.url.queryParameters['id']!);
          return json(200, (armRows ?? arm)[id]);
        case 'api.themoviedb.org':
          return switch (request.url.path) {
            '/3/search/tv' => json(200, {
              'results': [
                {
                  'id': 46298,
                  'name': 'Hunter x Hunter',
                  'first_air_date': '2011-10-02',
                },
              ],
            }),
            '/3/tv/1429' => json(200, {
              'status': 'Ended',
              'seasons': [
                {
                  'season_number': 1,
                  'air_date': '2013-04-07',
                  'episode_count': 25,
                },
                {
                  'season_number': 2,
                  'air_date': '2017-04-01',
                  'episode_count': 12,
                },
                {
                  'season_number': 3,
                  'air_date': '2018-07-23',
                  'episode_count': 22,
                },
              ],
            }),
            '/3/tv/46298' => json(200, {
              'status': 'Ended',
              'seasons': [
                {
                  'season_number': 1,
                  'air_date': '2011-10-02',
                  'episode_count': 148,
                },
              ],
            }),
            '/3/tv/46298/episode_groups' => json(200, {
              'results': [
                {'id': 'arcs', 'name': 'Story Arcs', 'type': 5},
              ],
            }),
            '/3/tv/episode_group/arcs' => json(200, {
              'type': 5,
              'groups': [
                {
                  'name': 'Hunter Exam Arc',
                  'order': 0,
                  'episodes': [
                    for (var n = 1; n <= 26; n++)
                      {'order': n - 1, 'air_date': '2011-10-02'},
                  ],
                },
                {
                  'name': 'Election Arc',
                  'order': 1,
                  'episodes': [
                    for (var n = 1; n <= 122; n++)
                      {'order': n - 1, 'air_date': '2014-07-08'},
                  ],
                },
              ],
            }),
            _ => json(404, {'status_message': 'not found'}),
          };
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final variables = body['variables'] as Map<String, Object?>;
      final id = variables['id'] as int;
      if ((body['query'] as String).contains('airingSchedule')) {
        return json(200, {
          'data': {
            'Media': {
              'airingSchedule': {
                'pageInfo': {'hasNextPage': false},
                'nodes': <Object>[],
              },
            },
          },
        });
      }
      return json(200, {
        'data': {'Media': withRelations(id, 2)},
      });
    });
    return AniListSource(
      client,
      tmdb: TmdbSource(client, token: 'tok'),
      arm: withArm ? ArmIds(client) : null,
      links: links,
      chains: chains,
    );
  }

  Iterable<http.Request> to(String host) =>
      sent.where((r) => r.url.host == host);

  test('a prequel that starts later is not followed (MONSTERS)', () async {
    final anilist = source();
    final seasons = await anilist.seasons('anilist:2');
    expect(
      seasons!.seasons.first,
      const Season(season: 1, released: Released(2013, 4, 7)),
    );
    expect(to('graphql.anilist.co').length, lessThan(5));
  });

  test('parts fold by TVDB season, a sequel without a format among them; '
      'the chain is kept with the map', () async {
    final chains = MemoryAnimeChainStore();
    final anilist = source(chains: chains);
    final seasons = await anilist.seasons('anilist:1');
    expect(seasons!.seasons, const [
      Season(season: 1, released: Released(2013, 4, 7)),
      Season(season: 2, released: Released(2017, 4, 1)),
      Season(season: 3, released: Released(2018, 7, 23)),
    ]);
    // ARM asked once per season entry, kept with the links.
    expect(to('arm.haglund.dev'), hasLength(5));
    expect((await links.read(4))!.tvdbSeason, 3);
    expect((await links.read(4))!.tmdb, 'tmdb:tv:1429');
    final kept = chains.chains.single.nodes;
    expect(kept.map((n) => n['tvdb_season']), [1, 2, 3, 3, 3]);
    // A kept chain serves the season screen with the fold.
    final again = source(chains: chains);
    final splits = await again.seasonSplits('anilist:1', tmdb: 'tmdb:tv:1429');
    expect(to('graphql.anilist.co'), isEmpty);
    expect(splits!.map((s) => s.id), [
      SeasonSplit.anilistId,
      SeasonSplit.anilistPartsId,
      SeasonSplit.tmdbSeasonsId,
    ]);
    expect(splits[0].seasons, const [
      SeasonSpan(season: 1, episodes: 25, released: Released(2013, 4, 7)),
      SeasonSpan(season: 2, episodes: 12, released: Released(2017, 4, 1)),
      SeasonSpan(season: 3, episodes: 22, released: Released(2018, 7, 23)),
    ]);
    expect(splits[0].long, isFalse);
    expect(splits[1].seasons.map((s) => s.episodes), [25, 12, 12, 10, null]);
    // The folded chain and the TMDB list split alike: one row.
    expect(SeasonSplit.distinct(splits), hasLength(2));
  });

  test('the parts split: its own seasons and episodes', () async {
    final anilist = source();
    final parts = await anilist.splitSeasons(
      'anilist:1',
      SeasonSplit.anilistPartsId,
    );
    expect(parts!.seasons.map((s) => s.season), [1, 2, 3, 4, 5]);
    expect(parts.seasons[4].released, const Released(2027, 1, 10));
    expect(anilist.isOwnSplit(SeasonSplit.anilistPartsId), isFalse);
    // Season 3 folded: both parts' episodes, numbered on.
    final folded = await anilist.seasonEpisodes('anilist:1', 3);
    expect(folded!.map((e) => e.number), List.generate(22, (i) => i + 1));
    expect(folded[12].aired, const Released(2019, 4, 29));
    final part = await anilist.seasonEpisodes(
      'anilist:1',
      4,
      from: SeasonSplit.anilistPartsId,
    );
    expect(part, hasLength(10));
  });

  test('the coming parts: a later part of a season out', () async {
    final anilist = source();
    expect(await anilist.seasonParts('anilist:1'), [
      (season: 3, part: 3, released: const Released(2027, 1, 10)),
    ]);
    expect(await anilist.seasonParts('anilist:11061'), isEmpty);
  });

  test('the TMDB show comes from ARM, no title match', () async {
    final anilist = source();
    expect(await anilist.tmdbShow('anilist:1'), 'tmdb:tv:1429');
    expect(to('api.themoviedb.org'), isEmpty);
  });

  test(
    'without a row the title is matched without its year (Hunter x Hunter)',
    () async {
      final anilist = source(armRows: const {11061: null});
      expect(await anilist.tmdbShow('anilist:11061'), 'tmdb:tv:46298');
      final search = to('api.themoviedb.org').single;
      expect(search.url.queryParameters['query'], 'Hunter x Hunter');
      expect(
        AniListSource.withoutYear('Hunter x Hunter (2011)'),
        'Hunter x Hunter',
      );
      expect(AniListSource.withoutYear('86 EIGHTY-SIX'), '86 EIGHTY-SIX');
    },
  );

  test(
    'a long run is marked so, and the arcs are its automatic split',
    () async {
      final anilist = source();
      final splits = SeasonSplit.distinct(
        (await anilist.seasonSplits('anilist:11061'))!,
      );
      expect(splits.first.long, isTrue);
      expect(splits.first.count, 1);
      final auto = SeasonSplit.automatic(splits)!;
      expect(auto.arcs, isTrue);
      expect(auto.names, {1: 'Hunter Exam', 2: 'Election'});
      // Without ARM, the chain alone: nothing folds, nothing is mapped.
      final bare = source(withArm: false);
      final seasons = await bare.seasons('anilist:1');
      expect(seasons!.seasons, hasLength(5));
      expect(to('arm.haglund.dev'), isEmpty);
    },
  );

  test('isLongRun: over 100 episodes, or airing for years without a count', () {
    AniNode node({
      int? episodes,
      String status = 'FINISHED',
      int year = 2011,
    }) => AniNode(
      id: 1,
      format: 'TV',
      status: status,
      start: Released(year, 10, 2),
      episodes: episodes,
    );
    final today = DateTime(2026, 11, 4);
    expect(
      AniListSource.isLongRun([
        [node(episodes: 148)],
      ], today),
      isTrue,
    );
    expect(
      AniListSource.isLongRun([
        [node(episodes: 64)],
      ], today),
      isFalse,
    );
    expect(
      AniListSource.isLongRun([
        [node(status: 'RELEASING', year: 1999)],
      ], today),
      isTrue,
    );
    expect(
      AniListSource.isLongRun([
        [node(status: 'RELEASING', year: 2026)],
      ], today),
      isFalse,
    );
    expect(
      AniListSource.isLongRun([
        [node(episodes: 148)],
        [node(episodes: 148)],
      ], today),
      isFalse,
    );
  });
}
