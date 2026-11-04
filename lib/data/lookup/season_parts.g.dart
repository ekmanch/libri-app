// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_parts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ComingPart _$ComingPartFromJson(Map<String, dynamic> json) => _ComingPart(
  entryId: json['entryId'] as String,
  season: (json['season'] as num).toInt(),
  part: (json['part'] as num).toInt(),
  released: const ReleasedConverter().fromJson(json['released'] as String),
);

Map<String, dynamic> _$ComingPartToJson(_ComingPart instance) =>
    <String, dynamic>{
      'entryId': instance.entryId,
      'season': instance.season,
      'part': instance.part,
      'released': const ReleasedConverter().toJson(instance.released),
    };
