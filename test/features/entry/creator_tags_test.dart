import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/features/entry/creator_tags.dart';

void main() {
  test('a book suggests its author, in Authors', () {
    expect(creatorTags(type: MediaType.books, creator: 'Ursula K. Le Guin'), [
      (tag: 'ursula-k-le-guin', category: TagCategory.authors),
    ]);
  });

  test('a movie or show suggests its director, in Directors', () {
    expect(creatorTags(type: MediaType.movies, creator: 'Robert Eggers'), [
      (tag: 'robert-eggers', category: TagCategory.directors),
    ]);
    expect(creatorTags(type: MediaType.shows, creator: 'Mike Flanagan'), [
      (tag: 'mike-flanagan', category: TagCategory.directors),
    ]);
  });

  test('a game or anime suggests its studio, in Studios', () {
    expect(creatorTags(type: MediaType.games, creator: 'Naughty Dog'), [
      (tag: 'naughty-dog', category: TagCategory.studios),
    ]);
    expect(creatorTags(type: MediaType.anime, creator: 'Madhouse'), [
      (tag: 'madhouse', category: TagCategory.studios),
    ]);
  });

  test('music suggests nothing: an artist is not a tag', () {
    expect(
      creatorTags(type: MediaType.music, creator: 'Alice in Chains'),
      isEmpty,
    );
  });

  test('several names give several tags; accents fold', () {
    expect(
      creatorTags(
        type: MediaType.books,
        creator: 'Stephen King & Peter Straub',
      ).map((t) => t.tag),
      ['stephen-king', 'peter-straub'],
    );
    expect(
      creatorTags(
        type: MediaType.shows,
        creator: 'Craig Mazin, Neil Druckmann',
      ).map((t) => t.tag),
      ['craig-mazin', 'neil-druckmann'],
    );
    expect(
      creatorTags(type: MediaType.books, creator: 'Jo Nesbø').single.tag,
      'jo-nesbo',
    );
    expect(creatorTags(type: MediaType.books, creator: '  '), isEmpty);
    expect(creatorTags(type: MediaType.books, creator: null), isEmpty);
  });

  test('a Pixar, Disney, DreamWorks or Ghibli film suggests the studio', () {
    expect(
      creatorTags(
        type: MediaType.movies,
        creator: 'Pete Docter',
        companies: ['Pixar', 'Walt Disney Pictures'],
      ),
      [(tag: 'pixar', category: TagCategory.studios)],
    );
    expect(
      creatorTags(
        type: MediaType.movies,
        creator: 'Chris Buck, Jennifer Lee',
        companies: ['Walt Disney Animation Studios', 'Walt Disney Pictures'],
      ).single.tag,
      'disney',
    );
    expect(
      creatorTags(
        type: MediaType.movies,
        creator: 'Andrew Adamson',
        companies: ['DreamWorks Animation'],
      ).single.tag,
      'dreamworks',
    );
    expect(
      creatorTags(
        type: MediaType.movies,
        creator: 'Hayao Miyazaki',
        companies: ['Studio Ghibli'],
      ).single.tag,
      'studio-ghibli',
    );
  });

  test('a live-action Disney film keeps its director', () {
    expect(
      creatorTags(
        type: MediaType.movies,
        creator: 'Gore Verbinski',
        companies: ['Walt Disney Pictures', 'Jerry Bruckheimer Films'],
      ).single.tag,
      'gore-verbinski',
    );
  });

  test('Miyazaki typed by hand still means Studio Ghibli', () {
    expect(creatorTags(type: MediaType.movies, creator: 'Hayao Miyazaki'), [
      (tag: 'studio-ghibli', category: TagCategory.studios),
    ]);
    expect(
      creatorTags(type: MediaType.anime, creator: 'Studio Ghibli').single.tag,
      'studio-ghibli',
    );
  });

  group('actor tags from the billed cast', () {
    test('a movie or show gets the top three, in Actors, in billing order', () {
      const cast = ['Kate Siegel', 'Zach Gilford', 'Hamish Linklater', 'Extra'];
      expect(actorTags(type: MediaType.movies, cast: cast), [
        (tag: 'kate-siegel', category: TagCategory.actors),
        (tag: 'zach-gilford', category: TagCategory.actors),
        (tag: 'hamish-linklater', category: TagCategory.actors),
      ]);
      expect(actorTags(type: MediaType.shows, cast: cast).length, 3);
    });

    test('accents fold and duplicates drop; fewer than three stay fewer', () {
      expect(
        actorTags(
          type: MediaType.movies,
          cast: ['Timothée Chalamet', 'Timothee Chalamet', 'Zendaya'],
        ),
        [
          (tag: 'timothee-chalamet', category: TagCategory.actors),
          (tag: 'zendaya', category: TagCategory.actors),
        ],
      );
    });

    test('other types get none, whatever the lookup sent', () {
      for (final type in [
        MediaType.books,
        MediaType.games,
        MediaType.music,
        MediaType.anime,
      ]) {
        expect(actorTags(type: type, cast: ['Kate Siegel']), isEmpty);
      }
    });
  });

  test('the lookup\'s language suggests its tag, in Languages', () {
    expect(languageTags(type: MediaType.movies, language: 'ja'), [
      (tag: 'japanese', category: TagCategory.languages),
    ]);
    expect(languageTags(type: MediaType.books, language: 'swe'), [
      (tag: 'swedish', category: TagCategory.languages),
    ]);
    // English nearly everything is in; Japanese nearly every anime is in.
    expect(languageTags(type: MediaType.movies, language: 'en'), isEmpty);
    expect(languageTags(type: MediaType.anime, language: 'ja'), isEmpty);
    expect(languageTags(type: MediaType.anime, language: 'ko'), [
      (tag: 'korean', category: TagCategory.languages),
    ]);
    expect(languageTags(type: MediaType.games, language: null), isEmpty);
    expect(languageTags(type: MediaType.games, language: 'xx'), isEmpty);
  });
}
