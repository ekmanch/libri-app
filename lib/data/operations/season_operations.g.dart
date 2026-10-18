// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_operations.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SetSeasonStatus _$SetSeasonStatusFromJson(Map<String, dynamic> json) =>
    SetSeasonStatus(
      json['entryId'] as String,
      (json['season'] as num).toInt(),
      $enumDecodeNullable(_$EntryStatusEnumMap, json['status']),
    );

Map<String, dynamic> _$SetSeasonStatusToJson(SetSeasonStatus instance) =>
    <String, dynamic>{
      'entryId': instance.entryId,
      'season': instance.season,
      'status': _$EntryStatusEnumMap[instance.status],
    };

const _$EntryStatusEnumMap = {
  EntryStatus.want: 'want',
  EntryStatus.inProgress: 'in_progress',
  EntryStatus.done: 'done',
  EntryStatus.dnf: 'dnf',
};

MarkSeasonsDone _$MarkSeasonsDoneFromJson(Map<String, dynamic> json) =>
    MarkSeasonsDone(json['entryId'] as String, (json['before'] as num).toInt());

Map<String, dynamic> _$MarkSeasonsDoneToJson(MarkSeasonsDone instance) =>
    <String, dynamic>{'entryId': instance.entryId, 'before': instance.before};

AddSeasons _$AddSeasonsFromJson(Map<String, dynamic> json) => AddSeasons(
  json['entryId'] as String,
  (json['seasons'] as List<dynamic>)
      .map((e) => Season.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$AddSeasonsToJson(AddSeasons instance) =>
    <String, dynamic>{
      'entryId': instance.entryId,
      'seasons': instance.seasons.map((e) => e.toJson()).toList(),
    };
