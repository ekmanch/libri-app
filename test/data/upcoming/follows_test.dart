import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/creator_names.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/upcoming/creator_status.dart';
import 'package:library_app/data/upcoming/follows.dart';

void main() {
  Entry entry(
    String id,
    MediaType type, {
    required String title,
    EntryStatus status = EntryStatus.done,
    String? creator,
    List<String> tags = const [],
    Map<String, List<TagCategory>>? tagCategories,
    String? source,
    EntryKind? kind,
    List<Season>? seasons,
    Series? series,
  }) => Entry(
    id: id,
    type: type,
    title: title,
    status: status,
    creator: creator,
    tags: tags,
    tagCategories: tagCategories,
    added: DateTime(2026, 1, 1),
    source: source,
    kind: kind,
    seasons: seasons,
    series: series,
  );

  final library = Library(
    tags: const {
      TagCategory.genre: ['horror'],
      TagCategory.authors: ['stephen-king', 'j-k-rowling', 'roald-dahl'],
      TagCategory.directors: ['clint-eastwood', 'mike-flanagan'],
      TagCategory.actors: ['clint-eastwood', 'jenna-ortega'],
      TagCategory.studios: ['pixar'],
    },
    entries: [
      entry(
        'books/it-1986',
        MediaType.books,
        title: 'It',
        creator: 'Stephen King',
        tags: const ['stephen-king', 'horror'],
      ),
      entry(
        'books/the-shining-1977',
        MediaType.books,
        title: 'The Shining',
        creator: 'Stephen King',
        tags: const ['stephen-king'],
      ),
      entry(
        'movies/the-shining-1980',
        MediaType.movies,
        title: 'The Shining',
        creator: 'Stanley Kubrick',
        tags: const ['stephen-king'],
      ),
      // Every entry DNF: not listed.
      entry(
        'books/harry-potter-1997',
        MediaType.books,
        title: 'Harry Potter',
        status: EntryStatus.dnf,
        creator: 'J. K. Rowling',
        tags: const ['j-k-rowling'],
      ),
      // A tag with no entry carrying it in its role: not listed.
      entry(
        'movies/million-dollar-baby-2004',
        MediaType.movies,
        title: 'Million Dollar Baby',
        creator: 'Clint Eastwood',
        tags: const ['clint-eastwood'],
      ),
      entry(
        'movies/the-good-the-bad-1966',
        MediaType.movies,
        title: 'The Good, the Bad and the Ugly',
        tags: const ['clint-eastwood'],
        tagCategories: const {
          'clint-eastwood': [TagCategory.actors],
        },
      ),
      entry(
        'shows/wednesday-2022',
        MediaType.shows,
        title: 'Wednesday',
        creator: 'Mike Flanagan',
        tags: const ['mike-flanagan', 'jenna-ortega'],
        source: 'tmdb:tv:1',
        seasons: const [
          Season(
            season: 1,
            released: Released(2022, 11, 23),
            status: EntryStatus.done,
          ),
          Season(
            season: 2,
            released: Released(2025, 8, 6),
            status: EntryStatus.done,
          ),
        ],
      ),
      entry(
        'shows/dropped-2020',
        MediaType.shows,
        title: 'Dropped',
        status: EntryStatus.dnf,
        source: 'tmdb:tv:2',
        seasons: const [
          Season(season: 1, released: Released(2020), status: EntryStatus.dnf),
        ],
      ),
      entry(
        'shows/by-hand-2020',
        MediaType.shows,
        title: 'By hand',
        seasons: const [
          Season(season: 1, released: Released(2020), status: EntryStatus.done),
        ],
      ),
      entry(
        'anime/frieren-2023',
        MediaType.anime,
        title: 'Frieren',
        source: 'anilist:3',
        kind: EntryKind.series,
        seasons: const [
          Season(season: 1, released: Released(2023), status: EntryStatus.done),
        ],
      ),
      entry(
        'movies/fellowship-2001',
        MediaType.movies,
        title: 'The Fellowship of the Ring',
        series: const Series(name: 'The Lord of the Rings', number: 1),
      ),
      entry(
        'movies/two-towers-2002',
        MediaType.movies,
        title: 'The Two Towers',
        status: EntryStatus.want,
        series: const Series(name: 'The Lord of the Rings', number: 2),
      ),
      // Only wanted: not followed.
      entry(
        'books/dune-1965',
        MediaType.books,
        title: 'Dune',
        status: EntryStatus.want,
        series: const Series(name: 'Dune', number: 1),
      ),
      entry(
        'music/dirt-alice-in-chains',
        MediaType.music,
        title: 'Dirt',
        creator: 'Alice in Chains',
        kind: EntryKind.album,
      ),
      entry(
        'music/rooster-alice-in-chains',
        MediaType.music,
        title: 'Rooster',
        creator: 'alice in chains',
        kind: EntryKind.song,
      ),
      entry(
        'music/the-wall-pink-floyd',
        MediaType.music,
        title: 'The Wall',
        creator: 'Pink Floyd',
        kind: EntryKind.album,
      ),
      entry(
        'music/mix-various-artists',
        MediaType.music,
        title: 'Mix',
        creator: 'Various Artists',
        kind: EntryKind.album,
      ),
      entry(
        'movies/up-2009',
        MediaType.movies,
        title: 'Up',
        creator: 'Pete Docter',
        tags: const ['pixar'],
      ),
    ],
  );

  test('creators come from their tags, in their role, while not all DNF', () {
    final follows = deriveFollows(library, AppSettings.defaults);
    final authors = follows.of(FollowKind.authors);
    expect(authors.map((f) => f.name), ['Stephen King']);
    expect(authors.single.id, 'stephen-king');
    expect(authors.single.detail, '1 movie, 2 books');
    expect(authors.single.entryIds, hasLength(3));
    expect(authors.single.followed, isTrue);

    final directors = follows.of(FollowKind.directors);
    expect(directors.map((f) => f.name), ['Clint Eastwood', 'Mike Flanagan']);
    // Eastwood directs only Million Dollar Baby; he acts in both.
    expect(directors.first.detail, '1 movie');
    final actors = follows.of(FollowKind.actors);
    expect(actors.map((f) => f.name), ['Clint Eastwood', 'Jenna Ortega']);
    expect(actors.first.detail, '2 movies');
    expect(actors.last.detail, '1 show');
    // Actors are off by default.
    expect(actors.every((f) => !f.followed), isTrue);
    expect(follows.of(FollowKind.studios).single.name, 'Pixar');
  });

  test(
    'shows and anime series linked to a lookup, not DNF; followed series',
    () {
      final follows = deriveFollows(library, AppSettings.defaults);
      final shows = follows.of(FollowKind.shows);
      expect(shows.map((f) => f.name), ['Frieren', 'Wednesday']);
      expect(shows.last.detail, '2 seasons');
      expect(shows.first.detail, '1 season');

      final series = follows.of(FollowKind.series);
      expect(series.map((f) => f.name), ['The Lord of the Rings']);
      expect(series.single.id, 'movies/lordoftherings');
      expect(series.single.detail, '2 movies in your library');
    },
  );

  test(
    'artists come from the creator field, one per name whatever the case',
    () {
      final artists = deriveFollows(
        library,
        AppSettings.defaults,
      ).of(FollowKind.artists);
      expect(artists.map((f) => f.name), ['Alice in Chains', 'Pink Floyd']);
      expect(artists.first.id, 'alice in chains');
      expect(artists.first.detail, '1 album, 1 song');
      expect(artists.last.detail, '1 album');
    },
  );

  test('the settings turn follows off and on, and the counts say so', () {
    const settings = AppSettings(
      unfollowed: {
        FollowKind.directors: {'mike-flanagan'},
      },
      followed: {
        FollowKind.actors: {'jenna-ortega'},
      },
    );
    final follows = deriveFollows(library, settings);
    expect(
      follows.find(FollowKind.directors, 'mike-flanagan')!.followed,
      isFalse,
    );
    expect(
      follows.find(FollowKind.directors, 'clint-eastwood')!.followed,
      isTrue,
    );
    expect(follows.countLabel(FollowKind.directors), '1 of 2');
    expect(follows.countLabel(FollowKind.authors), '1');
    expect(follows.countLabel(FollowKind.actors), '1 of 2');
    expect(follows.followedLabel(FollowKind.actors), '1 of 2 followed');
    expect(follows.followedOf(FollowKind.actors).single.name, 'Jenna Ortega');
    expect(follows.mostFollowed(FollowKind.actors), isFalse);
    expect(follows.mostFollowed(FollowKind.authors), isTrue);
    // Every kind but actors has something followed; actors has Jenna.
    expect(follows.kindsFollowed, 7);
    expect(
      deriveFollows(library, AppSettings.defaults).kindsFollowed,
      6,
      reason: 'actors are off until ticked',
    );
    expect(follows.activeDefaults(FollowKind.actors), {
      'clint-eastwood': false,
      'jenna-ortega': false,
    });
  });

  test('a creator no longer active is off by default, tickable', () {
    final statuses = {
      'authors/stephen-king': CreatorStatus(
        kind: FollowKind.authors,
        id: 'stephen-king',
        providerId: 'wikidata:Q39829',
        inactive: const Inactive(InactiveReason.died, year: 2099),
        checkedOn: DateTime(2026, 10, 30),
      ),
      'studios/pixar': CreatorStatus(
        kind: FollowKind.studios,
        id: 'pixar',
        providerId: 'tmdb:company:3',
        inactive: const Inactive(InactiveReason.dissolved),
        checkedOn: DateTime(2026, 10, 30),
      ),
    };
    var follows = deriveFollows(
      library,
      AppSettings.defaults,
      statuses: statuses,
    );
    final king = follows.find(FollowKind.authors, 'stephen-king')!;
    expect(king.isActive, isFalse);
    expect(king.defaultOn, isFalse);
    expect(king.followed, isFalse);
    expect(king.providerId, 'wikidata:Q39829');
    expect(king.secondLine, 'Died 2099 · Series still checked');
    expect(
      follows.find(FollowKind.studios, 'pixar')!.secondLine,
      'Dissolved · Not checked',
    );
    // The row count leaves the inactive out until ticked.
    expect(follows.countLabel(FollowKind.authors), '0');
    expect(follows.followedLabel(FollowKind.authors), '0 of 1 followed');
    expect(follows.activeDefaults(FollowKind.authors), isEmpty);

    follows = deriveFollows(
      library,
      const AppSettings(
        followed: {
          FollowKind.authors: {'stephen-king'},
        },
      ),
      statuses: statuses,
    );
    expect(follows.find(FollowKind.authors, 'stephen-king')!.followed, isTrue);
    expect(follows.countLabel(FollowKind.authors), '1');
  });

  test('tagDisplayName keeps the creator text, else capitalizes the tag', () {
    expect(tagDisplayName('stephen-king', library), 'Stephen King');
    expect(tagDisplayName('jenna-ortega', library), 'Jenna Ortega');
    expect(splitCreators('Stephen King & Peter Straub'), [
      'Stephen King',
      'Peter Straub',
    ]);
  });
}
