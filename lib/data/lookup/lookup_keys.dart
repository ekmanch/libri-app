/// The API keys this build was made with, from `secrets.json` through
/// `flutter run --dart-define-from-file=secrets.json`. The file is never
/// committed; `secrets.example.json` lists the names. A missing key leaves
/// that provider "not set up": nothing is asked, nothing crashes.
abstract final class LookupKeys {
  /// TMDB's API read access token (the long "v4" one), sent as a Bearer.
  static const tmdbReadToken = String.fromEnvironment('TMDB_READ_TOKEN');

  /// A Twitch application's client id and secret, for IGDB.
  static const igdbClientId = String.fromEnvironment('IGDB_CLIENT_ID');
  static const igdbClientSecret = String.fromEnvironment('IGDB_CLIENT_SECRET');

  /// Optional: Google Books, read by id only for the books it found while
  /// it was a search source, works without one, with a smaller quota.
  static const googleBooksKey = String.fromEnvironment('GOOGLE_BOOKS_KEY');
}
