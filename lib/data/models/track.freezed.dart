// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'track.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Track {

@JsonKey(includeIfNull: false) int? get n; String get title;@JsonKey(includeIfNull: false) String? get length;@JsonKey(includeIfNull: false) String? get id;@JsonKey(includeIfNull: false) int? get rating;
/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrackCopyWith<Track> get copyWith => _$TrackCopyWithImpl<Track>(this as Track, _$identity);

  /// Serializes this Track to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Track;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Track&&(identical(other.n, _this.n) || other.n == _this.n)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.length, _this.length) || other.length == _this.length)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.rating, _this.rating) || other.rating == _this.rating));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Track;
  return Object.hash(runtimeType,_this.n,_this.title,_this.length,_this.id,_this.rating);
}

@override
String toString() {
  final _this = this as Track;
  return 'Track(n: ${_this.n}, title: ${_this.title}, length: ${_this.length}, id: ${_this.id}, rating: ${_this.rating})';
}


}

/// @nodoc
abstract mixin class $TrackCopyWith<$Res>  {
  factory $TrackCopyWith(Track value, $Res Function(Track) _then) = _$TrackCopyWithImpl;
@useResult
$Res call({
@JsonKey(includeIfNull: false) int? n, String title,@JsonKey(includeIfNull: false) String? length,@JsonKey(includeIfNull: false) String? id,@JsonKey(includeIfNull: false) int? rating
});




}
/// @nodoc
class _$TrackCopyWithImpl<$Res>
    implements $TrackCopyWith<$Res> {
  _$TrackCopyWithImpl(this._self, this._then);

  final Track _self;
  final $Res Function(Track) _then;

/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? n = freezed,Object? title = null,Object? length = freezed,Object? id = freezed,Object? rating = freezed,}) {
  return _then(Track(
n: freezed == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,length: freezed == length ? _self.length : length // ignore: cast_nullable_to_non_nullable
as String?,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [Track].
extension TrackPatterns on Track {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Track value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Track() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Track value)  $default,){
final _that = this;
switch (_that) {
case _Track():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Track value)?  $default,){
final _that = this;
switch (_that) {
case _Track() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(includeIfNull: false)  int? n,  String title, @JsonKey(includeIfNull: false)  String? length, @JsonKey(includeIfNull: false)  String? id, @JsonKey(includeIfNull: false)  int? rating)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Track() when $default != null:
return $default(_that.n,_that.title,_that.length,_that.id,_that.rating);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(includeIfNull: false)  int? n,  String title, @JsonKey(includeIfNull: false)  String? length, @JsonKey(includeIfNull: false)  String? id, @JsonKey(includeIfNull: false)  int? rating)  $default,) {final _that = this;
switch (_that) {
case _Track():
return $default(_that.n,_that.title,_that.length,_that.id,_that.rating);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(includeIfNull: false)  int? n,  String title, @JsonKey(includeIfNull: false)  String? length, @JsonKey(includeIfNull: false)  String? id, @JsonKey(includeIfNull: false)  int? rating)?  $default,) {final _that = this;
switch (_that) {
case _Track() when $default != null:
return $default(_that.n,_that.title,_that.length,_that.id,_that.rating);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Track implements Track {
  const _Track({@JsonKey(includeIfNull: false) this.n, required this.title, @JsonKey(includeIfNull: false) this.length, @JsonKey(includeIfNull: false) this.id, @JsonKey(includeIfNull: false) this.rating});
  factory _Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);

@override@JsonKey(includeIfNull: false) final  int? n;
@override final  String title;
@override@JsonKey(includeIfNull: false) final  String? length;
@override@JsonKey(includeIfNull: false) final  String? id;
@override@JsonKey(includeIfNull: false) final  int? rating;

/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TrackCopyWith<_Track> get copyWith => __$TrackCopyWithImpl<_Track>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TrackToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Track&&(identical(other.n, n) || other.n == n)&&(identical(other.title, title) || other.title == title)&&(identical(other.length, length) || other.length == length)&&(identical(other.id, id) || other.id == id)&&(identical(other.rating, rating) || other.rating == rating));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,n,title,length,id,rating);
}

@override
String toString() {
    return 'Track(n: $n, title: $title, length: $length, id: $id, rating: $rating)';
}


}

/// @nodoc
abstract mixin class _$TrackCopyWith<$Res> implements $TrackCopyWith<$Res> {
  factory _$TrackCopyWith(_Track value, $Res Function(_Track) _then) = __$TrackCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(includeIfNull: false) int? n, String title,@JsonKey(includeIfNull: false) String? length,@JsonKey(includeIfNull: false) String? id,@JsonKey(includeIfNull: false) int? rating
});




}
/// @nodoc
class __$TrackCopyWithImpl<$Res>
    implements _$TrackCopyWith<$Res> {
  __$TrackCopyWithImpl(this._self, this._then);

  final _Track _self;
  final $Res Function(_Track) _then;

/// Create a copy of Track
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? n = freezed,Object? title = null,Object? length = freezed,Object? id = freezed,Object? rating = freezed,}) {
  return _then(_Track(
n: freezed == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,length: freezed == length ? _self.length : length // ignore: cast_nullable_to_non_nullable
as String?,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
