import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_format.dart';
import 'date_only_converter.dart';
import 'entry_status.dart';
import 'media_type.dart';
import 'entry_kind.dart';
import 'released.dart';
import 'season.dart';
import 'series.dart';
import 'tag_category.dart';
import 'track.dart';

part 'entry.freezed.dart';
part 'entry.g.dart';

/// One title in the library, of any type.
///
/// The field order here is the key order in `library.json`. Common fields are
/// always written, even when null, so an edit changes as few lines as
/// possible. Type-specific fields are omitted when absent.
@freezed
abstract class Entry with _$Entry {
  const Entry._();

  const factory Entry({
    required String id,
    required MediaType type,
    required String title,
    @ReleasedConverter() Released? released,
    String? creator,
    required EntryStatus status,
    int? rating,
    @Default([]) List<String> tags,

    /// Which of a tag's categories apply here, for a tag that is in more
    /// than one category of the tag list: "#clint-eastwood" as a director,
    /// an actor, or both. Keyed by tag, each a non-empty list in category
    /// order; only such tags have an entry, so the key is left out when the
    /// entry has none. A tag in one category never has an entry here. A tag
    /// in several that has none (a file edited by hand) counts in all of
    /// them.
    @JsonKey(name: 'tag_categories', includeIfNull: false)
    Map<String, List<TagCategory>>? tagCategories,
    @Default('') String note,
    @Default('') String description,
    @JsonKey(name: 'seasonal_only') @Default(false) bool seasonalOnly,
    @DateOnlyConverter() required DateTime added,

    /// The lookup id, "tmdb:movie:603", "deezer:album:302127",
    /// "openlibrary:OL45804W", or null until a match is picked in
    /// Add / edit entry › New entry: pick a match or "Look up again". Always
    /// written, like `rating`. Covers and track lists for entries without one
    /// are matched on the device and never stored here. Changing the type
    /// clears it; editing the title never does.
    String? source,
    // Games.
    @JsonKey(includeIfNull: false) String? platform,
    // Books.
    @JsonKey(includeIfNull: false) List<BookFormat>? formats,

    /// The page count, from the lookup or typed in Add / edit entry.
    @JsonKey(includeIfNull: false) int? pages,

    /// The series the entry is part of (movies, books, games and anime
    /// movies), from the lookup or typed in Add / edit entry.
    @JsonKey(includeIfNull: false) Series? series,
    // Music (album, song) and anime (series, movie).
    @JsonKey(includeIfNull: false) EntryKind? kind,
    @JsonKey(includeIfNull: false) String? album,
    @JsonKey(includeIfNull: false) List<Track>? tracks,
    // Shows and anime series: in season number order, omitted when the
    // show has none.
    @JsonKey(includeIfNull: false) List<Season>? seasons,
  }) = _Entry;

  factory Entry.fromJson(Map<String, Object?> json) => _$EntryFromJson(json);

  /// The release year. A show counts from its first season, so sorting
  /// and the decade filter place it where it began.
  int? get year => firstSeason?.released?.year ?? released?.year;

  Season? get firstSeason =>
      seasons == null || seasons!.isEmpty ? null : seasons!.first;

  /// A show with more than one season: its status comes from the seasons
  /// and its screens list them. A show with one season looks like a movie.
  bool get hasSeasonList => (seasons?.length ?? 0) > 1;

  /// A show, or an anime series (`"kind": "series"`): its seasons carry the
  /// dates and statuses, and the seasons code (Show & seasons) applies to
  /// it. An anime movie, or an anime whose kind is not known yet, is like a
  /// movie: one date, no seasons.
  bool get usesSeasons =>
      type == MediaType.shows ||
      (type == MediaType.anime && kind == EntryKind.series);

  /// Whether an entry of [type] and [kind] can belong to a series (Library ›
  /// Movie in a series): movies, books, games and anime movies. Shows and
  /// anime series use seasons instead.
  static bool typeHasSeries(MediaType type, EntryKind? kind) => switch (type) {
    MediaType.movies || MediaType.books || MediaType.games => true,
    MediaType.anime => kind != EntryKind.series,
    MediaType.shows || MediaType.music => false,
  };

  bool get canHaveSeries => typeHasSeries(type, kind);

  /// The entry with [seasons] and, when it [usesSeasons], the status they
  /// give.
  Entry withSeasons(List<Season>? seasons, {DateTime? today}) {
    final list = seasons == null || seasons.isEmpty ? null : seasons;
    return copyWith(
      seasons: list,
      status: list == null || !usesSeasons
          ? status
          : Season.showStatus(list, today ?? seasonClock()),
    );
  }

  /// A season added by the daily check, out and with no status yet.
  bool hasNewSeasonOn(DateTime today) =>
      seasons?.any((s) => s.isNewOn(today)) ?? false;

  /// The categories [tag] is picked in here, for a tag in more than one
  /// category: the entry's own pick, else [all], the tag's categories, which
  /// is also the answer for a tag in one category.
  List<TagCategory> categoriesOf(String tag, List<TagCategory> all) {
    if (all.length < 2) return all;
    final picked = tagCategories?[tag];
    if (picked == null || picked.isEmpty) return all;
    return [
      for (final c in all)
        if (picked.contains(c)) c,
    ];
  }

  /// Whether [tag] is on this entry as [category]: on it at all, and, for a
  /// tag with a pick, picked in that category. Used by the filter, which
  /// has no tag list at hand: an entry without a pick matches any category.
  bool hasTagAs(String tag, TagCategory category) {
    if (!tags.contains(tag)) return false;
    final picked = tagCategories?[tag];
    return picked == null || picked.isEmpty || picked.contains(category);
  }

  /// False only when a release date is known and still in the future.
  bool isReleasedOn(DateTime today) => released?.isReleasedOn(today) ?? true;
}
