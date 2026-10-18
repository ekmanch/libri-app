// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'season.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Season {

 int get season;@ReleasedConverter() Released? get released; EntryStatus? get status;@JsonKey(name: 'new', includeIfNull: false) bool? get fresh;@JsonKey(includeIfNull: false) bool? get manual;
/// Create a copy of Season
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeasonCopyWith<Season> get copyWith => _$SeasonCopyWithImpl<Season>(this as Season, _$identity);

  /// Serializes this Season to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Season;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Season&&(identical(other.season, _this.season) || other.season == _this.season)&&(identical(other.released, _this.released) || other.released == _this.released)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.fresh, _this.fresh) || other.fresh == _this.fresh)&&(identical(other.manual, _this.manual) || other.manual == _this.manual));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Season;
  return Object.hash(runtimeType,_this.season,_this.released,_this.status,_this.fresh,_this.manual);
}

@override
String toString() {
  final _this = this as Season;
  return 'Season(season: ${_this.season}, released: ${_this.released}, status: ${_this.status}, fresh: ${_this.fresh}, manual: ${_this.manual})';
}


}

/// @nodoc
abstract mixin class $SeasonCopyWith<$Res>  {
  factory $SeasonCopyWith(Season value, $Res Function(Season) _then) = _$SeasonCopyWithImpl;
@useResult
$Res call({
 int season,@ReleasedConverter() Released? released, EntryStatus? status,@JsonKey(name: 'new', includeIfNull: false) bool? fresh,@JsonKey(includeIfNull: false) bool? manual
});




}
/// @nodoc
class _$SeasonCopyWithImpl<$Res>
    implements $SeasonCopyWith<$Res> {
  _$SeasonCopyWithImpl(this._self, this._then);

  final Season _self;
  final $Res Function(Season) _then;

/// Create a copy of Season
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? season = null,Object? released = freezed,Object? status = freezed,Object? fresh = freezed,Object? manual = freezed,}) {
  return _then(Season(
season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,released: freezed == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as EntryStatus?,fresh: freezed == fresh ? _self.fresh : fresh // ignore: cast_nullable_to_non_nullable
as bool?,manual: freezed == manual ? _self.manual : manual // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [Season].
extension SeasonPatterns on Season {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Season value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Season() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Season value)  $default,){
final _that = this;
switch (_that) {
case _Season():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Season value)?  $default,){
final _that = this;
switch (_that) {
case _Season() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int season, @ReleasedConverter()  Released? released,  EntryStatus? status, @JsonKey(name: 'new', includeIfNull: false)  bool? fresh, @JsonKey(includeIfNull: false)  bool? manual)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Season() when $default != null:
return $default(_that.season,_that.released,_that.status,_that.fresh,_that.manual);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int season, @ReleasedConverter()  Released? released,  EntryStatus? status, @JsonKey(name: 'new', includeIfNull: false)  bool? fresh, @JsonKey(includeIfNull: false)  bool? manual)  $default,) {final _that = this;
switch (_that) {
case _Season():
return $default(_that.season,_that.released,_that.status,_that.fresh,_that.manual);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int season, @ReleasedConverter()  Released? released,  EntryStatus? status, @JsonKey(name: 'new', includeIfNull: false)  bool? fresh, @JsonKey(includeIfNull: false)  bool? manual)?  $default,) {final _that = this;
switch (_that) {
case _Season() when $default != null:
return $default(_that.season,_that.released,_that.status,_that.fresh,_that.manual);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Season extends Season {
  const _Season({required this.season, @ReleasedConverter() this.released, this.status, @JsonKey(name: 'new', includeIfNull: false) this.fresh, @JsonKey(includeIfNull: false) this.manual}): super._();
  factory _Season.fromJson(Map<String, dynamic> json) => _$SeasonFromJson(json);

@override final  int season;
@override@ReleasedConverter() final  Released? released;
@override final  EntryStatus? status;
@override@JsonKey(name: 'new', includeIfNull: false) final  bool? fresh;
@override@JsonKey(includeIfNull: false) final  bool? manual;

/// Create a copy of Season
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SeasonCopyWith<_Season> get copyWith => __$SeasonCopyWithImpl<_Season>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeasonToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Season&&(identical(other.season, season) || other.season == season)&&(identical(other.released, released) || other.released == released)&&(identical(other.status, status) || other.status == status)&&(identical(other.fresh, fresh) || other.fresh == fresh)&&(identical(other.manual, manual) || other.manual == manual));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,season,released,status,fresh,manual);
}

@override
String toString() {
    return 'Season(season: $season, released: $released, status: $status, fresh: $fresh, manual: $manual)';
}


}

/// @nodoc
abstract mixin class _$SeasonCopyWith<$Res> implements $SeasonCopyWith<$Res> {
  factory _$SeasonCopyWith(_Season value, $Res Function(_Season) _then) = __$SeasonCopyWithImpl;
@override @useResult
$Res call({
 int season,@ReleasedConverter() Released? released, EntryStatus? status,@JsonKey(name: 'new', includeIfNull: false) bool? fresh,@JsonKey(includeIfNull: false) bool? manual
});




}
/// @nodoc
class __$SeasonCopyWithImpl<$Res>
    implements _$SeasonCopyWith<$Res> {
  __$SeasonCopyWithImpl(this._self, this._then);

  final _Season _self;
  final $Res Function(_Season) _then;

/// Create a copy of Season
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? season = null,Object? released = freezed,Object? status = freezed,Object? fresh = freezed,Object? manual = freezed,}) {
  return _then(_Season(
season: null == season ? _self.season : season // ignore: cast_nullable_to_non_nullable
as int,released: freezed == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as EntryStatus?,fresh: freezed == fresh ? _self.fresh : fresh // ignore: cast_nullable_to_non_nullable
as bool?,manual: freezed == manual ? _self.manual : manual // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
