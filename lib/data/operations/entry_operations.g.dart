// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry_operations.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SetStatus _$SetStatusFromJson(Map<String, dynamic> json) => SetStatus(
  json['entryId'] as String,
  $enumDecode(_$EntryStatusEnumMap, json['status']),
);

Map<String, dynamic> _$SetStatusToJson(SetStatus instance) => <String, dynamic>{
  'entryId': instance.entryId,
  'status': _$EntryStatusEnumMap[instance.status]!,
};

const _$EntryStatusEnumMap = {
  EntryStatus.want: 'want',
  EntryStatus.inProgress: 'in_progress',
  EntryStatus.done: 'done',
  EntryStatus.dnf: 'dnf',
};

SetKind _$SetKindFromJson(Map<String, dynamic> json) => SetKind(
  json['entryId'] as String,
  $enumDecode(_$EntryKindEnumMap, json['kind']),
);

Map<String, dynamic> _$SetKindToJson(SetKind instance) => <String, dynamic>{
  'entryId': instance.entryId,
  'kind': _$EntryKindEnumMap[instance.kind]!,
};

const _$EntryKindEnumMap = {
  EntryKind.album: 'album',
  EntryKind.song: 'song',
  EntryKind.series: 'series',
  EntryKind.movie: 'movie',
};

SetRating _$SetRatingFromJson(Map<String, dynamic> json) =>
    SetRating(json['entryId'] as String, (json['rating'] as num?)?.toInt());

Map<String, dynamic> _$SetRatingToJson(SetRating instance) => <String, dynamic>{
  'entryId': instance.entryId,
  'rating': instance.rating,
};

AddEntry _$AddEntryFromJson(Map<String, dynamic> json) =>
    AddEntry(Entry.fromJson(json['entry'] as Map<String, dynamic>));

Map<String, dynamic> _$AddEntryToJson(AddEntry instance) => <String, dynamic>{
  'entry': instance.entry.toJson(),
};

UpdateEntry _$UpdateEntryFromJson(Map<String, dynamic> json) =>
    UpdateEntry(Entry.fromJson(json['entry'] as Map<String, dynamic>));

Map<String, dynamic> _$UpdateEntryToJson(UpdateEntry instance) =>
    <String, dynamic>{'entry': instance.entry.toJson()};

DeleteEntry _$DeleteEntryFromJson(Map<String, dynamic> json) =>
    DeleteEntry(json['entryId'] as String);

Map<String, dynamic> _$DeleteEntryToJson(DeleteEntry instance) =>
    <String, dynamic>{'entryId': instance.entryId};

RateTrack _$RateTrackFromJson(Map<String, dynamic> json) => RateTrack(
  json['entryId'] as String,
  Track.fromJson(json['track'] as Map<String, dynamic>),
);

Map<String, dynamic> _$RateTrackToJson(RateTrack instance) => <String, dynamic>{
  'entryId': instance.entryId,
  'track': instance.track.toJson(),
};

ClearTrackRating _$ClearTrackRatingFromJson(Map<String, dynamic> json) =>
    ClearTrackRating(
      json['entryId'] as String,
      trackId: json['trackId'] as String?,
      title: json['title'] as String?,
    );

Map<String, dynamic> _$ClearTrackRatingToJson(ClearTrackRating instance) =>
    <String, dynamic>{
      'entryId': instance.entryId,
      'trackId': instance.trackId,
      'title': instance.title,
    };
