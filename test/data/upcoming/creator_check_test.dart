import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/check_day_store.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/movie_dates.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/upcoming/check_control.dart';
import 'package:library_app/data/upcoming/creator_check.dart';
import 'package:library_app/data/upcoming/creator_lookup.dart';
import 'package:library_app/data/upcoming/creator_status.dart';
import 'package:library_app/data/upcoming/follows.dart';
import 'package:library_app/dev/fake_lookup.dart';

void main() {
  final now = DateTime(2026, 10, 30, 9, 30);
  final today = DateTime(2026, 10, 30);

  Entry entry(
    String id,
    MediaType type, {
    required String title,
    EntryStatus status = EntryStatus.done,
    String? creator,
    List<String> tags = const [],
    EntryKind? kind,
  }) => Entry(
    id: id,
    type: type,
    title: title,
    status: status,
    creator: creator,
    tags: tags,
    added: DateTime(2026, 1, 1),
    kind: kind,
  );

  final library = Library(
    tags: const {
      TagCategory.authors: ['stephen-king', 'j-r-r-tolkien'],
      TagCategory.actors: ['pedro-pascal'],
    },
    entries: [
      entry(
        'books/it',
        MediaType.books,
        title: 'It',
        creator: 'Stephen King',
        tags: const ['stephen-king'],
      ),
      entry(
        'books/the-hobbit',
        MediaType.books,
        title: 'The Hobbit',
        creator: 'J. R. R. Tolkien',
        tags: const ['j-r-r-tolkien'],
      ),
      entry(
        'shows/the-last-of-us',
        MediaType.shows,
        title: 'The Last of Us',
        tags: const ['pedro-pascal'],
      ),
      entry(
        'music/dirt',
        MediaType.music,
        title: 'Dirt',
        creator: 'Alice in Chains',
        kind: EntryKind.album,
      ),
    ],
  );

  LookupMatch release(String source, String title, Released released) =>
      LookupMatch(
        type: MediaType.books,
        title: title,
        source: source,
        released: released,
        creator: 'Stephen King',
      );

  final neverFlinch = release(
    'fake:nf',
    'Never Flinch',
    const Released(2027, 5, 27),
  );
  final oldBook = release('fake:it', 'It', const Released(1986, 9, 15));
  final justOut = release('fake:jo', 'Just Out', const Released(2026, 10, 10));
  final longAgo = release('fake:la', 'Long Ago', const Released(2026, 9, 1));

  late MemoryCreatorStatusStore statuses;
  late MemoryFoundReleaseStore releases;
  late MemoryCheckDayStore days;

  setUp(() {
    statuses = MemoryCreatorStatusStore();
    releases = MemoryFoundReleaseStore();
    days = MemoryCheckDayStore();
  });

  CreatorCheck check(FakeLookupSource fake) => CreatorCheck(
    lookups: LookupService([fake]),
    statuses: statuses,
    releases: releases,
    store: days,
  );

  Follows follows([AppSettings settings = AppSettings.defaults]) =>
      deriveFollows(library, settings);

  test('learns who each creator is, who died, and records the releases ahead or just out', () async {
    final fake = FakeLookupSource(
      releasesByCreator: {
        'fake:creator:stephen-king': [neverFlinch, oldBook, justOut, longAgo],
      },
    );
    final result = await check(fake).run(follows(), now);
    expect(result.wrote, isTrue);
    // King's two, and the fake's built-in Alice in Chains album.
    expect(result.found, 3);

    final known = await statuses.read();
    expect(
      known['authors/stephen-king']!.providerId,
      'fake:creator:stephen-king',
    );
    expect(known['authors/stephen-king']!.inactive, isNull);
    // Tolkien died: Wikidata (the fake's table) said so in the batched ask.
    expect(known['authors/j-r-r-tolkien']!.inactive?.label, 'Died 1973');
    // Pedro Pascal is an actor, off by default: who he is was still learned.
    expect(
      known['actors/pedro-pascal']!.providerId,
      'fake:creator:pedro-pascal',
    );
    expect(
      known['artists/alice in chains']!.providerId,
      'fake:creator:alice-in-chains',
    );

    final recorded = await releases.read();
    expect(recorded.map((r) => r.match.title), [
      'Never Flinch',
      'Just Out',
      'Rainier Fog II',
    ]);
    expect(recorded.first.creatorId, 'stephen-king');
    expect(recorded.first.creatorName, 'Stephen King');
    expect(recorded.first.kind, FollowKind.authors);
    expect(recorded.first.foundOn, now);
    // Tolkien's and Pascal's releases were not asked for: not followed.
    expect(fake.calls.where((c) => c.startsWith('releases:')), [
      'releases:fake:creator:stephen-king',
      'releases:fake:creator:alice-in-chains',
    ]);
    // Wikidata was asked once per kind with names, TMDB-like lookups per person.
    expect(fake.calls.where((c) => c.startsWith('inactive:')), [
      'inactive:authors:2',
      'inactive:artists:1',
    ]);
    expect(await days.lastRun(), today);
  });

  test('a creator once known is not asked about again until stale; a dead one ticked is checked', () async {
    final fake = FakeLookupSource(
      releasesByCreator: {
        'fake:creator:j-r-r-tolkien': [
          release(
            'fake:fall',
            'The Fall of Gondolin',
            const Released(2026, 11, 20),
          ),
        ],
      },
    );
    await check(fake).run(follows(), now);
    fake.calls.clear();

    // The next day: statuses are fresh, so only releases are asked for; the
    // owner has ticked Tolkien in the meantime.
    final ticked = deriveFollows(
      library,
      const AppSettings(
        followed: {
          FollowKind.authors: {'j-r-r-tolkien'},
        },
      ),
      statuses: await statuses.read(),
    );
    expect(ticked.find(FollowKind.authors, 'j-r-r-tolkien')!.followed, isTrue);
    final result = await check(fake)
        .run(ticked, now.add(const Duration(days: 1)));
    expect(fake.calls.where((c) => c.startsWith('creator:')), isEmpty);
    expect(fake.calls.where((c) => c.startsWith('inactive:')), isEmpty);
    expect(
      fake.calls.where((c) => c.startsWith('releases:')),
      contains('releases:fake:creator:j-r-r-tolkien'),
    );
    expect(result.found, 1);
    expect(
      (await releases.read()).map((r) => r.match.title),
      contains('The Fall of Gondolin'),
    );

    // Ninety days on, the statuses are asked again.
    fake.calls.clear();
    await check(fake).run(ticked, now.add(const Duration(days: 91)));
    expect(fake.calls.where((c) => c.startsWith('creator:')), isNotEmpty);
  });

  test('a found book is kept only with an edition in the languages read, '
      'dated by it; a found movie takes the first of its dates by kind, '
      'which are recorded', () async {
    final movie = LookupMatch(
      type: MediaType.movies,
      title: 'The Last Round',
      source: 'fake:last-round',
      released: const Released(2026, 12, 18),
      creator: 'Clint Eastwood',
    );
    const dates = MovieDates(
      cinema: Released(2026, 12, 17),
      digital: Released(2027, 2),
    );
    final fake = FakeLookupSource(
      releasesByCreator: {
        'fake:creator:stephen-king': [neverFlinch, justOut, movie],
      },
      editionsBySource: {
        // Only in Japanese: not listed.
        'fake:nf': (inLanguages: false, released: null),
        // The English edition comes later than the work's year.
        'fake:jo': (inLanguages: true, released: const Released(2026, 11, 3)),
      },
      movieDatesBySource: {'fake:last-round': dates},
    );
    final store = MemoryMovieDateStore();
    final result = await CreatorCheck(
      lookups: LookupService([fake]),
      statuses: statuses,
      releases: releases,
      store: days,
      movieDates: store,
    ).run(follows(), now, languages: {'en', 'sv'});
    expect(result.wrote, isTrue);
    final kings = [
      for (final r in await releases.read())
        if (r.creatorId == 'stephen-king') r,
    ];
    expect(kings.map((r) => r.match.title), ['Just Out', 'The Last Round']);
    expect(kings.first.match.released, const Released(2026, 11, 3));
    expect(kings.last.match.released, const Released(2026, 12, 17));
    expect(await store.read(), {'fake:last-round': dates});
    expect(
      fake.calls,
      containsAll(['editions:fake:nf:en,sv', 'movie-dates:fake:last-round']),
    );
    // Without languages no book is asked about its editions.
    fake.calls.clear();
    await check(fake).run(follows(), now, force: true);
    expect(fake.calls.where((c) => c.startsWith('editions:')), isEmpty);
  });

  test('a director who also acts keeps the director\'s releases while the '
      'actor follow is off (fixed 2026-10-31)', () async {
    final both = Library(
      tags: const {
        TagCategory.directors: ['clint-eastwood'],
        TagCategory.actors: ['clint-eastwood'],
      },
      entries: [
        entry(
          'movies/million-dollar-baby',
          MediaType.movies,
          title: 'Million Dollar Baby',
          creator: 'Clint Eastwood',
          tags: const ['clint-eastwood'],
        ).copyWith(
          tagCategories: const {
            'clint-eastwood': [TagCategory.directors, TagCategory.actors],
          },
        ),
      ],
    );
    final fake = FakeLookupSource();
    final result = await check(fake)
        .run(deriveFollows(both, AppSettings.defaults), now);
    expect(result.found, 1);
    expect((await releases.read()).map((r) => r.match.title), [
      'The Last Round',
    ]);
  });

  test('an unfollowed creator\'s releases leave the record', () async {
    final fake = FakeLookupSource(
      releasesByCreator: {
        'fake:creator:stephen-king': [neverFlinch],
      },
    );
    await check(fake).run(follows(), now);
    Future<List<FoundRelease>> kings() async => [
      for (final r in await releases.read())
        if (r.creatorId == 'stephen-king') r,
    ];
    expect(await kings(), hasLength(1));
    final unfollowed = deriveFollows(
      library,
      const AppSettings(
        unfollowed: {
          FollowKind.authors: {'stephen-king'},
        },
      ),
      statuses: await statuses.read(),
    );
    final result = await check(fake)
        .run(unfollowed, now.add(const Duration(days: 1)));
    expect(result.wrote, isTrue);
    expect(await kings(), isEmpty);
  });

  test('include narrows the run; a stop records no day', () async {
    final fake = FakeLookupSource(
      releasesByCreator: {
        'fake:creator:stephen-king': [neverFlinch],
      },
    );
    var ticks = 0;
    await check(fake).run(
      follows(),
      now,
      include: (f) => f.kind == FollowKind.authors,
      control: CheckControl(onTick: () => ticks++),
    );
    expect(ticks, 2);
    expect(fake.calls.where((c) => c.startsWith('creator:')), [
      'creator:authors:J. R. R. Tolkien',
      'creator:authors:Stephen King',
    ]);
    expect(await days.lastRun(), today);

    days = MemoryCheckDayStore();
    statuses = MemoryCreatorStatusStore();
    var asked = 0;
    await check(fake).run(
      follows(),
      now,
      control: CheckControl(onTick: () => asked++, cancelled: () => asked >= 1),
    );
    expect(asked, 1);
    expect(await days.lastRun(), isNull);
  });

  test('runs once a day unless forced; offline is tried again', () async {
    final fake = FakeLookupSource();
    await check(fake).run(follows(), now);
    fake.calls.clear();
    await check(fake).run(follows(), now.add(const Duration(hours: 2)));
    expect(fake.calls, isEmpty);
    await check(fake)
        .run(follows(), now.add(const Duration(hours: 2)), force: true);
    expect(fake.calls, isNotEmpty);

    days = MemoryCheckDayStore();
    statuses = MemoryCreatorStatusStore();
    final offline = FakeLookupSource(failure: LookupFailure.offline);
    final result = await check(offline).run(follows(), now);
    expect(result.wrote, isFalse);
    expect(await days.lastRun(), isNull);
    expect(await statuses.read(), isEmpty);
  });

  test('found releases survive their stored form', () {
    final found = FoundRelease(
      kind: FollowKind.artists,
      creatorId: 'alice in chains',
      creatorName: 'Alice in Chains',
      match: const LookupMatch(
        type: MediaType.music,
        title: 'Rainier Fog II',
        source: 'deezer:album:1',
        released: Released(2026, 11, 20),
        creator: 'Alice in Chains',
        description: 'The eighth album.',
        coverUrl: 'https://cdn/a.jpg',
        largeCoverUrl: 'https://cdn/a-big.jpg',
      ),
      foundOn: DateTime(2026, 10, 30, 7, 12),
    );
    expect(FoundRelease.fromJson(found.toJson()), found);
    expect(found.key, 'deezer:album:1');
    expect(isRecentOrAhead(const Released(2026, 11, 20), today), isTrue);
    expect(
      isRecentOrAhead(const Released(2026), today),
      isTrue,
      reason: 'year-only counts until the year is out',
    );
    expect(
      isRecentOrAhead(const Released(2026, 10, 1), today),
      isTrue,
      reason: 'within thirty days',
    );
    expect(isRecentOrAhead(const Released(2026, 9, 29), today), isFalse);
    expect(isRecentOrAhead(null, today), isFalse);
  });
}
