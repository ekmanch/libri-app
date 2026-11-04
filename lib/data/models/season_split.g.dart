// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_split.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SeasonSplit _$SeasonSplitFromJson(Map<String, dynamic> json) => _SeasonSplit(
  ids: (json['ids'] as List<dynamic>).map((e) => e as String).toList(),
  arcs: json['arcs'] as bool? ?? false,
  service: json['service'] as String?,
  long: json['long'] as bool? ?? false,
  seasons: (json['seasons'] as List<dynamic>)
      .map((e) => SeasonSpan.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SeasonSplitToJson(_SeasonSplit instance) =>
    <String, dynamic>{
      'ids': instance.ids,
      'arcs': instance.arcs,
      'service': ?instance.service,
      'long': instance.long,
      'seasons': instance.seasons.map((e) => e.toJson()).toList(),
    };
