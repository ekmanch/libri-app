// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Season _$SeasonFromJson(Map<String, dynamic> json) => _Season(
  season: (json['season'] as num).toInt(),
  released: _$JsonConverterFromJson<String, Released>(
    json['released'],
    const ReleasedConverter().fromJson,
  ),
  status: $enumDecodeNullable(_$EntryStatusEnumMap, json['status']),
  fresh: json['new'] as bool?,
);

Map<String, dynamic> _$SeasonToJson(_Season instance) => <String, dynamic>{
  'season': instance.season,
  'released': _$JsonConverterToJson<String, Released>(
    instance.released,
    const ReleasedConverter().toJson,
  ),
  'status': _$EntryStatusEnumMap[instance.status],
  'new': ?instance.fresh,
};

Value? _$JsonConverterFromJson<Json, Value>(
  Object? json,
  Value? Function(Json json) fromJson,
) => json == null ? null : fromJson(json as Json);

const _$EntryStatusEnumMap = {
  EntryStatus.want: 'want',
  EntryStatus.inProgress: 'in_progress',
  EntryStatus.done: 'done',
  EntryStatus.dnf: 'dnf',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) => value == null ? null : toJson(value);
