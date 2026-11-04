// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_span.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SeasonSpan _$SeasonSpanFromJson(Map<String, dynamic> json) => _SeasonSpan(
  season: (json['season'] as num).toInt(),
  name: json['name'] as String?,
  episodes: (json['episodes'] as num?)?.toInt(),
  released: _$JsonConverterFromJson<String, Released>(
    json['released'],
    const ReleasedConverter().fromJson,
  ),
);

Map<String, dynamic> _$SeasonSpanToJson(_SeasonSpan instance) =>
    <String, dynamic>{
      'season': instance.season,
      'name': ?instance.name,
      'episodes': instance.episodes,
      'released': _$JsonConverterToJson<String, Released>(
        instance.released,
        const ReleasedConverter().toJson,
      ),
    };

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) => json == null ? null : fromJson(json as Json);

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) => value == null ? null : toJson(value);
