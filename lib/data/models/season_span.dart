import 'package:freezed_annotation/freezed_annotation.dart';

import 'released.dart';

part 'season_span.freezed.dart';
part 'season_span.g.dart';

/// One season as a lookup splits a show: its number, its name when the
/// split names its seasons (a story arc, "Hunter Exam"; null for a plain
/// "Season 3"), how many episodes it has (null when the lookup does not
/// say yet) and its date. Used to map statuses from one split to another
/// by episode range ([ranges]); kept on the phone, never in
/// `library.json`.
@freezed
abstract class SeasonSpan with _$SeasonSpan {
  const SeasonSpan._();

  const factory SeasonSpan({
    required int season,
    @JsonKey(includeIfNull: false) String? name,
    int? episodes,
    @ReleasedConverter() Released? released,
  }) = _SeasonSpan;

  factory SeasonSpan.fromJson(Map<String, Object?> json) =>
      _$SeasonSpanFromJson(json);

  /// Each season's episodes as a range, first and last (null: open to the
  /// end), counted from 1 over the whole show. A season after one whose
  /// count is not known has no range.
  static Map<int, (int, int?)> ranges(List<SeasonSpan> split) {
    final ranges = <int, (int, int?)>{};
    var next = 1;
    for (final s in [...split]..sort((a, b) => a.season.compareTo(b.season))) {
      final count = s.episodes;
      if (count == null) {
        ranges[s.season] = (next, null);
        break;
      }
      if (count <= 0) continue;
      ranges[s.season] = (next, next + count - 1);
      next += count;
    }
    return ranges;
  }

  /// Whether two episode ranges share an episode.
  static bool overlaps((int, int?) a, (int, int?) b) =>
      (a.$2 == null || b.$1 <= a.$2!) && (b.$2 == null || a.$1 <= b.$2!);
}
