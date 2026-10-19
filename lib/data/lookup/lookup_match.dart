import 'package:flutter/foundation.dart';

import '../models/media_type.dart';
import '../models/released.dart';
import '../models/season.dart';

/// One candidate from a title lookup (A13), or the match a cover was
/// resolved from. Filled by the sources in `lib/data/lookup/`; the fake in
/// `lib/dev/fake_lookup.dart` serves a fixed catalog for tests and demos.
@immutable
class LookupMatch {
  const LookupMatch({
    required this.type,
    required this.title,
    required this.source,
    this.released,
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
    this.coverUrl,
    this.largeCoverUrl,
  });

  final MediaType type;
  final String title;

  /// The lookup id, as stored on the entry: "tmdb:movie:603",
  /// "deezer:album:302127", "openlibrary:OL45804W".
  final String source;

  final Released? released;
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
    String? coverUrl,
    String? largeCoverUrl,
  }) => LookupMatch(
    type: type,
    title: title,
    source: source,
    released: released ?? this.released,
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
      other.coverUrl == coverUrl &&
      other.largeCoverUrl == largeCoverUrl;

  @override
  int get hashCode => Object.hash(type, title, source, released, coverUrl);

  @override
  String toString() => 'LookupMatch($source, $title)';
}
