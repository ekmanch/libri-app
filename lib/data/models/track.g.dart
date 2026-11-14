// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Track _$TrackFromJson(Map<String, dynamic> json) => _Track(
  n: (json['n'] as num?)?.toInt(),
  title: json['title'] as String,
  length: json['length'] as String?,
  id: json['id'] as String?,
  rating: (json['rating'] as num?)?.toInt(),
);

Map<String, dynamic> _$TrackToJson(_Track instance) => <String, dynamic>{
  'n': ?instance.n,
  'title': instance.title,
  'length': ?instance.length,
  'id': ?instance.id,
  'rating': ?instance.rating,
};
