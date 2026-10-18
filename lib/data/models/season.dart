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

  /// How far ahead of its release a season is added: a heads-up that it is
  /// on the way.
  static const headsUpDays = 14;

  /// Whether a fetched season belongs in the library on [today]: it has a
  /// release date, and that date is at most [headsUpDays] away. A partial
  /// date counts from the day its period ends, as for entries.
  bool isListableOn(DateTime today) {
    final released = this.released;
    if (released == null) return false;
    final limit = DateTime(today.year, today.month, today.day + headsUpDays);
    return !released.availableFrom.isAfter(limit);
  }

  /// The seasons of [fetched] that belong in the library on [today], in
  /// number order, without status or New mark.
  static List<Season> listable(Iterable<Season> fetched, DateTime today) => [
    for (final s in [...fetched]..sort((a, b) => a.season.compareTo(b.season)))
      if (s.season > 0 && s.isListableOn(today))
        Season(season: s.season, released: s.released),
  ];
}
