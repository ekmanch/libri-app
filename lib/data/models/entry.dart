import 'package:freezed_annotation/freezed_annotation.dart';

import 'book_format.dart';
import 'date_only_converter.dart';
import 'entry_status.dart';
import 'media_type.dart';
import 'music_kind.dart';
import 'released.dart';
import 'season.dart';
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
    @Default('') String note,
    @Default('') String description,
    @JsonKey(name: 'seasonal_only') @Default(false) bool seasonalOnly,
    @DateOnlyConverter() required DateTime added,

    /// The lookup id, "tmdb:movie:603", "deezer:album:302127",
    /// "openlibrary:OL45804W", or null until a match is picked in A13 or
    /// "Look up again". Always written, like `rating`. Covers and track lists
    /// for entries without one are matched on the device and never stored
    /// here. Changing the type clears it; editing the title never does.
    String? source,
    // Games.
    @JsonKey(includeIfNull: false) String? platform,
    // Books.
    @JsonKey(includeIfNull: false) List<BookFormat>? formats,
    // Music.
    @JsonKey(includeIfNull: false) MusicKind? kind,
    @JsonKey(includeIfNull: false) String? album,
    @JsonKey(includeIfNull: false) List<Track>? tracks,
    // Shows: in season number order, omitted when the show has none.
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

  /// The entry with [seasons] and, for a show, the status they give.
  Entry withSeasons(List<Season>? seasons, {DateTime? today}) {
    final list = seasons == null || seasons.isEmpty ? null : seasons;
    return copyWith(
      seasons: list,
      status: list == null || type != MediaType.shows
          ? status
          : Season.showStatus(list, today ?? seasonClock()),
    );
  }

  /// A season added by the daily check, out and with no status yet.
  bool hasNewSeasonOn(DateTime today) =>
      seasons?.any((s) => s.isNewOn(today)) ?? false;

  /// False only when a release date is known and still in the future.
  bool isReleasedOn(DateTime today) => released?.isReleasedOn(today) ?? true;
}
