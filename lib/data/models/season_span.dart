import 'package:freezed_annotation/freezed_annotation.dart';

import 'released.dart';

part 'season_span.freezed.dart';
part 'season_span.g.dart';

/// One season as a lookup splits a show: its number, how many episodes it
/// has (null when the lookup does not say yet) and its date. Used to map
/// statuses from one split of an anime to another by episode range
/// ([ResplitSeasons]); never in `library.json`.
@freezed
abstract class SeasonSpan with _$SeasonSpan {
  const factory SeasonSpan({
    required int season,
    int? episodes,
    @ReleasedConverter() Released? released,
  }) = _SeasonSpan;

  factory SeasonSpan.fromJson(Map<String, Object?> json) =>
      _$SeasonSpanFromJson(json);
}
