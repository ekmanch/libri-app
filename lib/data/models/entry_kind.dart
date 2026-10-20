/// What kind of entry a music or anime entry is: an album or a single song;
/// an anime series (seasons, like a show) or an anime movie (one date, like
/// a movie). Other types have no kind. JSON uses the enum names.
enum EntryKind {
  album,
  song,
  series,
  movie;

  /// The kinds of a music entry.
  static const musicKinds = [album, song];

  /// The kinds of an anime entry.
  static const animeKinds = [series, movie];
}
