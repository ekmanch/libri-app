import 'package:freezed_annotation/freezed_annotation.dart';

import 'entry_status.dart';
import 'released.dart';

part 'season.freezed.dart';
part 'season.g.dart';

/// One season of a show entry. [season] is the season's number, unique
/// within the show; seasons are kept in number order. [status] is null when
/// not set. A show's own status comes from its seasons ([showStatus]).
///
/// [fresh] (`"new"` in the file) is true on a season the daily check added
/// after the show was in the library, until the season gets a status.
/// [manual] is true on a season added in the form (or kept when the lookup
/// dropped it), which the daily check never removes. Both are written only
/// while true.
@freezed
abstract class Season with _$Season {
  const Season._();

  const factory Season({
    required int season,
    @ReleasedConverter() Released? released,
    EntryStatus? status,
    @JsonKey(name: 'new', includeIfNull: false) bool? fresh,
    @JsonKey(includeIfNull: false) bool? manual,
  }) = _Season;

  factory Season.fromJson(Map<String, Object?> json) => _$SeasonFromJson(json);

  /// Out on [today]. A season without a date counts as out, like an entry.
  bool isReleasedOn(DateTime today) => released?.isReleasedOn(today) ?? true;

  /// Shown with a "New" label, and the show with a "New season" badge: a
  /// season the daily check added, once it is out, until it has a status.
  bool isNewOn(DateTime today) =>
      fresh == true && status == null && isReleasedOn(today);

  bool get isManual => manual == true;

  /// The seasons of [fetched] that belong in the library: every numbered
  /// season with a date (an announced one shows "Coming 2027"), in number
  /// order, without status or marks. Specials (season 0) and seasons the
  /// lookup has no date for yet are left out.
  static List<Season> listable(Iterable<Season> fetched) => [
    for (final s in [...fetched]..sort((a, b) => a.season.compareTo(b.season)))
      if (s.season > 0 && s.released != null)
        Season(season: s.season, released: s.released),
  ];

  /// A show's status from its seasons. A show with one season has that
  /// season's status (Want while not set). With more, only seasons that
  /// are out and have a status count: any In progress is In progress; else
  /// any DNF is DNF; all Done is Done; Done and Want together are In
  /// progress; all Want, or nothing set, is Want.
  static EntryStatus showStatus(List<Season> seasons, DateTime today) {
    if (seasons.length == 1) return seasons.single.status ?? EntryStatus.want;
    final set = {
      for (final s in seasons)
        if (s.status != null && s.isReleasedOn(today)) s.status!,
    };
    if (set.isEmpty) return EntryStatus.want;
    if (set.contains(EntryStatus.inProgress)) return EntryStatus.inProgress;
    if (set.contains(EntryStatus.dnf)) return EntryStatus.dnf;
    if (set.length == 1) return set.single;
    return EntryStatus.inProgress;
  }
}

/// Today for the season rules, so the tests can fix the day.
DateTime Function() seasonClock = DateTime.now;
