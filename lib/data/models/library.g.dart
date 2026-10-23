// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Library _$LibraryFromJson(Map<String, dynamic> json) => _Library(
  version: (json['version'] as num?)?.toInt() ?? 2,
  tags:
      (json['tags'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          $enumDecode(_$TagCategoryEnumMap, k),
          (e as List<dynamic>).map((e) => e as String).toList(),
        ),
      ) ??
      const {},
  entries:
      (json['entries'] as List<dynamic>?)
          ?.map((e) => Entry.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  plans:
      (json['plans'] as List<dynamic>?)
          ?.map((e) => Plan.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$LibraryToJson(_Library instance) => <String, dynamic>{
  'version': instance.version,
  'tags': instance.tags.map((k, e) => MapEntry(_$TagCategoryEnumMap[k]!, e)),
  'entries': instance.entries.map((e) => e.toJson()).toList(),
  'plans': instance.plans.map((e) => e.toJson()).toList(),
};

const _$TagCategoryEnumMap = {
  TagCategory.genre: 'Genres',
  TagCategory.gameGenre: 'Game genres',
  TagCategory.musicGenre: 'Music genres',
  TagCategory.mood: 'Mood',
  TagCategory.season: 'Season',
  TagCategory.languages: 'Languages',
  TagCategory.authors: 'Authors',
  TagCategory.directors: 'Directors',
  TagCategory.actors: 'Actors',
  TagCategory.studios: 'Studios',
  TagCategory.streaming: 'Streaming',
  TagCategory.animationStyle: 'Animation style',
  TagCategory.other: 'Other',
};
