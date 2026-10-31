import '../data/models/entry_status.dart';
import '../data/models/media_type.dart';
import '../data/models/entry_kind.dart';
import '../data/lookup/movie_dates.dart';
import '../data/models/released.dart';
import '../data/models/tag_category.dart';

/// UI words for the enums. American spelling, sentence case.
extension EntryStatusLabel on EntryStatus {
  String get label => switch (this) {
    EntryStatus.want => 'Want',
    EntryStatus.inProgress => 'In progress',
    EntryStatus.done => 'Done',
    EntryStatus.dnf => 'DNF',
  };

  /// Mid-sentence form: "want", "in progress", "done", "DNF".
  String get lowerLabel =>
      this == EntryStatus.dnf ? label : label.toLowerCase();

  /// The word where the type is known (Library › "Status words"): In
  /// progress reads "Reading" for books (manga too), "Watching" for shows,
  /// anime and a show's seasons, "Playing" for games. With no [type], where
  /// types are mixed, it stays [label]. library.json keeps in_progress; the
  /// desktop app shows the same words.
  String labelFor(MediaType? type) => this != EntryStatus.inProgress
      ? label
      : switch (type) {
          MediaType.books => 'Reading',
          MediaType.shows || MediaType.anime || MediaType.movies => 'Watching',
          MediaType.games => 'Playing',
          MediaType.music || null => label,
        };

  /// Mid-sentence [labelFor]: "reading", "want", "DNF".
  String lowerLabelFor(MediaType? type) =>
      this == EntryStatus.dnf ? label : labelFor(type).toLowerCase();
}

/// The type that words a season's status: seasons belong to shows and
/// anime, and both say "Watching".
const seasonsType = MediaType.shows;

extension MediaTypeLabel on MediaType {
  /// Plural, for headings and chips: "Movies".
  String get label => switch (this) {
    MediaType.movies => 'Movies',
    MediaType.shows => 'Shows',
    MediaType.books => 'Books',
    MediaType.games => 'Games',
    MediaType.music => 'Music',
    MediaType.anime => 'Anime',
  };

  /// Singular, for one entry: "Movie", "Album" is handled by the caller.
  String get singular => switch (this) {
    MediaType.movies => 'Movie',
    MediaType.shows => 'Show',
    MediaType.books => 'Book',
    MediaType.games => 'Game',
    MediaType.music => 'Music',
    MediaType.anime => 'Anime',
  };
}

/// "7 movies", "1 book", "3 anime". Music lists use [musicCountLabel]; in
/// mixed contexts it falls back to "entries".
String countLabel(MediaType type, int count) =>
    '$count ${countNoun(type, count)}';

/// The noun of [countLabel]: "movie", "movies".
String countNoun(MediaType type, int count) {
  final (one, many) = switch (type) {
    MediaType.movies => ('movie', 'movies'),
    MediaType.shows => ('show', 'shows'),
    MediaType.books => ('book', 'books'),
    MediaType.games => ('game', 'games'),
    MediaType.music => ('entry', 'entries'),
    MediaType.anime => ('anime', 'anime'),
  };
  return count == 1 ? one : many;
}

extension EntryKindLabel on EntryKind {
  /// For the filter sheet's Kind chips: "Albums", "Songs"; an anime's kind
  /// in Add / edit entry: "Series", "Movies".
  String get label => switch (this) {
    EntryKind.album => 'Albums',
    EntryKind.song => 'Songs',
    EntryKind.series => 'Series',
    EntryKind.movie => 'Movies',
  };

  /// Mid-sentence: "albums", "songs".
  String get plural => label.toLowerCase();
}

extension TagCategoryLabel on TagCategory {
  String get label => switch (this) {
    TagCategory.genre => 'Genres',
    TagCategory.gameGenre => 'Game genres',
    TagCategory.musicGenre => 'Music genres',
    TagCategory.mood => 'Mood',
    TagCategory.season => 'Season',
    TagCategory.languages => 'Languages',
    TagCategory.authors => 'Authors',
    TagCategory.directors => 'Directors',
    TagCategory.actors => 'Actors',
    TagCategory.studios => 'Studios',
    TagCategory.streaming => 'Streaming',
    TagCategory.animationStyle => 'Animation style',
    TagCategory.other => 'Other',
  };

  /// The category as a role after a tag that is in more than one category:
  /// "#clint-eastwood · Actor", "#sports · Game genre".
  String get roleLabel => switch (this) {
    TagCategory.genre => 'Genre',
    TagCategory.gameGenre => 'Game genre',
    TagCategory.musicGenre => 'Music genre',
    TagCategory.mood => 'Mood',
    TagCategory.season => 'Season',
    TagCategory.languages => 'Language',
    TagCategory.authors => 'Author',
    TagCategory.directors => 'Director',
    TagCategory.actors => 'Actor',
    TagCategory.studios => 'Studio',
    TagCategory.streaming => 'Streaming',
    TagCategory.animationStyle => 'Animation style',
    TagCategory.other => 'Other',
  };
}

/// "#clint-eastwood · Director, Actor": a tag with the roles it has here.
/// With no [categories] (a tag in one category) just "#tag".
String tagLabel(String tag, [Iterable<TagCategory> categories = const []]) {
  final roles = categories.map((c) => c.roleLabel).join(', ');
  return roles.isEmpty ? '#$tag' : '#$tag · $roles';
}

/// The label of the one `creator` field, by type (DESIGN.md section 8).
String creatorLabel(MediaType type) => switch (type) {
  MediaType.movies => 'Director',
  MediaType.shows => 'Creator',
  MediaType.books => 'Author',
  MediaType.games => 'Studio',
  MediaType.music => 'Artist',
  MediaType.anime => 'Studio',
};

const monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The Released field (Add / edit entry): "2013", "Jun 2013" or "Jun 14, 2013".
String releasedLabel(Released released) {
  final month = released.month, day = released.day;
  if (month == null) return '${released.year}';
  final name = monthAbbreviations[month - 1];
  if (day == null) return '$name ${released.year}';
  return '$name $day, ${released.year}';
}

/// The line under the picker's title (Add / edit entry › Released: wheel
/// picker): "Year only: 2013", "June 2013" or "June 14, 2013".
String releasedLongLabel(Released released) {
  final month = released.month, day = released.day;
  if (month == null) return 'Year only: ${released.year}';
  final name = monthNames[month - 1];
  if (day == null) return '$name ${released.year}';
  return '$name $day, ${released.year}';
}

/// "8 / 10", or "Not rated".
String ratingLabel(int? rating) =>
    rating == null ? 'Not rated' : '$rating / 10';

/// "3 albums, 2 songs", "1 song". Zero counts are left out; "0 albums" is
/// returned only when both are zero.
String albumsAndSongsLabel(int albums, int songs) {
  final parts = [
    if (albums > 0) '$albums ${albums == 1 ? 'album' : 'albums'}',
    if (songs > 0) '$songs ${songs == 1 ? 'song' : 'songs'}',
  ];
  return parts.isEmpty ? '0 albums' : parts.join(', ');
}

/// The count line of the music list (Library › Music: artists, text view): "17
/// artists, 13 albums, 5 songs".
String musicCountLabel({
  required int artists,
  required int albums,
  required int songs,
}) =>
    '$artists ${artists == 1 ? 'artist' : 'artists'}, '
    '$albums ${albums == 1 ? 'album' : 'albums'}, '
    '$songs ${songs == 1 ? 'song' : 'songs'}';

/// What a plan row says when the entry was already done when it was added:
/// a rewatch, a reread, a replay or a relisten.
String repeatLabel(MediaType type) => switch (type) {
  MediaType.books => 'Reread',
  MediaType.games => 'Replay',
  MediaType.music => 'Relisten',
  MediaType.movies || MediaType.shows || MediaType.anime => 'Rewatch',
};

/// "Nov 10" (with the year when it is not this year: "Nov 10, 2027"), "Jan
/// 2027" for a month, "2027" for a year.
String comingSoonLabel(Released released, {required DateTime today}) {
  final month = released.month, day = released.day;
  if (month == null) return '${released.year}';
  final name = monthAbbreviations[month - 1];
  if (day == null) return '$name ${released.year}';
  final date = '$name $day';
  return released.year == today.year ? date : '$date, ${released.year}';
}

/// "In cinemas Dec 18 · Digital Feb 2027" for a movie whose dates by kind
/// are both known (Settings › Movies › Release dates set to Both; Library ›
/// Entry details and Coming soon: add an upcoming entry), else null.
String? bothDatesLabel(MovieDates? dates, {required DateTime today}) {
  final cinema = dates?.cinema, digital = dates?.digital;
  if (cinema == null || digital == null) return null;
  return 'In cinemas ${comingSoonLabel(cinema, today: today)} · '
      'Digital ${comingSoonLabel(digital, today: today)}';
}
