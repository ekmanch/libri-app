import 'package:freezed_annotation/freezed_annotation.dart';

part 'track.freezed.dart';
part 'track.g.dart';

/// A track on an album entry; never a song entry. An album with an online
/// match stores only its rated tracks ([title], [id] when known, [rating]):
/// its list is fetched, never stored. An album without one keeps its own
/// list, made by hand: every track with its number [n] and an optional
/// [length] ("4:31"), rated or not. The keys are written in this order, each
/// but the title only when present. [id] is the lookup id.
@freezed
abstract class Track with _$Track {
  const factory Track({
    @JsonKey(includeIfNull: false) int? n,
    required String title,
    @JsonKey(includeIfNull: false) String? length,
    @JsonKey(includeIfNull: false) String? id,
    @JsonKey(includeIfNull: false) int? rating,
  }) = _Track;

  factory Track.fromJson(Map<String, Object?> json) => _$TrackFromJson(json);
}
