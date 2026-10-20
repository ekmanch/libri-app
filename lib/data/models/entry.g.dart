// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Entry _$EntryFromJson(Map<String, dynamic> json) => _Entry(
  id: json['id'] as String,
  type: $enumDecode(_$MediaTypeEnumMap, json['type']),
  title: json['title'] as String,
  released: _$JsonConverterFromJson<String, Released>(
    json['released'],
    const ReleasedConverter().fromJson,
  ),
  creator: json['creator'] as String?,
  status: $enumDecode(_$EntryStatusEnumMap, json['status']),
  rating: (json['rating'] as num?)?.toInt(),
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  note: json['note'] as String? ?? '',
  description: json['description'] as String? ?? '',
  seasonalOnly: json['seasonal_only'] as bool? ?? false,
  added: const DateOnlyConverter().fromJson(json['added'] as String),
  source: json['source'] as String?,
  platform: json['platform'] as String?,
  formats: (json['formats'] as List<dynamic>?)
      ?.map((e) => $enumDecode(_$BookFormatEnumMap, e))
      .toList(),
  pages: (json['pages'] as num?)?.toInt(),
  series: json['series'] == null
      ? null
      : Series.fromJson(json['series'] as Map<String, dynamic>),
  kind: $enumDecodeNullable(_$EntryKindEnumMap, json['kind']),
  album: json['album'] as String?,
  tracks: (json['tracks'] as List<dynamic>?)
      ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
      .toList(),
  seasons: (json['seasons'] as List<dynamic>?)
      ?.map((e) => Season.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$EntryToJson(_Entry instance) => <String, dynamic>{
  'id': instance.id,
  'type': _$MediaTypeEnumMap[instance.type]!,
  'title': instance.title,
  'released': _$JsonConverterToJson<String, Released>(
    instance.released,
    const ReleasedConverter().toJson,
  ),
  'creator': instance.creator,
  'status': _$EntryStatusEnumMap[instance.status]!,
  'rating': instance.rating,
  'tags': instance.tags,
  'note': instance.note,
  'description': instance.description,
  'seasonal_only': instance.seasonalOnly,
  'added': const DateOnlyConverter().toJson(instance.added),
  'source': instance.source,
  'platform': ?instance.platform,
  'formats': ?instance.formats?.map((e) => _$BookFormatEnumMap[e]!).toList(),
  'pages': ?instance.pages,
  'series': ?instance.series?.toJson(),
  'kind': ?_$EntryKindEnumMap[instance.kind],
  'album': ?instance.album,
  'tracks': ?instance.tracks?.map((e) => e.toJson()).toList(),
  'seasons': ?instance.seasons?.map((e) => e.toJson()).toList(),
};

const _$MediaTypeEnumMap = {
  MediaType.movies: 'movies',
  MediaType.shows: 'shows',
  MediaType.books: 'books',
  MediaType.games: 'games',
  MediaType.music: 'music',
  MediaType.anime: 'anime',
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

const _$BookFormatEnumMap = {
  BookFormat.audiobook: 'audiobook',
  BookFormat.physical: 'physical',
};

const _$EntryKindEnumMap = {
  EntryKind.album: 'album',
  EntryKind.song: 'song',
  EntryKind.series: 'series',
  EntryKind.movie: 'movie',
};

Json? _$JsonConverterToJson<Json, Value>(
  Value? value,
  Json? Function(Value value) toJson,
) => value == null ? null : toJson(value);
