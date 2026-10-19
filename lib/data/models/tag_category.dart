import 'package:json_annotation/json_annotation.dart';

import 'media_type.dart';

/// Tag categories, in display order. The JSON keys of the `tags` map are
/// the display names.
enum TagCategory {
  /// Genres for movies, shows, books and anime.
  @JsonValue('Genres')
  genre,
  @JsonValue('Game genres')
  gameGenre,
  @JsonValue('Music genres')
  musicGenre,
  @JsonValue('Mood')
  mood,
  @JsonValue('Season')
  season,

  /// The three creator groups. A tag's group is the person's or studio's
  /// main role, not the entry's type: #stephen-king is an author even on a
  /// movie, and Directors also holds showrunners and anime directors.
  @JsonValue('Authors')
  authors,
  @JsonValue('Directors')
  directors,

  /// The cast of movies and shows; Add / edit entry suggests the top three
  /// billed.
  @JsonValue('Actors')
  actors,
  @JsonValue('Studios')
  studios,
  @JsonValue('Animation style')
  animationStyle,
  @JsonValue('Other')
  other;

  /// Whether the tag picker (Add / edit entry › Tag picker) lists this category
  /// for an entry of [type] before anything is typed: game genres only for
  /// games, music genres only for music, actors only for movies and shows. A
  /// search finds every tag.
  bool offeredFor(MediaType type) => switch (this) {
    gameGenre => type == MediaType.games,
    musicGenre => type == MediaType.music,
    actors => type == MediaType.movies || type == MediaType.shows,
    _ => true,
  };

  /// The category a new tag starts on in Add / edit entry › New tag: confirm
  /// and pick a category.
  static TagCategory defaultFor(MediaType type) => switch (type) {
    MediaType.games => gameGenre,
    MediaType.music => musicGenre,
    _ => genre,
  };

  /// The group a tag made from an entry's creator field starts on: the
  /// author of a book, the director (or showrunner) of a movie or show, the
  /// studio of a game or an anime. Music has none: an artist is not a tag.
  static TagCategory? creatorGroupFor(MediaType type) => switch (type) {
    MediaType.books => authors,
    MediaType.movies || MediaType.shows => directors,
    MediaType.games || MediaType.anime => studios,
    MediaType.music => null,
  };

  /// Whether this is one of the creator groups (the groups a creator
  /// field's tag can land in; Actors is filled from the cast instead).
  bool get isCreatorGroup =>
      this == authors || this == directors || this == studios;

  /// Whether the tags are people, named first name first (#kate-siegel).
  bool get isPeopleGroup =>
      this == authors || this == directors || this == actors;
}
