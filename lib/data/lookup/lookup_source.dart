import '../models/media_type.dart';
import '../models/season.dart';
import 'episode_info.dart';
import 'lookup_match.dart';

/// One provider of matches: TMDB, AniList, Open Library, IGDB, Deezer, or
/// the fake. Every method throws [LookupException] on failure and never
/// returns a match of a type outside [types].
abstract class LookupSource {
  /// The provider part of the ids it issues: "tmdb" for "tmdb:movie:603".
  String get id;

  Set<MediaType> get types;

  /// False when a needed key is missing from this build; then nothing is
  /// asked and the screen says the lookup is not set up.
  bool get isConfigured => true;

  /// Whether [source] ("tmdb:movie:603") is one of this source's ids. The
  /// fake answers for every provider.
  bool issued(String source) => LookupMatch.providerOf(source) == id;

  /// Candidates for what the user typed (Add / edit entry › New entry: pick a
  /// match), in the provider's order.
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  });

  /// The one best hit for an entry that was never looked up, so its cover
  /// can be found: same title, and the same year when one is known.
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  });

  /// The match with what the search left out (a director, a release date,
  /// genres), fetched once when it is picked. Defaults to the match itself.
  Future<LookupMatch> details(LookupMatch match) async => match;

  /// The seasons of the show with [source], as in [LookupMatch.seasons],
  /// and whether the show is canceled, for the daily check. Null from a
  /// source without shows.
  Future<ShowSeasons?> seasons(String source) async => null;

  /// The episodes of [season] of the show with [source], in number order, for
  /// the season screen (Show & seasons › Season episodes (all out) and Season
  /// episodes (airing weekly)); empty when the show has no such season. Null
  /// from a source without shows. Never asked by the daily check.
  Future<List<EpisodeInfo>?> seasonEpisodes(String source, int season) async =>
      null;

  /// A cover image for an entry with [source], sized for the cache, or
  /// null when the provider has none.
  Future<String?> coverUrl(String source, {required MediaType type});
}

/// A show's seasons as the lookup lists them, and whether it is canceled.
typedef ShowSeasons = ({List<Season> seasons, bool canceled});
