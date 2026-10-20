import 'package:freezed_annotation/freezed_annotation.dart';

part 'series.freezed.dart';
part 'series.g.dart';

/// The series an entry belongs to (Library › Movie in a series; Book in a
/// long series): its name and the entry's number in it, in the source's
/// numbering (usually story order), or null when the number is not known.
/// Only these two are stored; the full list of parts is fetched and kept on
/// the phone (`SeriesService`). Movies, books, games and anime movies can
/// have one; shows and anime series use seasons instead.
@freezed
abstract class Series with _$Series {
  const factory Series({required String name, int? number}) = _Series;

  factory Series.fromJson(Map<String, Object?> json) => _$SeriesFromJson(json);
}
