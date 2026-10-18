// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_operations.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddTag _$AddTagFromJson(Map<String, dynamic> json) => AddTag(
  json['name'] as String,
  $enumDecode(_$TagCategoryEnumMap, json['category']),
);

Map<String, dynamic> _$AddTagToJson(AddTag instance) => <String, dynamic>{
  'name': instance.name,
  'category': _$TagCategoryEnumMap[instance.category]!,
};

const _$TagCategoryEnumMap = {
  TagCategory.genre: 'Genres',
  TagCategory.gameGenre: 'Game genres',
  TagCategory.musicGenre: 'Music genres',
  TagCategory.mood: 'Mood',
  TagCategory.season: 'Season',
  TagCategory.authors: 'Authors',
  TagCategory.directors: 'Directors',
  TagCategory.actors: 'Actors',
  TagCategory.studios: 'Studios',
  TagCategory.animationStyle: 'Animation style',
  TagCategory.other: 'Other',
};
