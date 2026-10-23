// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_operations.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddTag _$AddTagFromJson(Map<String, dynamic> json) => AddTag(
  json['name'] as String,
  (json['categories'] as List<dynamic>)
      .map((e) => $enumDecode(_$TagCategoryEnumMap, e))
      .toList(),
);

Map<String, dynamic> _$AddTagToJson(AddTag instance) => <String, dynamic>{
  'name': instance.name,
  'categories': instance.categories
      .map((e) => _$TagCategoryEnumMap[e]!)
      .toList(),
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
  TagCategory.animationStyle: 'Animation style',
  TagCategory.other: 'Other',
};

SetTagCategories _$SetTagCategoriesFromJson(Map<String, dynamic> json) =>
    SetTagCategories(
      json['name'] as String,
      (json['categories'] as List<dynamic>)
          .map((e) => $enumDecode(_$TagCategoryEnumMap, e))
          .toList(),
    );

Map<String, dynamic> _$SetTagCategoriesToJson(SetTagCategories instance) =>
    <String, dynamic>{
      'name': instance.name,
      'categories': instance.categories
          .map((e) => _$TagCategoryEnumMap[e]!)
          .toList(),
    };
