// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_operations.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MoveShowsToSeasons _$MoveShowsToSeasonsFromJson(Map<String, dynamic> json) =>
    MoveShowsToSeasons();

Map<String, dynamic> _$MoveShowsToSeasonsToJson(MoveShowsToSeasons instance) =>
    <String, dynamic>{};

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

SetSeasons _$SetSeasonsFromJson(Map<String, dynamic> json) => SetSeasons(
  json['entryId'] as String,
  (json['seasons'] as List<dynamic>)
      .map((e) => Season.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SetSeasonsToJson(SetSeasons instance) =>
    <String, dynamic>{
      'entryId': instance.entryId,
      'seasons': instance.seasons.map((e) => e.toJson()).toList(),
    };

RemoveSeason _$RemoveSeasonFromJson(Map<String, dynamic> json) =>
    RemoveSeason(json['entryId'] as String, (json['season'] as num).toInt());

Map<String, dynamic> _$RemoveSeasonToJson(RemoveSeason instance) =>
    <String, dynamic>{'entryId': instance.entryId, 'season': instance.season};

KeepSeason _$KeepSeasonFromJson(Map<String, dynamic> json) =>
    KeepSeason(json['entryId'] as String, (json['season'] as num).toInt());

Map<String, dynamic> _$KeepSeasonToJson(KeepSeason instance) =>
    <String, dynamic>{'entryId': instance.entryId, 'season': instance.season};

RefreshShowStatus _$RefreshShowStatusFromJson(Map<String, dynamic> json) =>
    RefreshShowStatus(json['entryId'] as String);

Map<String, dynamic> _$RefreshShowStatusToJson(RefreshShowStatus instance) =>
    <String, dynamic>{'entryId': instance.entryId};

SetSeasonDates _$SetSeasonDatesFromJson(Map<String, dynamic> json) =>
    SetSeasonDates(
      json['entryId'] as String,
      (json['dates'] as List<dynamic>)
          .map((e) => Season.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SetSeasonDatesToJson(SetSeasonDates instance) =>
    <String, dynamic>{
      'entryId': instance.entryId,
      'dates': instance.dates.map((e) => e.toJson()).toList(),
    };
