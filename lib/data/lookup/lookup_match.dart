import 'package:flutter/foundation.dart';

import '../models/entry_kind.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../models/season.dart';
import '../models/series.dart';

/// One candidate from a title lookup (Add / edit entry › New entry: pick a
/// match), or the match a cover was resolved from. Filled by the sources in
/// `lib/data/lookup/`; the fake in `lib/dev/fake_lookup.dart` serves a fixed
/// catalog for tests and demos.
@immutable
class LookupMatch {
  const LookupMatch({
    required this.type,
    required this.title,
    required this.source,
    this.released,
    this.releasedFromEbook = false,
    this.creator,
    this.description = '',
    this.album,
    this.albumSource,
    this.platforms = const [],
    this.companies = const [],
    this.cast = const [],
    this.tags = const [],
    this.seasons = const [],
    this.pages,
    this.kind,
    this.series,
    this.language,
    this.coverUrl,
    this.largeCoverUrl,
  });

  final MediaType type;
  final String title;

  /// The lookup id, as stored on the entry: "tmdb:movie:603",
  /// "deezer:album:302127", "openlibrary:OL45804W".
  final String source;

  final Released? released;

  /// For a book: [released] is the year of the Apple Books ebook, with no
  /// Open Library year to go by, so it may be a reprint's. The add form
  /// says so under the date; it is never stored.
  final bool releasedFromEbook;

  final String? creator;
  final String description;

  /// For a song: the album it is on, and that album's lookup id.
  final String? album;
  final String? albumSource;

  /// For a game: the platforms it is out on, as the lookup lists them.
  final List<String> platforms;

  /// The companies behind it, as the lookup names them: production
  /// companies for a movie or show, studios for an anime, developers for a
  /// game. The form reads the studio's tag from them (#pixar).
  final List<String> companies;

  /// The top-billed cast of a movie or show, in billing order, as the
  /// lookup names them. The form suggests the first three as actor tags.
  final List<String> cast;

  /// Tag names the lookup suggests (genres, themes). The form matches them
  /// to the library's tags and offers the rest as new ones.
  final List<String> tags;

  /// For a show: every season the lookup lists with its release date,
  /// specials left out. The form keeps those [Season.listable] today.
  final List<Season> seasons;

  /// For a book: its page count, when the lookup knows it.
  final int? pages;

  /// For an anime: a series (seasons, like a show) or a movie, as the
  /// lookup's format says (AniList: TV, TV short, ONA and OVA are series;
  /// a movie, a special or a music video is a movie); null when it does
  /// not say. Music tells albums from songs by [album] instead.
  final EntryKind? kind;

  /// The series the title belongs to and its number in it, when the lookup
  /// knows (TMDB collections, IGDB collections, Wikidata for books, or a
  /// "Vol. 43" in a manga's title).
  final Series? series;

  /// The language the work is in, as a code ("ja", "jpn", "ja-JP"), when the
  /// lookup says: TMDB's original language, the one language of an Open
  /// Library work, a game's only audio language on IGDB, an anime's country
  /// of origin on AniList. The form suggests its tag (see `languages.dart`).
  final String? language;

  /// A cover or artwork image, sized for a list row.
  final String? coverUrl;

  /// The same image at the size the cache keeps (a details header on a 3x
  /// screen), when the provider offers one; else [coverUrl] serves.
  final String? largeCoverUrl;

  String? get cacheCoverUrl => largeCoverUrl ?? coverUrl;

  /// The provider part of a lookup id: "tmdb" for "tmdb:movie:603".
  static String providerOf(String source) =>
      source.substring(0, source.indexOf(':').clamp(0, source.length));

  LookupMatch copyWith({
    Released? released,
    bool? releasedFromEbook,
    String? creator,
    String? description,
    String? album,
    String? albumSource,
    List<String>? platforms,
    List<String>? companies,
    List<String>? cast,
    List<String>? tags,
    List<Season>? seasons,
    int? pages,
    EntryKind? kind,
    Series? series,
    String? language,
    String? coverUrl,
    String? largeCoverUrl,
  }) => LookupMatch(
    type: type,
    title: title,
    source: source,
    released: released ?? this.released,
    releasedFromEbook: releasedFromEbook ?? this.releasedFromEbook,
    creator: creator ?? this.creator,
    description: description ?? this.description,
    album: album ?? this.album,
    albumSource: albumSource ?? this.albumSource,
    platforms: platforms ?? this.platforms,
    companies: companies ?? this.companies,
    cast: cast ?? this.cast,
    tags: tags ?? this.tags,
    seasons: seasons ?? this.seasons,
    pages: pages ?? this.pages,
    kind: kind ?? this.kind,
    series: series ?? this.series,
    language: language ?? this.language,
    coverUrl: coverUrl ?? this.coverUrl,
    largeCoverUrl: largeCoverUrl ?? this.largeCoverUrl,
  );

  @override
  bool operator ==(Object other) =>
      other is LookupMatch &&
      other.type == type &&
      other.title == title &&
      other.source == source &&
      other.released == released &&
      other.releasedFromEbook == releasedFromEbook &&
      other.creator == creator &&
      other.description == description &&
      other.album == album &&
      other.albumSource == albumSource &&
      listEquals(other.platforms, platforms) &&
      listEquals(other.companies, companies) &&
      listEquals(other.cast, cast) &&
      listEquals(other.tags, tags) &&
      listEquals(other.seasons, seasons) &&
      other.pages == pages &&
      other.kind == kind &&
      other.series == series &&
      other.language == language &&
      other.coverUrl == coverUrl &&
      other.largeCoverUrl == largeCoverUrl;

  @override
  int get hashCode => Object.hash(type, title, source, released, coverUrl);

  @override
  String toString() => 'LookupMatch($source, $title)';
}
