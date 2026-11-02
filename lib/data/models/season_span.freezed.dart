// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'season_span.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SeasonSpan {

 int get season; int? get episodes;@ReleasedConverter() Released? get released;
/// Create a copy of SeasonSpan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeasonSpanCopyWith<SeasonSpan> get copyWith => _$SeasonSpanCopyWithImpl<SeasonSpan>(this as SeasonSpan, _$identity);

  /// Serializes this SeasonSpan to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SeasonSpan;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SeasonSpan&&(identical(other.season, _this.season) || other.season == _this.season)&&(identical(other.episodes, _this.episodes) || other.episodes == _this.episodes)&&(identical(other.released, _this.released) || other.released == _this.released));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SeasonSpan;
  return Object.hash(runtimeType,_this.season,_this.episodes,_this.released);
}

@override
String toString() {
  final _this = this as SeasonSpan;
  return 'SeasonSpan(season: ${_this.season}, episodes: ${_this.episodes}, released: ${_this.released})';
}


}

/// @nodoc
abstract mixin class $SeasonSpanCopyWith<$Res>  {
  factory $SeasonSpanCopyWith(SeasonSpan value, $Res Function(SeasonSpan) _then) = _$SeasonSpanCopyWithImpl;
@useResult
$Res call({
 int season, int? episodes,@ReleasedConverter() Released? released
});




}
/// @nodoc
class _$SeasonSpanCopyWithImpl<$Res>
    implements $SeasonSpanCopyWith<$Res> {
  _$SeasonSpanCopyWithImpl(this._self, this._then);

  final SeasonSpan _self;
  final $Res Function(SeasonSpan) _then;

/// Create a copy of SeasonSpan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? season = null,Object? episodes = freezed,Object? released = freezed,}) {
  return _then(SeasonSpan(
season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,episodes: freezed == episodes ? _self.episodes : episodes // ignore: cast_nullable_to_non_nullable
as int?,released: freezed == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released?,
  ));
}

}


/// Adds pattern-matching-related methods to [SeasonSpan].
extension SeasonSpanPatterns on SeasonSpan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SeasonSpan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SeasonSpan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SeasonSpan value)  $default,){
final _that = this;
switch (_that) {
case _SeasonSpan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SeasonSpan value)?  $default,){
final _that = this;
switch (_that) {
case _SeasonSpan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int season,  int? episodes, @ReleasedConverter()  Released? released)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SeasonSpan() when $default != null:
return $default(_that.season,_that.episodes,_that.released);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int season,  int? episodes, @ReleasedConverter()  Released? released)  $default,) {final _that = this;
switch (_that) {
case _SeasonSpan():
return $default(_that.season,_that.episodes,_that.released);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int season,  int? episodes, @ReleasedConverter()  Released? released)?  $default,) {final _that = this;
switch (_that) {
case _SeasonSpan() when $default != null:
return $default(_that.season,_that.episodes,_that.released);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SeasonSpan implements SeasonSpan {
  const _SeasonSpan({required this.season, this.episodes, @ReleasedConverter() this.released});
  factory _SeasonSpan.fromJson(Map<String, dynamic> json) => _$SeasonSpanFromJson(json);

@override final  int season;
@override final  int? episodes;
@override@ReleasedConverter() final  Released? released;

/// Create a copy of SeasonSpan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SeasonSpanCopyWith<_SeasonSpan> get copyWith => __$SeasonSpanCopyWithImpl<_SeasonSpan>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeasonSpanToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SeasonSpan&&(identical(other.season, season) || other.season == season)&&(identical(other.episodes, episodes) || other.episodes == episodes)&&(identical(other.released, released) || other.released == released));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,season,episodes,released);
}

@override
String toString() {
    return 'SeasonSpan(season: $season, episodes: $episodes, released: $released)';
}


}

/// @nodoc
abstract mixin class _$SeasonSpanCopyWith<$Res> implements $SeasonSpanCopyWith<$Res> {
  factory _$SeasonSpanCopyWith(_SeasonSpan value, $Res Function(_SeasonSpan) _then) = __$SeasonSpanCopyWithImpl;
@override @useResult
$Res call({
 int season, int? episodes,@ReleasedConverter() Released? released
});




}
/// @nodoc
class __$SeasonSpanCopyWithImpl<$Res>
    implements _$SeasonSpanCopyWith<$Res> {
  __$SeasonSpanCopyWithImpl(this._self, this._then);

  final _SeasonSpan _self;
  final $Res Function(_SeasonSpan) _then;

/// Create a copy of SeasonSpan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? season = null,Object? episodes = freezed,Object? released = freezed,}) {
  return _then(_SeasonSpan(
season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,episodes: freezed == episodes ? _self.episodes : episodes // ignore: cast_nullable_to_non_nullable
as int?,released: freezed == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released?,
  ));
}


}

// dart format on
