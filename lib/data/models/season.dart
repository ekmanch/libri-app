import 'package:freezed_annotation/freezed_annotation.dart';

import 'entry_status.dart';
import 'released.dart';

part 'season.freezed.dart';
part 'season.g.dart';

/// One season of a show entry. [season] is the season's number, unique
/// within the show; seasons are kept in number order. [status] is null when
/// not set, and never changes the show's own status.
///
/// [fresh] (`"new"` in the file) is true on a season the daily check added
/// after the show was in the library, until the season gets a status. It is
/// written only while true.
@freezed
abstract class Season with _$Season {
  const Season._();

  const factory Season({
    required int season,
    @ReleasedConverter() Released? released,
    EntryStatus? status,
    @JsonKey(name: 'new', includeIfNull: false) bool? fresh,
  }) = _Season;

  factory Season.fromJson(Map<String, Object?> json) => _$SeasonFromJson(json);

  /// Shown with a "New" label, and the show with a "New season" badge.
  bool get isNew => fresh == true && status == null;
}
