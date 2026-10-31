import 'dart:async';

import '../data/lookup/episode_info.dart';
import '../data/lookup/igdb_source.dart';
import '../data/lookup/lookup_failure.dart';
import '../data/lookup/lookup_match.dart';
import '../data/lookup/lookup_source.dart';
import '../data/lookup/movie_dates.dart';
import '../data/models/follow_kind.dart';
import '../data/upcoming/creator_lookup.dart';
import '../data/upcoming/creator_status.dart';
import '../data/lookup/music_source.dart';
import '../data/lookup/track_info.dart';
import '../data/models/entry_id.dart';
import '../data/models/entry_kind.dart';
import '../data/models/media_type.dart';
import '../data/models/platform_names.dart';
import '../data/models/released.dart';
import '../data/models/season.dart';

/// A lookup with a fixed catalog, for the widget tests, the screenshot
/// walks, the accessibility audit and the FIRST_RUN dev switch. [search]
/// answers from [fakeCatalog]; [match] answers any title, so every fixture
/// entry gets a (fake) cover in a photo view. [latency] shows the loading
/// state, [failure] makes every call fail that way, and `configured:
/// false` is a provider without its key.
class FakeLookupSource extends LookupSource
    implements MusicSource, CreatorLookup, InactiveLookup {
  FakeLookupSource({
    this.latency = Duration.zero,
    this.failure,
    this.configured = true,
    this.seasonsBySource = const {},
    this.canceledSources = const {},
    this.kindBySource = const {},
    this.episodesBySeason = const {},
    this.seriesBySource = const {},
    this.releasedBySource = const {},
    this.inactiveByName = const {},
    this.releasesByCreator = const {},
    this.movieDatesBySource = const {},
    this.editionsBySource = const {},
  });

  /// Long enough to see the spinner in a demo, short enough not to wait.
  static const demoLatency = Duration(milliseconds: 700);

  final Duration latency;
  final LookupFailure? failure;
  final bool configured;

  /// Seasons [seasons] answers for a show outside the catalog, by source.
  final Map<String, List<Season>> seasonsBySource;

  /// Shows [seasons] calls canceled, by source.
  final Set<String> canceledSources;

  /// The kind [seasons] reports for an anime, by source (null for a show).
  final Map<String, EntryKind?> kindBySource;

  /// Series [seriesParts] answers, by source, ahead of the built-in ones.
  final Map<String, SeriesParts?> seriesBySource;

  /// Release dates [releaseDate] answers, by source; any other source gets
  /// null, as from a provider with no date.
  final Map<String, Released?> releasedBySource;

  /// Episodes [seasonEpisodes] answers, by show source and season, ahead
  /// of the built-in ones.
  final Map<(String, int), List<EpisodeInfo>> episodesBySeason;

  /// Who is no longer active, by name in lowercase, ahead of the built-in
  /// ones ([fakeInactive]).
  final Map<String, Inactive> inactiveByName;

  /// Releases [creatorReleases] answers, by creator id (`fake:creator:<slug>`),
  /// ahead of the built-in ones ([fakeCreatorReleases]).
  final Map<String, List<LookupMatch>> releasesByCreator;

  /// Dates by kind [movieDates] answers, by source, ahead of the built-in
  /// ones ([fakeMovieDates]); any other source gets null.
  final Map<String, MovieDates?> movieDatesBySource;

  /// What [editionRelease] answers, by source; any other source gets null,
  /// as from a provider that cannot list editions.
  final Map<String, EditionRelease?> editionsBySource;

  /// Every call made, for the tests: "search:carrie:movies",
  /// "match:Dirt:music", "details:deezer:album:91627", "cover:igdb:1009".
  final calls = <String>[];

  @override
  String get id => 'fake';

  /// The fake stands in for TMDB in the walks and the tests.
  @override
  String get name => 'TMDB';

  @override
  Set<MediaType> get types => MediaType.values.toSet();

  @override
  bool get isConfigured => configured;

  /// The catalog carries every provider's ids, so the fake owns them all.
  @override
  bool issued(String source) => true;

  Future<void> _call(String call) async {
    calls.add(call);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failure case final failure?) throw LookupException(failure);
  }

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async {
    await _call('search:${query.trim().toLowerCase()}:${type.name}');
    return catalogSearch(query, type: type).take(limit).toList();
  }

  /// A short list of IGDB's platforms, read as IGDB's are.
  @override
  Future<List<GamePlatform>> platforms() async {
    await _call('platforms');
    return IgdbSource.platformsFrom(_platformRows);
  }

  /// The catalog's games out on [platform], dated by their release there.
  @override
  Future<List<LookupMatch>> searchOnPlatform(
    String query,
    GamePlatform platform, {
    int limit = 10,
  }) async {
    await _call('search:${query.trim().toLowerCase()}:${platform.name}');
    return [
      for (final match in catalogSearch(query, type: MediaType.games))
        if (match.platforms.map(normalizePlatform).contains(platform.name))
          match.copyWith(released: _releasedOn[(match.source, platform.name)]),
    ].take(limit).toList();
  }

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async {
    await _call('match:$title:${type.name}');
    final wanted = title.trim().toLowerCase();
    for (final match in fakeCatalog) {
      if (match.type == type &&
          match.title.toLowerCase() == wanted &&
          (year == null || match.released?.year == year)) {
        return match;
      }
    }
    final slug = slugify(title);
    if (slug.isEmpty) return null;
    final shape = type == MediaType.music ? 'square' : 'poster';
    return LookupMatch(
      type: type,
      title: title,
      source: 'fake:$slug',
      released: year == null ? null : Released(year),
      creator: creator,
      coverUrl: 'fake://cover/$shape/fake:$slug',
    );
  }

  @override
  Future<LookupMatch> details(LookupMatch match) async {
    await _call('details:${match.source}');
    return match;
  }

  @override
  Future<ShowSeasons?> seasons(String source) async {
    await _call('seasons:$source');
    final canceled = canceledSources.contains(source);
    final kind = kindBySource[source];
    if (seasonsBySource[source] case final seasons?) {
      return (seasons: seasons, canceled: canceled, kind: kind);
    }
    for (final match in fakeCatalog) {
      if (match.source == source) {
        return (seasons: match.seasons, canceled: canceled, kind: kind);
      }
    }
    return null;
  }

  @override
  Future<Released?> releaseDate(String source) async {
    await _call('released:$source');
    return releasedBySource[source];
  }

  @override
  Future<MovieDates?> movieDates(String source) async {
    await _call('movie-dates:$source');
    if (movieDatesBySource.containsKey(source)) {
      return movieDatesBySource[source];
    }
    return fakeMovieDates()[source];
  }

  @override
  Future<EditionRelease?> editionRelease(
    String source, {
    required Set<String> languages,
  }) async {
    await _call('editions:$source:${(languages.toList()..sort()).join(',')}');
    return editionsBySource[source];
  }

  @override
  Future<SeriesParts?> seriesParts(String source, {String? name}) async {
    await _call('series:$source');
    if (seriesBySource.containsKey(source)) return seriesBySource[source];
    return _seriesBySource[source];
  }

  @override
  Future<List<EpisodeInfo>?> seasonEpisodes(String source, int season) async {
    await _call('episodes:$source:$season');
    return episodesBySeason[(source, season)] ??
        _episodesBySeason[(source, season)] ??
        (source == 'fake:severance' && season == 3
            ? _airingFromToday()
            : const []);
  }

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    await _call('cover:$source');
    final shape = type == MediaType.music ? 'square' : 'poster';
    return 'fake://cover/$shape/$source';
  }

  /// Four other editions of any title, each with its own (fake) cover;
  /// books say which edition, as Open Library and Apple Books do.
  @override
  Future<List<LookupMatch>> coverChoices(
    String title, {
    required MediaType type,
    String? creator,
  }) async {
    await _call('covers:$title:${type.name}');
    final slug = slugify(title);
    if (slug.isEmpty) return const [];
    final shape = type == MediaType.music ? 'square' : 'poster';
    const editions = [
      (2019, 'Ebook'),
      (2009, 'Paperback'),
      (2024, 'TV tie-in'),
      (1986, 'Paperback'),
    ];
    return [
      for (final (i, (year, edition)) in editions.indexed)
        LookupMatch(
          type: type,
          title: title,
          source: 'fake:$slug-${i + 2}',
          released: Released(year),
          creator: creator,
          edition: type == MediaType.books ? edition : null,
          coverUrl: 'fake://cover/$shape/fake:$slug-${i + 2}',
        ),
    ];
  }

  @override
  Future<List<TrackInfo>> albumTracks(String albumSource) async {
    await _call('tracks:$albumSource');
    return _trackListsBySource[albumSource] ?? const [];
  }

  // Followed creators (Settings › Upcoming releases).

  @override
  Set<FollowKind> get creatorKinds => const {
    FollowKind.authors,
    FollowKind.artists,
    FollowKind.directors,
    FollowKind.studios,
    FollowKind.actors,
  };

  /// Every name is a creator, `fake:creator:<slug>`; the built-in table says
  /// who died (for the people TMDB would say it for; the rest come through
  /// [inactiveOf], as Wikidata's do).
  @override
  Future<CreatorMatch?> findCreator(FollowKind kind, String name) async {
    await _call('creator:${kind.key}:$name');
    final slug = slugify(name);
    if (slug.isEmpty) return null;
    final inactive = kind == FollowKind.directors || kind == FollowKind.actors
        ? _inactiveOf(name)
        : null;
    return (providerId: 'fake:creator:$slug', inactive: inactive);
  }

  Inactive? _inactiveOf(String name) =>
      inactiveByName[name.toLowerCase()] ?? fakeInactive[name.toLowerCase()];

  @override
  Future<Map<String, Inactive>> inactiveOf(
    FollowKind kind,
    List<String> names,
  ) async {
    await _call('inactive:${kind.key}:${names.length}');
    return {for (final name in names) name: ?_inactiveOf(name)};
  }

  @override
  Future<List<LookupMatch>> creatorReleases(
    String providerId,
    FollowKind kind, {
    required DateTime today,
  }) async {
    await _call('releases:$providerId');
    final releases =
        releasesByCreator[providerId] ?? fakeCreatorReleases()[providerId];
    return [
      for (final match in releases ?? const <LookupMatch>[])
        if (isRecentOrAhead(match.released, today)) match,
    ];
  }

  /// Every artist but "Various Artists" has a photo.
  @override
  Future<String?> artistPhotoUrl(String name) async {
    await _call('photo:$name');
    if (name.trim().toLowerCase() == 'various artists') return null;
    return 'fake://cover/square/artist:${slugify(name)}';
  }

  /// The catalog, synchronously: a case-insensitive substring match on the
  /// title, titles that start with the query first.
  static List<LookupMatch> catalogSearch(String query, {MediaType? type}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = fakeCatalog.where(
      (m) =>
          (type == null || m.type == type) && m.title.toLowerCase().contains(q),
    );
    final starts = hits.where((m) => m.title.toLowerCase().startsWith(q));
    final rest = hits.where((m) => !m.title.toLowerCase().startsWith(q));
    return [...starts, ...rest];
  }
}

/// Track lists for the catalog's Dirt and for the fixture's Dirt and Dark
/// Side of the Moon (matched on the device as `fake:<slug>`).
const _dirt = [
  (id: 'deezer:track:1016550', title: 'Them Bones'),
  (id: 'deezer:track:1016551', title: 'Dam That River'),
  (id: 'deezer:track:1016552', title: 'Rain When I Die'),
  (id: 'deezer:track:1016553', title: 'Down in a Hole'),
  (id: 'deezer:track:1016554', title: 'Sickman'),
  (id: 'deezer:track:1016555', title: 'Rooster'),
  (id: 'deezer:track:1016556', title: 'Junkhead'),
  (id: 'deezer:track:1016557', title: 'Dirt'),
  (id: 'deezer:track:1016558', title: 'God Smack'),
  (id: 'deezer:track:1016559', title: 'Iron Gland'),
  (id: 'deezer:track:1016560', title: 'Hate to Feel'),
  (id: 'deezer:track:1016561', title: 'Angry Chair'),
  (id: 'deezer:track:1016562', title: 'Would?'),
];

const _trackListsBySource = <String, List<TrackInfo>>{
  'fake:dirt': _dirt,
  'deezer:album:91627': _dirt,
  'fake:the-dark-side-of-the-moon': [
    (id: 'deezer:track:3133701', title: 'Speak to Me'),
    (id: 'deezer:track:3133702', title: 'Breathe (In the Air)'),
    (id: 'deezer:track:3133703', title: 'On the Run'),
    (id: 'deezer:track:3133704', title: 'Time'),
    (id: 'deezer:track:3133705', title: 'The Great Gig in the Sky'),
    (id: 'deezer:track:3133706', title: 'Money'),
    (id: 'deezer:track:3133707', title: 'Us and Them'),
    (id: 'deezer:track:3133708', title: 'Any Colour You Like'),
    (id: 'deezer:track:3133709', title: 'Brain Damage'),
    (id: 'deezer:track:3133710', title: 'Eclipse'),
  ],
};

/// Series for the fixture's The Lord of the Rings movies (Library › Movie in
/// a series) and Berserk volumes (Library › Book in a long series; All
/// volumes in a series), matched on the device as `fake:<slug>`, so each
/// owned part finds the same list.
final _seriesBySource = <String, SeriesParts>{
  for (final slug in [
    'the-lord-of-the-rings-the-fellowship-of-the-ring',
    'the-lord-of-the-rings-the-two-towers',
    'the-lord-of-the-rings-the-return-of-the-king',
  ])
    'fake:$slug': _lordOfTheRings,
  for (final n in [1, 42, 43]) 'fake:berserk-vol-$n': _berserk,
};

const _lordOfTheRings = (
  name: 'The Lord of the Rings',
  parts: <SeriesPart>[
    (
      number: 1,
      title: 'The Lord of the Rings: The Fellowship of the Ring',
      year: 2001,
      released: null,
      source: 'fake:the-lord-of-the-rings-the-fellowship-of-the-ring',
      creator: null,
      cover: 'fake://cover/poster/fake:the-lord-of-the-rings-the-fellowship-of-the-ring',
      extra: false,
    ),
    (
      number: 2,
      title: 'The Lord of the Rings: The Two Towers',
      year: 2002,
      released: null,
      source: 'fake:the-lord-of-the-rings-the-two-towers',
      creator: null,
      cover: 'fake://cover/poster/fake:the-lord-of-the-rings-the-two-towers',
      extra: false,
    ),
    (
      number: 3,
      title: 'The Lord of the Rings: The Return of the King',
      year: 2003,
      released: null,
      source: 'fake:the-lord-of-the-rings-the-return-of-the-king',
      creator: null,
      cover: 'fake://cover/poster/fake:the-lord-of-the-rings-the-return-of-the-king',
      extra: false,
    ),
    // Announced, as TMDB lists it: a part still to come, which the series
    // check records for the place that will list everything coming (the
    // home lists only entries set Want).
    (
      number: 4,
      title: 'The Lord of the Rings: The Hunt for Gollum',
      year: 2027,
      released: Released(2027, 12, 17),
      source: 'fake:the-lord-of-the-rings-the-hunt-for-gollum',
      creator: null,
      cover:
          'fake://cover/poster/fake:the-lord-of-the-rings-the-hunt-for-gollum',
      extra: false,
    ),
  ],
);

/// 43 volumes; the years are sample data, like the canvas's.
final _berserk = (
  name: 'Berserk',
  parts: <SeriesPart>[
    for (var n = 1; n <= 43; n++)
      (
        number: n,
        title: 'Berserk, Vol. $n',
        year: switch (n) {
          41 => 2018,
          42 => 2021,
          43 => 2025,
          _ => 1990 + ((n - 1) * 27 / 39).round(),
        },
        released: null,
        source: 'fake:berserk-vol-$n',
        creator: null,
        cover: 'fake://cover/poster/fake:berserk-vol-$n',
        extra: false,
      ),
  ],
);

/// Episodes for the fixture's Stranger Things season 1 (all out on one day,
/// Show & seasons › Season episodes (all out)), The Haunting of Hill House (one
/// season, Show & seasons › Episodes of a one-season show), Severance
/// seasons 1 and 2 (weekly) and Frieren's two seasons (an anime series, Show &
/// seasons › Anime season episodes), matched on the device as `fake:<slug>`.
final _episodesBySeason = <(String, int), List<EpisodeInfo>>{
  ('fake:frieren-beyond-journeys-end', 1): _weekly(
    DateTime(2023, 9, 29),
    const [
      ("The Journey's End", 24),
      ("It Didn't Have to Be Magic", 24),
      ('Killing Magic', 24),
      ('The Land Where Souls Rest', 24),
    ],
  ),
  ('fake:frieren-beyond-journeys-end', 2): _weekly(
    DateTime(2026, 1, 16),
    const [
      ('A New Journey', 24),
      ('The Northern Road', 24),
      ('First-Class Mages', 24),
      ('The Old Bridge', 24),
      ('Snowfall', 24),
      ('A Familiar Spell', 24),
      ('The Village Festival', 24),
      ('Graves of Heroes', 24),
      ('Echoes', 24),
      ('Spring Again', 24),
    ],
  ),
  ('fake:stranger-things', 1): _sameDay(Released(2016, 7, 15), const [
    ('Chapter One: The Vanishing of Will Byers', 47),
    ('Chapter Two: The Weirdo on Maple Street', 55),
    ('Chapter Three: Holly, Jolly', 51),
    ('Chapter Four: The Body', 50),
    ('Chapter Five: The Flea and the Acrobat', 52),
    ('Chapter Six: The Monster', 46),
    ('Chapter Seven: The Bathtub', 41),
    ('Chapter Eight: The Upside Down', 54),
  ]),
  ('fake:the-haunting-of-hill-house', 1): _sameDay(
    Released(2018, 10, 12),
    const [
      ('Steven Sees a Ghost', 59),
      ('Open Casket', 58),
      ('The Twin Thing', 50),
      ('Touch', 50),
      ('The Bent-Neck Lady', 54),
      ('Two Storms', 57),
      ('Eulogy', 54),
      ('Witness Marks', 50),
      ('Screaming Meemies', 61),
      ('Silence Lay Steadily', 71),
    ],
  ),
  ('fake:severance', 1): _weekly(DateTime(2022, 2, 18), const [
    ('Good News About Hell', 57),
    ('Half Loop', 53),
    ('In Perpetuity', 50),
    ('The You You Are', 49),
    ('The Grim Barbarity of Optics and Design', 44),
    ('Hide and Seek', 53),
    ('Defiant Jazz', 52),
    ("What's for Dinner?", 41),
    ('The We We Are', 40),
  ]),
  ('fake:severance', 2): _weekly(DateTime(2025, 1, 17), const [
    ('Hello, Ms. Cobel', 50),
    ('Goodbye, Mrs. Selvig', 53),
    ('Who Is Alive?', 49),
    ("Woe's Hollow", 48),
    ("Trojan's Horse", 50),
    ('Attila', 52),
    ('Chikhai Bardo', 56),
    ('Sweet Vitriol', 49),
    ('The After Hours', 51),
    ('Cold Harbor', 76),
  ]),
};

List<EpisodeInfo> _sameDay(Released day, List<(String, int)> episodes) => [
  for (final (i, (title, runtime)) in episodes.indexed)
    (number: i + 1, title: title, aired: day, runtime: runtime),
];

List<EpisodeInfo> _weekly(DateTime first, List<(String, int)> episodes) => [
  for (final (i, (title, runtime)) in episodes.indexed)
    (
      number: i + 1,
      title: title,
      aired: _day(DateTime(first.year, first.month, first.day + 7 * i)),
      runtime: runtime,
    ),
];

Released _day(DateTime d) => Released(d.year, d.month, d.day);

/// Severance season 3, airing weekly from today (Show & seasons › Season
/// episodes (airing weekly)): the first episode out, two more titled, the rest
/// "Title TBA" with no runtime yet.
List<EpisodeInfo> _airingFromToday() {
  final now = seasonClock();
  const titles = ['Cold Open', 'Lumon Days', 'The Testing Floor'];
  return [
    for (var i = 0; i < 8; i++)
      (
        number: i + 1,
        title: i < titles.length ? titles[i] : null,
        // Calendar days, so a clock change does not shift the date.
        aired: _day(DateTime(now.year, now.month, now.day + 7 * i)),
        runtime: i == 0 ? 54 : null,
      ),
  ];
}

/// IGDB's records for the platforms [FakeLookupSource.platforms] lists.
const _platformRows = <Map<String, Object?>>[
  {'id': 52, 'name': 'Arcade', 'abbreviation': 'Arcade'},
  {
    'id': 33,
    'name': 'Game Boy',
    'abbreviation': 'Game Boy',
    'alternative_name': 'GB',
  },
  {
    'id': 22,
    'name': 'Game Boy Color',
    'abbreviation': 'GBC',
    'alternative_name': 'GBC',
  },
  {
    'id': 18,
    'name': 'Nintendo Entertainment System',
    'abbreviation': 'NES',
    'alternative_name': 'NES',
  },
  {
    'id': 4,
    'name': 'Nintendo 64',
    'abbreviation': 'N64',
    'alternative_name': 'N64',
  },
  {
    'id': 130,
    'name': 'Nintendo Switch',
    'abbreviation': 'Switch',
    'alternative_name': 'NX',
  },
  {
    'id': 6,
    'name': 'PC (Microsoft Windows)',
    'abbreviation': 'PC',
    'alternative_name': 'mswin',
  },
  {
    'id': 7,
    'name': 'PlayStation',
    'abbreviation': 'PS1',
    'alternative_name': 'PSX, PSOne',
  },
  {
    'id': 8,
    'name': 'PlayStation 2',
    'abbreviation': 'PS2',
    'alternative_name': 'PS2',
  },
  {
    'id': 9,
    'name': 'PlayStation 3',
    'abbreviation': 'PS3',
    'alternative_name': 'PS3',
  },
  {
    'id': 48,
    'name': 'PlayStation 4',
    'abbreviation': 'PS4',
    'alternative_name': 'PS4',
  },
  {
    'id': 167,
    'name': 'PlayStation 5',
    'abbreviation': 'PS5',
    'alternative_name': 'PS5',
  },
  {
    'id': 29,
    'name': 'Sega Mega Drive/Genesis',
    'abbreviation': 'Genesis/MegaDrive',
    'alternative_name': 'Sega Genesis',
  },
  {
    'id': 32,
    'name': 'Sega Saturn',
    'abbreviation': 'Saturn',
    'alternative_name': 'Saturn',
  },
  {
    'id': 19,
    'name': 'Super Nintendo Entertainment System',
    'abbreviation': 'SNES',
    'alternative_name': 'SNES, Super Nintendo',
  },
  {
    'id': 5,
    'name': 'Wii',
    'abbreviation': 'Wii',
    'alternative_name': 'Revolution',
  },
  {
    'id': 169,
    'name': 'Xbox Series X|S',
    'abbreviation': 'Series X|S',
    'alternative_name': 'XSX',
  },
];

/// Where a catalog game came out later on a platform than its first
/// release, by source and platform name.
const _releasedOn = <(String, String), Released>{
  ('igdb:322188', 'Wii'): Released(2011, 12, 2),
  ('igdb:322188', 'Sega Mega Drive/Genesis'): Released(1994, 6, 25),
  ('igdb:39496', 'Wii'): Released(2008, 9, 30),
};

const fakeCatalog = <LookupMatch>[
  LookupMatch(
    source: 'igdb:1009',
    coverUrl: 'fake://cover/poster/igdb:1009',
    type: MediaType.games,
    title: 'The Last of Us',
    released: Released(2013, 6, 14),
    creator: 'Naughty Dog',
    description: 'Joel and Ellie cross a ruined United States.',
    platforms: ['PlayStation 3', 'PlayStation 4', 'PlayStation 5', 'PC'],
    tags: [
      'horror',
      'adventure',
      'post-apocalyptic',
      'stealth',
      'survival',
      'zombies',
    ],
  ),
  LookupMatch(
    source: 'igdb:112875',
    coverUrl: 'fake://cover/poster/igdb:112875',
    type: MediaType.games,
    title: 'The Last of Us Part II',
    released: Released(2020, 6, 19),
    creator: 'Naughty Dog',
    description: 'Five years on, Ellie sets out for Seattle.',
    platforms: ['PlayStation 4', 'PlayStation 5', 'PC'],
    tags: ['adventure', 'post-apocalyptic', 'stealth', 'survival'],
  ),
  LookupMatch(
    source: 'tmdb:tv:100088',
    coverUrl: 'fake://cover/poster/tmdb:tv:100088',
    type: MediaType.shows,
    title: 'The Last of Us',
    released: Released(2023),
    creator: 'Craig Mazin, Neil Druckmann',
    cast: ['Pedro Pascal', 'Bella Ramsey', 'Gabriel Luna'],
    description: 'The HBO adaptation of the game.',
    network: 'HBO',
    tags: ['drama', 'horror', 'post-apocalyptic'],
    seasons: [
      Season(season: 1, released: Released(2023, 1, 15)),
      Season(season: 2, released: Released(2025, 4, 13)),
    ],
  ),
  LookupMatch(
    source: 'igdb:7340',
    coverUrl: 'fake://cover/poster/igdb:7340',
    type: MediaType.games,
    title: 'The Last of Us: Left Behind',
    released: Released(2014, 2, 14),
    creator: 'Naughty Dog',
    description: 'A standalone chapter about Ellie and Riley.',
    platforms: ['PlayStation 3', 'PlayStation 4'],
    tags: ['adventure', 'post-apocalyptic'],
  ),
  LookupMatch(
    source: 'tmdb:tv:243005',
    coverUrl: 'fake://cover/poster/tmdb:tv:243005',
    type: MediaType.shows,
    title: 'Carrie',
    released: Released(2026),
    creator: 'Mike Flanagan',
    cast: ['Summer H. Howell', 'Samantha Sloyan', 'Siena Agudong'],
    description: 'A limited series take on the Stephen King novel.',
    network: 'Prime Video',
    tags: ['horror', 'drama'],
    seasons: [Season(season: 1, released: Released(2026))],
  ),
  LookupMatch(
    source: 'tmdb:movie:133805',
    coverUrl: 'fake://cover/poster/tmdb:movie:133805',
    type: MediaType.movies,
    title: 'Carrie',
    released: Released(2013),
    creator: 'Kimberly Peirce',
    cast: ['Chloë Grace Moretz', 'Julianne Moore', 'Gabriella Wilde'],
    description:
        'A shy teenager with telekinetic powers is pushed too far at prom.',
    tags: ['horror', 'drama'],
  ),
  LookupMatch(
    source: 'tmdb:movie:7340',
    coverUrl: 'fake://cover/poster/tmdb:movie:7340',
    type: MediaType.movies,
    title: 'Carrie',
    released: Released(1976),
    creator: 'Brian De Palma',
    cast: ['Sissy Spacek', 'Piper Laurie', 'Amy Irving'],
    description:
        'A sheltered girl discovers her powers after a cruel prank at prom.',
    tags: ['horror', 'classic'],
  ),
  LookupMatch(
    source: 'openlibrary:OL81613W',
    coverUrl: 'fake://cover/poster/openlibrary:OL81613W',
    type: MediaType.books,
    title: 'Carrie',
    released: Released(1974),
    creator: 'Stephen King',
    description:
        "Stephen King's first novel, told through clippings and "
        'testimony.',
    tags: ['horror', 'stephen-king'],
    pages: 199,
  ),
  LookupMatch(
    source: 'openlibrary:OL893415W',
    coverUrl: 'fake://cover/poster/openlibrary:OL893415W',
    type: MediaType.books,
    title: 'Dune',
    released: Released(1965),
    creator: 'Frank Herbert',
    description: 'Paul Atreides and the desert planet Arrakis.',
    tags: ['sci-fi', 'epic', 'classic'],
    pages: 412,
  ),
  LookupMatch(
    source: 'tmdb:movie:841',
    coverUrl: 'fake://cover/poster/tmdb:movie:841',
    type: MediaType.movies,
    title: 'Dune',
    released: Released(1984),
    creator: 'David Lynch',
    cast: ['Kyle MacLachlan', 'Francesca Annis', 'Brad Dourif'],
    description: "David Lynch's adaptation of the Frank Herbert novel.",
    tags: ['sci-fi', 'epic', 'cult'],
  ),
  LookupMatch(
    source: 'tmdb:movie:438631',
    coverUrl: 'fake://cover/poster/tmdb:movie:438631',
    type: MediaType.movies,
    title: 'Dune',
    released: Released(2021),
    creator: 'Denis Villeneuve',
    cast: ['Timothée Chalamet', 'Rebecca Ferguson', 'Oscar Isaac'],
    description:
        'The first half of the novel, from Caladan to the deep '
        'desert.',
    tags: ['sci-fi', 'epic', 'adventure'],
  ),
  LookupMatch(
    source: 'igdb:144213',
    coverUrl: 'fake://cover/poster/igdb:144213',
    type: MediaType.games,
    title: 'Dune: Awakening',
    released: Released(2025, 6, 10),
    creator: 'Funcom',
    description: 'An open-world survival game set on Arrakis.',
    platforms: ['PC'],
    tags: ['survival', 'sci-fi', 'open-world'],
  ),
  LookupMatch(
    source: 'tmdb:movie:508442',
    coverUrl: 'fake://cover/poster/tmdb:movie:508442',
    type: MediaType.movies,
    title: 'Soul',
    released: Released(2020, 12, 25),
    creator: 'Pete Docter',
    cast: ['Jamie Foxx', 'Tina Fey', 'Graham Norton'],
    description: 'A music teacher gets a second look at what makes a life.',
    companies: ['Pixar', 'Walt Disney Pictures'],
    tags: ['animation', 'comedy', 'fantasy'],
  ),
  LookupMatch(
    source: 'anilist:154587',
    coverUrl: 'fake://cover/poster/anilist:154587',
    type: MediaType.anime,
    title: "Frieren: Beyond Journey's End",
    released: Released(2023, 9, 29),
    creator: 'Madhouse',
    companies: ['Madhouse'],
    description:
        'An elf mage outlives the hero\u2019s party she traveled with and '
        'sets out to understand the people she lost.',
    tags: ['adventure', 'fantasy', 'drama'],
    kind: EntryKind.series,
    seasons: [
      Season(season: 1, released: Released(2023, 9, 29)),
      Season(season: 2, released: Released(2026, 1, 16)),
    ],
  ),
  LookupMatch(
    source: 'anilist:199',
    coverUrl: 'fake://cover/poster/anilist:199',
    type: MediaType.anime,
    title: 'Spirited Away',
    released: Released(2001, 7, 20),
    creator: 'Studio Ghibli',
    kind: EntryKind.movie,
    description:
        'Chihiro works in a bathhouse for spirits to free her parents.',
    companies: ['Studio Ghibli'],
    tags: ['adventure', 'fantasy', 'supernatural'],
    language: 'ja',
  ),
  LookupMatch(
    source: 'anilist:47',
    coverUrl: 'fake://cover/poster/anilist:47',
    type: MediaType.anime,
    title: 'Akira',
    released: Released(1988),
    creator: 'Katsuhiro Otomo',
    kind: EntryKind.movie,
    description: 'A biker gang, a secret military project and Neo-Tokyo.',
    tags: ['2d', 'scifi', 'cyberpunk', 'classic'],
  ),
  LookupMatch(
    source: 'openlibrary:OL15366647W',
    coverUrl: 'fake://cover/poster/openlibrary:OL15366647W',
    type: MediaType.books,
    title: 'Akira',
    released: Released(1982),
    creator: 'Katsuhiro Otomo',
    description: 'The manga the film was drawn from.',
    tags: ['manga', 'scifi', 'cyberpunk'],
    language: 'jpn',
  ),
  LookupMatch(
    source: 'tmdb:movie:78',
    coverUrl: 'fake://cover/poster/tmdb:movie:78',
    type: MediaType.movies,
    title: 'Blade Runner',
    released: Released(1982),
    creator: 'Ridley Scott',
    cast: ['Harrison Ford', 'Rutger Hauer', 'Sean Young'],
    description: 'A blade runner hunts four replicants in 2019 Los Angeles.',
    tags: ['sci-fi', 'neo-noir', 'classic', 'dark'],
  ),
  LookupMatch(
    source: 'tmdb:movie:335984',
    coverUrl: 'fake://cover/poster/tmdb:movie:335984',
    type: MediaType.movies,
    title: 'Blade Runner 2049',
    released: Released(2017),
    creator: 'Denis Villeneuve',
    cast: ['Ryan Gosling', 'Harrison Ford', 'Ana de Armas'],
    description:
        'A new blade runner unearths a secret that could end '
        'everything.',
    tags: ['sci-fi', 'neo-noir', 'melancholic'],
  ),
  LookupMatch(
    source: 'anilist:437',
    coverUrl: 'fake://cover/poster/anilist:437',
    type: MediaType.anime,
    title: 'Perfect Blue',
    released: Released(1997),
    creator: 'Satoshi Kon',
    kind: EntryKind.movie,
    description: 'A pop idol turned actress loses her grip on what is real.',
    tags: ['2d', 'thriller', 'psychological', 'dark'],
  ),
  LookupMatch(
    source: 'deezer:album:91627',
    coverUrl: 'fake://cover/square/deezer:album:91627',
    type: MediaType.music,
    title: 'Hounds of Love',
    released: Released(1985),
    creator: 'Kate Bush',
    description: "Kate Bush's fifth studio album.",
    tags: ['art-pop', 'pop', 'classic'],
  ),
  LookupMatch(
    source: 'deezer:track:1016551',
    coverUrl: 'fake://cover/square/deezer:track:1016551',
    albumSource: 'deezer:album:91627',
    type: MediaType.music,
    title: 'Running Up That Hill',
    released: Released(1985),
    creator: 'Kate Bush',
    album: 'Hounds of Love',
    tags: ['art-pop', 'pop', 'synth'],
  ),
  LookupMatch(
    source: 'igdb:267306',
    coverUrl: 'fake://cover/poster/igdb:267306',
    type: MediaType.games,
    title: 'Silent Hill 2',
    released: Released(2024, 10, 8),
    creator: 'Bloober Team',
    description: 'The remake of the 2001 survival horror game.',
    platforms: ['PlayStation 5', 'PC'],
    tags: ['survival-horror', 'horror', 'psychological'],
  ),
  LookupMatch(
    source: 'igdb:321621',
    coverUrl: 'fake://cover/poster/igdb:321621',
    type: MediaType.games,
    title: 'Street Fighter II',
    released: Released(1992, 6, 10),
    creator: 'Capcom',
    description: 'The Super Nintendo port of the 1991 arcade game.',
    platforms: [
      'Super Nintendo Entertainment System',
      'Wii',
      'Wii U',
      'Super Famicom',
    ],
    tags: ['fighting', 'arcade'],
  ),
  LookupMatch(
    source: 'igdb:3186',
    coverUrl: 'fake://cover/poster/igdb:3186',
    type: MediaType.games,
    title: 'Street Fighter II',
    released: Released(1991, 2, 6),
    creator: 'Capcom',
    description: 'Eight world warriors, one tournament.',
    platforms: ['Arcade'],
    tags: ['fighting', 'arcade'],
  ),
  LookupMatch(
    source: 'igdb:39496',
    coverUrl: 'fake://cover/poster/igdb:39496',
    type: MediaType.games,
    title: 'Street Fighter II: Champion Edition',
    released: Released(1992, 3, 13),
    creator: 'Capcom',
    description: 'The four bosses become playable.',
    platforms: ['Arcade', 'TurboGrafx-16/PC Engine', 'Wii'],
    tags: ['fighting', 'arcade'],
  ),
  LookupMatch(
    source: 'igdb:322188',
    coverUrl: 'fake://cover/poster/igdb:322188',
    type: MediaType.games,
    title: 'Super Street Fighter II',
    released: Released(1994, 6, 25),
    creator: 'Capcom',
    description: 'Four new challengers join the tournament.',
    platforms: [
      'Super Nintendo Entertainment System',
      'Sega Mega Drive/Genesis',
      'Wii',
    ],
    tags: ['fighting', 'arcade'],
  ),
];

/// Who is no longer active, by name in lowercase: the fixture's artists and
/// a few people, for Settings › Follow: authors and Follow: actors.
const fakeInactive = <String, Inactive>{
  'miles davis': Inactive(InactiveReason.died, year: 1991),
  '2pac': Inactive(InactiveReason.died, year: 1996),
  "screamin' jay hawkins": Inactive(InactiveReason.died, year: 2000),
  'creedence clearwater revival': Inactive(
    InactiveReason.disbanded,
    year: 1972,
  ),
  'j. r. r. tolkien': Inactive(InactiveReason.died, year: 1973),
  'sean connery': Inactive(InactiveReason.died, year: 2020),
};

/// A day [days] from the app clock, as a release.
Released _inDays(int days) {
  final d = seasonClock().add(Duration(days: days));
  return Released(d.year, d.month, d.day);
}

/// The dates by kind of the fake's movies that have them: the Clint
/// Eastwood movie of [fakeCreatorReleases] opens in cinemas in six weeks
/// and comes to digital two months after (Settings › Movies › Release
/// dates: Both shows both in the add sheet).
Map<String, MovieDates> fakeMovieDates() => {
  'fake:creator-release:eastwood-next': MovieDates(
    cinema: _inDays(42),
    digital: _inDays(42 + 61),
  ),
};

/// What the fixture's followed creators have coming, dated from the app
/// clock so the rows read "coming" whatever the day: an Alice in Chains
/// album in three weeks, a FromSoftware game in two months, a Clint
/// Eastwood movie in six weeks (he directs and stars), a Studio Ghibli film
/// next spring.
Map<String, List<LookupMatch>> fakeCreatorReleases() {
  final inDays = _inDays;

  final eastwood = LookupMatch(
    source: 'fake:creator-release:eastwood-next',
    coverUrl: 'fake://cover/poster/fake:creator-release:eastwood-next',
    type: MediaType.movies,
    title: 'The Last Round',
    released: inDays(42),
    creator: 'Clint Eastwood',
    description: 'A retired fighter takes one more case.',
  );
  return {
    'fake:creator:alice-in-chains': [
      LookupMatch(
        source: 'fake:creator-release:aic-next',
        coverUrl: 'fake://cover/square/fake:creator-release:aic-next',
        type: MediaType.music,
        title: 'Rainier Fog II',
        released: inDays(21),
        creator: 'Alice in Chains',
      ),
    ],
    'fake:creator:fromsoftware': [
      LookupMatch(
        source: 'fake:creator-release:duskbloods',
        coverUrl: 'fake://cover/poster/fake:creator-release:duskbloods',
        type: MediaType.games,
        title: 'The Duskbloods',
        released: inDays(60),
        creator: 'FromSoftware',
        description: 'Bloodhunters fight over the First Blood.',
        platforms: ['Switch 2'],
      ),
    ],
    'fake:creator:clint-eastwood': [eastwood],
    'fake:creator:studio-ghibli': [
      LookupMatch(
        source: 'fake:creator-release:ghibli-next',
        coverUrl: 'fake://cover/poster/fake:creator-release:ghibli-next',
        type: MediaType.movies,
        title: 'The Boy and the River',
        released: Released(seasonClock().year + 1, 4),
        creator: 'Studio Ghibli',
      ),
    ],
  };
}
