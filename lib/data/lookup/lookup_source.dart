import '../models/entry_kind.dart';
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

  /// The provider's name for the credit under a season's episodes: "TMDB".
  String get name => id;

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
  /// whether the show is canceled, and for an anime whether it is a series
  /// or a movie, for the daily check. Null from a source without shows.
  Future<ShowSeasons?> seasons(String source) async => null;

  /// The id the seasons' episodes are read under: [source] itself, or for an
  /// anime series the TMDB show it was matched to (Show & seasons › Anime with
  /// seasons (Frieren)), so the episodes come from there.
  Future<String> seasonSource(String source) async => source;

  /// The episodes of [season] of the show with [source], in number order, for
  /// the season screen (Show & seasons › Season episodes (all out) and Season
  /// episodes (airing weekly)); empty when the show has no such season. Null
  /// from a source without shows. Never asked by the daily check.
  Future<List<EpisodeInfo>?> seasonEpisodes(String source, int season) async =>
      null;

  /// The series the title with [source] belongs to, with every part in the
  /// series' own order (Library › Movie in a series; All volumes in a series),
  /// or null when the provider knows no series for it. [name] is the series
  /// name the entry carries, for a provider that lists parts by name (Open
  /// Library's manga volumes).
  Future<SeriesParts?> seriesParts(String source, {String? name}) async => null;

  /// A cover image for an entry with [source], sized for the cache, or
  /// null when the provider has none.
  Future<String?> coverUrl(String source, {required MediaType type});
}

/// A show's seasons as the lookup lists them, whether it is canceled, and
/// for an anime its kind (null for a show, or when the lookup cannot say).
typedef ShowSeasons = ({List<Season> seasons, bool canceled, EntryKind? kind});

/// One part of a series as the lookup lists it: its number in the series
/// (null when the source gives none), its title, its year and its lookup id
/// (so a part in the library is matched to it, and "+ Add" can look it up).
typedef SeriesPart = ({int? number, String title, int? year, String? source});

/// A series: its name and its parts in the source's order.
typedef SeriesParts = ({String name, List<SeriesPart> parts});
