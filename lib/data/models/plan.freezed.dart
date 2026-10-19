// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Plan {

 String get id; String get name; int? get year; List<String> get tags; bool get timeline;@JsonKey(name: 'seasonal_theme') bool get seasonalTheme;/// Set by the Started switch in Plans › Edit plan, and by the app when the
/// plan's first date arrives. Never cleared on its own.
 bool get started; List<PlanItem> get items;
/// Create a copy of Plan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanCopyWith<Plan> get copyWith => _$PlanCopyWithImpl<Plan>(this as Plan, _$identity);

  /// Serializes this Plan to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Plan;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Plan&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.year, _this.year) || other.year == _this.year)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.timeline, _this.timeline) || other.timeline == _this.timeline)&&(identical(other.seasonalTheme, _this.seasonalTheme) || other.seasonalTheme == _this.seasonalTheme)&&(identical(other.started, _this.started) || other.started == _this.started)&&const DeepCollectionEquality().equals(other.items, _this.items));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Plan;
  return Object.hash(runtimeType,_this.id,_this.name,_this.year,const DeepCollectionEquality().hash(_this.tags),_this.timeline,_this.seasonalTheme,_this.started,const DeepCollectionEquality().hash(_this.items));
}

@override
String toString() {
  final _this = this as Plan;
  return 'Plan(id: ${_this.id}, name: ${_this.name}, year: ${_this.year}, tags: ${_this.tags}, timeline: ${_this.timeline}, seasonalTheme: ${_this.seasonalTheme}, started: ${_this.started}, items: ${_this.items})';
}


}

/// @nodoc
abstract mixin class $PlanCopyWith<$Res>  {
  factory $PlanCopyWith(Plan value, $Res Function(Plan) _then) = _$PlanCopyWithImpl;
@useResult
$Res call({
 String id, String name, int? year, List<String> tags, bool timeline,@JsonKey(name: 'seasonal_theme') bool seasonalTheme, bool started, List<PlanItem> items
});




}
/// @nodoc
class _$PlanCopyWithImpl<$Res>
    implements $PlanCopyWith<$Res> {
  _$PlanCopyWithImpl(this._self, this._then);

  final Plan _self;
  final $Res Function(Plan) _then;

/// Create a copy of Plan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? year = freezed,Object? tags = null,Object? timeline = null,Object? seasonalTheme = null,Object? started = null,Object? items = null,}) {
  return _then(Plan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,timeline: null == timeline ? _self.timeline : timeline // ignore: cast_nullable_to_non_nullable
as bool,seasonalTheme: null == seasonalTheme ? _self.seasonalTheme : seasonalTheme // ignore: cast_nullable_to_non_nullable
as bool,started: null == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as bool,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<PlanItem>,
  ));
}

}


/// Adds pattern-matching-related methods to [Plan].
extension PlanPatterns on Plan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Plan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Plan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Plan value)  $default,){
final _that = this;
switch (_that) {
case _Plan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Plan value)?  $default,){
final _that = this;
switch (_that) {
case _Plan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int? year,  List<String> tags,  bool timeline, @JsonKey(name: 'seasonal_theme')  bool seasonalTheme,  bool started,  List<PlanItem> items)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Plan() when $default != null:
return $default(_that.id,_that.name,_that.year,_that.tags,_that.timeline,_that.seasonalTheme,_that.started,_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int? year,  List<String> tags,  bool timeline, @JsonKey(name: 'seasonal_theme')  bool seasonalTheme,  bool started,  List<PlanItem> items)  $default,) {final _that = this;
switch (_that) {
case _Plan():
return $default(_that.id,_that.name,_that.year,_that.tags,_that.timeline,_that.seasonalTheme,_that.started,_that.items);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int? year,  List<String> tags,  bool timeline, @JsonKey(name: 'seasonal_theme')  bool seasonalTheme,  bool started,  List<PlanItem> items)?  $default,) {final _that = this;
switch (_that) {
case _Plan() when $default != null:
return $default(_that.id,_that.name,_that.year,_that.tags,_that.timeline,_that.seasonalTheme,_that.started,_that.items);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Plan extends Plan {
  const _Plan({required this.id, required this.name, this.year,  List<String> tags = const [], this.timeline = false, @JsonKey(name: 'seasonal_theme') this.seasonalTheme = false, this.started = false,  List<PlanItem> items = const []}): _tags = tags,_items = items,super._();
  factory _Plan.fromJson(Map<String, dynamic> json) => _$PlanFromJson(json);

@override final  String id;
@override final  String name;
@override final  int? year;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey() final  bool timeline;
@override@JsonKey(name: 'seasonal_theme') final  bool seasonalTheme;
/// Set by the Started switch in Plans › Edit plan, and by the app when the
/// plan's first date arrives. Never cleared on its own.
@override@JsonKey() final  bool started;
 final  List<PlanItem> _items;
@override@JsonKey() List<PlanItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of Plan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanCopyWith<_Plan> get copyWith => __$PlanCopyWithImpl<_Plan>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlanToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Plan&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.year, year) || other.year == year)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.timeline, timeline) || other.timeline == timeline)&&(identical(other.seasonalTheme, seasonalTheme) || other.seasonalTheme == seasonalTheme)&&(identical(other.started, started) || other.started == started)&&const DeepCollectionEquality().equals(other.items, _items));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,year,const DeepCollectionEquality().hash(_tags),timeline,seasonalTheme,started,const DeepCollectionEquality().hash(_items));
}

@override
String toString() {
    return 'Plan(id: $id, name: $name, year: $year, tags: $tags, timeline: $timeline, seasonalTheme: $seasonalTheme, started: $started, items: $items)';
}


}

/// @nodoc
abstract mixin class _$PlanCopyWith<$Res> implements $PlanCopyWith<$Res> {
  factory _$PlanCopyWith(_Plan value, $Res Function(_Plan) _then) = __$PlanCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int? year, List<String> tags, bool timeline,@JsonKey(name: 'seasonal_theme') bool seasonalTheme, bool started, List<PlanItem> items
});




}
/// @nodoc
class __$PlanCopyWithImpl<$Res>
    implements _$PlanCopyWith<$Res> {
  __$PlanCopyWithImpl(this._self, this._then);

  final _Plan _self;
  final $Res Function(_Plan) _then;

/// Create a copy of Plan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? year = freezed,Object? tags = null,Object? timeline = null,Object? seasonalTheme = null,Object? started = null,Object? items = null,}) {
  return _then(_Plan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,year: freezed == year ? _self.year : year // ignore: cast_nullable_to_non_nullable
as int?,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,timeline: null == timeline ? _self.timeline : timeline // ignore: cast_nullable_to_non_nullable
as bool,seasonalTheme: null == seasonalTheme ? _self.seasonalTheme : seasonalTheme // ignore: cast_nullable_to_non_nullable
as bool,started: null == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as bool,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<PlanItem>,
  ));
}


}

// dart format on
