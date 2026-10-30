import 'media_type.dart';
import 'tag_category.dart';

/// The seven kinds of follow Settings › Upcoming releases lists, in the
/// order of its rows. Every follow is derived from the library (DESIGN.md
/// 10c): shows and anime series with seasons, series and collections,
/// then the creators behind the entries, by their tags or, for artists, by
/// the creator field of albums and songs.
enum FollowKind {
  shows('shows', 'Shows and anime', 'New seasons', 'seasons'),
  series('series', 'Series and collections', 'Next parts', 'parts'),
  authors('authors', 'Authors', 'New books', 'books'),
  artists('artists', 'Artists', 'New albums', 'albums'),
  directors(
    'directors',
    'Directors',
    'New movies and shows',
    'movies and shows',
  ),
  studios('studios', 'Studios', 'New movies and games', 'movies and games'),
  actors('actors', 'Actors', 'New movies and shows', 'movies and shows');

  const FollowKind(this.key, this.label, this.what, this.noun);

  /// The key in `settings.json`.
  final String key;

  /// The row's name ("Shows and anime").
  final String label;

  /// What is checked, under the name ("New seasons").
  final String what;

  /// What the followed group heading names: "Followed for new books".
  final String noun;

  /// Whether a follow of this kind is on until the owner unticks it. Actors
  /// are off until ticked, since a library tags far more actors than anyone
  /// wants to follow (the canvas's "2 of 221").
  bool get defaultOn => this != actors;

  /// Whether the follows are people or studios (a creator), rather than
  /// the library's shows and series.
  bool get isCreator => this != shows && this != series;

  /// The tag category the creators of this kind come from, or null for
  /// shows, series and artists (whose names are not tags).
  TagCategory? get category => switch (this) {
    authors => TagCategory.authors,
    directors => TagCategory.directors,
    studios => TagCategory.studios,
    actors => TagCategory.actors,
    _ => null,
  };

  /// "Search authors", "Search shows and anime".
  String get searchHint => 'Search ${label.toLowerCase()}';

  /// The types a creator's new releases are of, for the found releases.
  Set<MediaType> get releaseTypes => switch (this) {
    shows => const {MediaType.shows, MediaType.anime},
    series => const {MediaType.movies, MediaType.books, MediaType.games},
    authors => const {MediaType.books},
    artists => const {MediaType.music},
    directors || actors => const {MediaType.movies, MediaType.shows},
    studios => const {MediaType.movies, MediaType.games},
  };

  static FollowKind? byKey(String? key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}
