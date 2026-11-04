// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'season_parts.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ComingPart {

 String get entryId; int get season; int get part;@ReleasedConverter() Released get released;
/// Create a copy of ComingPart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComingPartCopyWith<ComingPart> get copyWith => _$ComingPartCopyWithImpl<ComingPart>(this as ComingPart, _$identity);

  /// Serializes this ComingPart to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ComingPart;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComingPart&&(identical(other.entryId, _this.entryId) || other.entryId == _this.entryId)&&(identical(other.season, _this.season) || other.season == _this.season)&&(identical(other.part, _this.part) || other.part == _this.part)&&(identical(other.released, _this.released) || other.released == _this.released));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ComingPart;
  return Object.hash(runtimeType,_this.entryId,_this.season,_this.part,_this.released);
}

@override
String toString() {
  final _this = this as ComingPart;
  return 'ComingPart(entryId: ${_this.entryId}, season: ${_this.season}, part: ${_this.part}, released: ${_this.released})';
}


}

/// @nodoc
abstract mixin class $ComingPartCopyWith<$Res>  {
  factory $ComingPartCopyWith(ComingPart value, $Res Function(ComingPart) _then) = _$ComingPartCopyWithImpl;
@useResult
$Res call({
 String entryId, int season, int part,@ReleasedConverter() Released released
});




}
/// @nodoc
class _$ComingPartCopyWithImpl<$Res>
    implements $ComingPartCopyWith<$Res> {
  _$ComingPartCopyWithImpl(this._self, this._then);

  final ComingPart _self;
  final $Res Function(ComingPart) _then;

/// Create a copy of ComingPart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entryId = null,Object? season = null,Object? part = null,Object? released = null,}) {
  return _then(ComingPart(
entryId: null == entryId ? _self.entryId : entryId // ignore: cast_nullable_to_non_nullable
as String,season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,part: null == part ? _self.part : part // ignore: cast_nullable_to_non_nullable
as int,released: null == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released,
  ));
}

}


/// Adds pattern-matching-related methods to [ComingPart].
extension ComingPartPatterns on ComingPart {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComingPart value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComingPart() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComingPart value)  $default,){
final _that = this;
switch (_that) {
case _ComingPart():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComingPart value)?  $default,){
final _that = this;
switch (_that) {
case _ComingPart() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String entryId,  int season,  int part, @ReleasedConverter()  Released released)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComingPart() when $default != null:
return $default(_that.entryId,_that.season,_that.part,_that.released);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String entryId,  int season,  int part, @ReleasedConverter()  Released released)  $default,) {final _that = this;
switch (_that) {
case _ComingPart():
return $default(_that.entryId,_that.season,_that.part,_that.released);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String entryId,  int season,  int part, @ReleasedConverter()  Released released)?  $default,) {final _that = this;
switch (_that) {
case _ComingPart() when $default != null:
return $default(_that.entryId,_that.season,_that.part,_that.released);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ComingPart extends ComingPart {
  const _ComingPart({required this.entryId, required this.season, required this.part, @ReleasedConverter() required this.released}): super._();
  factory _ComingPart.fromJson(Map<String, dynamic> json) => _$ComingPartFromJson(json);

@override final  String entryId;
@override final  int season;
@override final  int part;
@override@ReleasedConverter() final  Released released;

/// Create a copy of ComingPart
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComingPartCopyWith<_ComingPart> get copyWith => __$ComingPartCopyWithImpl<_ComingPart>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ComingPartToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComingPart&&(identical(other.entryId, entryId) || other.entryId == entryId)&&(identical(other.season, season) || other.season == season)&&(identical(other.part, part) || other.part == part)&&(identical(other.released, released) || other.released == released));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,entryId,season,part,released);
}

@override
String toString() {
    return 'ComingPart(entryId: $entryId, season: $season, part: $part, released: $released)';
}


}

/// @nodoc
abstract mixin class _$ComingPartCopyWith<$Res> implements $ComingPartCopyWith<$Res> {
  factory _$ComingPartCopyWith(_ComingPart value, $Res Function(_ComingPart) _then) = __$ComingPartCopyWithImpl;
@override @useResult
$Res call({
 String entryId, int season, int part,@ReleasedConverter() Released released
});




}
/// @nodoc
class __$ComingPartCopyWithImpl<$Res>
    implements _$ComingPartCopyWith<$Res> {
  __$ComingPartCopyWithImpl(this._self, this._then);

  final _ComingPart _self;
  final $Res Function(_ComingPart) _then;

/// Create a copy of ComingPart
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entryId = null,Object? season = null,Object? part = null,Object? released = null,}) {
  return _then(_ComingPart(
entryId: null == entryId ? _self.entryId : entryId // ignore: cast_nullable_to_non_nullable
as String,season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,part: null == part ? _self.part : part // ignore: cast_nullable_to_non_nullable
as int,released: null == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released,
  ));
}


}

// dart format on
