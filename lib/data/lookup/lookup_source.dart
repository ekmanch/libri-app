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

  /// The game platforms a search can be narrowed to (Add / edit entry ›
  /// Platform picker), A to Z by name; empty from a source without games.
  Future<List<GamePlatform>> platforms() async => const [];

  /// Candidates for what the user typed among the games released on
  /// [platform] (Add / edit entry › Game search on a platform), each dated
  /// by its release there rather than its first release anywhere. Plain
  /// [search] from a source that cannot narrow by platform.
  Future<List<LookupMatch>> searchOnPlatform(
    String query,
    GamePlatform platform, {
    int limit = 10,
  }) => search(query, type: MediaType.games, limit: limit);

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

  /// Matches to take a cover from for an entry titled [title] (Add / edit
  /// entry › Pick a cover), each with a cover, the id its image is found by
  /// ([LookupMatch.coverFrom]) and the edition when the provider says.
  /// Defaults to [search] for the title.
  Future<List<LookupMatch>> coverChoices(
    String title, {
    required MediaType type,
    String? creator,
  }) => search(title, type: type, limit: 20);

  /// The image of a cover picked in [coverChoices], by its
  /// [LookupMatch.coverFrom] id, sized for the cache. Defaults to
  /// [coverUrl], for a provider whose id stands for one image.
  Future<String?> pickedCoverUrl(String id, {required MediaType type}) =>
      coverUrl(id, type: type);
}

/// A show's seasons as the lookup lists them, whether it is canceled, and
/// for an anime its kind (null for a show, or when the lookup cannot say).
typedef ShowSeasons = ({List<Season> seasons, bool canceled, EntryKind? kind});

/// One part of a series as the lookup lists it: its number in the series
/// (null when the source gives none), its title, its year and its lookup id
/// (so a part in the library is matched to it, and "+ Add" can look it up),
/// and its authors when the source names them (Wikidata does, so Choose
/// what to show can say which parts someone else wrote).
typedef SeriesPart = ({
  int? number,
  String title,
  int? year,
  String? source,
  String? creator,
});

/// A series: its name and its parts in the source's order.
typedef SeriesParts = ({String name, List<SeriesPart> parts});

/// A game platform as the lookup lists it (Add / edit entry › Platform
/// picker): the lookup's own id for it, the name the app shows and saves,
/// spelled as `normalizePlatform` spells it ("Super Nintendo", "PC"), and
/// the other names it goes by ("SNES", "Super Nintendo Entertainment
/// System"), which a search in the picker matches too.
typedef GamePlatform = ({int id, String name, List<String> aka});
