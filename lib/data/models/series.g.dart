// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'series.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Series _$SeriesFromJson(Map<String, dynamic> json) => _Series(
  name: json['name'] as String,
  number: (json['number'] as num?)?.toInt(),
);

Map<String, dynamic> _$SeriesToJson(_Series instance) => <String, dynamic>{
  'name': instance.name,
  'number': instance.number,
};
