// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'season_split.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SeasonSplit implements DiagnosticableTreeMixin {

/// Where the split comes from, the first being the id written as
/// `seasons_from`: "anilist" (AniList's sequel chain, parts folded),
/// "anilist:parts" (the chain's entries one by one), "tmdb:seasons"
/// (the TMDB show's season list), `tmdb:group:<id>` (one of its
/// episode groups). Several when sources split alike ([distinct]).
 List<String> get ids;/// One season per story arc (a TMDB story-arc group): the seasons are
/// named after the arcs, and this is the split Libri picks for a long
/// run ([automatic]).
 bool get arcs;/// The streaming service whose seasons a TMDB group follows
/// ("Netflix", "Crunchyroll"), named in the sheet beside the season
/// count (owner's decision, 2026-11-04); null for any other split.
@JsonKey(includeIfNull: false) String? get service;/// A regular list that is one long run: one season of more than 100
/// episodes, or airing with no count for years (Hunter x Hunter, One
/// Piece). Its automatic split is the arcs ([automatic]).
 bool get long;/// In season number order.
 List<SeasonSpan> get seasons;
/// Create a copy of SeasonSplit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SeasonSplitCopyWith<SeasonSplit> get copyWith => _$SeasonSplitCopyWithImpl<SeasonSplit>(this as SeasonSplit, _$identity);

  /// Serializes this SeasonSplit to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  final _this = this as SeasonSplit;
  properties
    ..add(DiagnosticsProperty('type', 'SeasonSplit'))
    ..add(DiagnosticsProperty('ids', _this.ids))..add(DiagnosticsProperty('arcs', _this.arcs))..add(DiagnosticsProperty('service', _this.service))..add(DiagnosticsProperty('long', _this.long))..add(DiagnosticsProperty('seasons', _this.seasons));
}

@override
bool operator ==(Object other) {
  final _this = this as SeasonSplit;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SeasonSplit&&const DeepCollectionEquality().equals(other.ids, _this.ids)&&(identical(other.arcs, _this.arcs) || other.arcs == _this.arcs)&&(identical(other.service, _this.service) || other.service == _this.service)&&(identical(other.long, _this.long) || other.long == _this.long)&&const DeepCollectionEquality().equals(other.seasons, _this.seasons));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SeasonSplit;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.ids),_this.arcs,_this.service,_this.long,const DeepCollectionEquality().hash(_this.seasons));
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  final _this = this as SeasonSplit;
  return 'SeasonSplit(ids: ${_this.ids}, arcs: ${_this.arcs}, service: ${_this.service}, long: ${_this.long}, seasons: ${_this.seasons})';
}


}

/// @nodoc
abstract mixin class $SeasonSplitCopyWith<$Res>  {
  factory $SeasonSplitCopyWith(SeasonSplit value, $Res Function(SeasonSplit) _then) = _$SeasonSplitCopyWithImpl;
@useResult
$Res call({
 List<String> ids, bool arcs,@JsonKey(includeIfNull: false) String? service, bool long, List<SeasonSpan> seasons
});




}
/// @nodoc
class _$SeasonSplitCopyWithImpl<$Res>
    implements $SeasonSplitCopyWith<$Res> {
  _$SeasonSplitCopyWithImpl(this._self, this._then);

  final SeasonSplit _self;
  final $Res Function(SeasonSplit) _then;

/// Create a copy of SeasonSplit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ids = null,Object? arcs = null,Object? service = freezed,Object? long = null,Object? seasons = null,}) {
  return _then(SeasonSplit(
ids: null == ids ? _self.ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,arcs: null == arcs ? _self.arcs : arcs // ignore: cast_nullable_to_non_nullable
as bool,service: freezed == service ? _self.service : service // ignore: cast_nullable_to_non_nullable
as String?,long: null == long ? _self.long : long // ignore: cast_nullable_to_non_nullable
as bool,seasons: null == seasons ? _self.seasons : seasons // ignore: cast_nullable_to_non_nullable
as List<SeasonSpan>,
  ));
}

}


/// Adds pattern-matching-related methods to [SeasonSplit].
extension SeasonSplitPatterns on SeasonSplit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SeasonSplit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SeasonSplit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SeasonSplit value)  $default,){
final _that = this;
switch (_that) {
case _SeasonSplit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SeasonSplit value)?  $default,){
final _that = this;
switch (_that) {
case _SeasonSplit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> ids,  bool arcs, @JsonKey(includeIfNull: false)  String? service,  bool long,  List<SeasonSpan> seasons)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SeasonSplit() when $default != null:
return $default(_that.ids,_that.arcs,_that.service,_that.long,_that.seasons);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> ids,  bool arcs, @JsonKey(includeIfNull: false)  String? service,  bool long,  List<SeasonSpan> seasons)  $default,) {final _that = this;
switch (_that) {
case _SeasonSplit():
return $default(_that.ids,_that.arcs,_that.service,_that.long,_that.seasons);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> ids,  bool arcs, @JsonKey(includeIfNull: false)  String? service,  bool long,  List<SeasonSpan> seasons)?  $default,) {final _that = this;
switch (_that) {
case _SeasonSplit() when $default != null:
return $default(_that.ids,_that.arcs,_that.service,_that.long,_that.seasons);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SeasonSplit extends SeasonSplit with DiagnosticableTreeMixin {
  const _SeasonSplit({required  List<String> ids, this.arcs = false, @JsonKey(includeIfNull: false) this.service, this.long = false, required  List<SeasonSpan> seasons}): _ids = ids,_seasons = seasons,super._();
  factory _SeasonSplit.fromJson(Map<String, dynamic> json) => _$SeasonSplitFromJson(json);

/// Where the split comes from, the first being the id written as
/// `seasons_from`: "anilist" (AniList's sequel chain, parts folded),
/// "anilist:parts" (the chain's entries one by one), "tmdb:seasons"
/// (the TMDB show's season list), `tmdb:group:<id>` (one of its
/// episode groups). Several when sources split alike ([distinct]).
 final  List<String> _ids;
/// Where the split comes from, the first being the id written as
/// `seasons_from`: "anilist" (AniList's sequel chain, parts folded),
/// "anilist:parts" (the chain's entries one by one), "tmdb:seasons"
/// (the TMDB show's season list), `tmdb:group:<id>` (one of its
/// episode groups). Several when sources split alike ([distinct]).
@override List<String> get ids {
  if (_ids is EqualUnmodifiableListView) return _ids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ids);
}

/// One season per story arc (a TMDB story-arc group): the seasons are
/// named after the arcs, and this is the split Libri picks for a long
/// run ([automatic]).
@override@JsonKey() final  bool arcs;
/// The streaming service whose seasons a TMDB group follows
/// ("Netflix", "Crunchyroll"), named in the sheet beside the season
/// count (owner's decision, 2026-11-04); null for any other split.
@override@JsonKey(includeIfNull: false) final  String? service;
/// A regular list that is one long run: one season of more than 100
/// episodes, or airing with no count for years (Hunter x Hunter, One
/// Piece). Its automatic split is the arcs ([automatic]).
@override@JsonKey() final  bool long;
/// In season number order.
 final  List<SeasonSpan> _seasons;
/// In season number order.
@override List<SeasonSpan> get seasons {
  if (_seasons is EqualUnmodifiableListView) return _seasons;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_seasons);
}


/// Create a copy of SeasonSplit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SeasonSplitCopyWith<_SeasonSplit> get copyWith => __$SeasonSplitCopyWithImpl<_SeasonSplit>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SeasonSplitToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'SeasonSplit'))
    ..add(DiagnosticsProperty('ids', ids))..add(DiagnosticsProperty('arcs', arcs))..add(DiagnosticsProperty('service', service))..add(DiagnosticsProperty('long', long))..add(DiagnosticsProperty('seasons', seasons));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SeasonSplit&&const DeepCollectionEquality().equals(other.ids, _ids)&&(identical(other.arcs, arcs) || other.arcs == arcs)&&(identical(other.service, service) || other.service == service)&&(identical(other.long, long) || other.long == long)&&const DeepCollectionEquality().equals(other.seasons, _seasons));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_ids),arcs,service,long,const DeepCollectionEquality().hash(_seasons));
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'SeasonSplit(ids: $ids, arcs: $arcs, service: $service, long: $long, seasons: $seasons)';
}


}

/// @nodoc
abstract mixin class _$SeasonSplitCopyWith<$Res> implements $SeasonSplitCopyWith<$Res> {
  factory _$SeasonSplitCopyWith(_SeasonSplit value, $Res Function(_SeasonSplit) _then) = __$SeasonSplitCopyWithImpl;
@override @useResult
$Res call({
 List<String> ids, bool arcs,@JsonKey(includeIfNull: false) String? service, bool long, List<SeasonSpan> seasons
});




}
/// @nodoc
class __$SeasonSplitCopyWithImpl<$Res>
    implements _$SeasonSplitCopyWith<$Res> {
  __$SeasonSplitCopyWithImpl(this._self, this._then);

  final _SeasonSplit _self;
  final $Res Function(_SeasonSplit) _then;

/// Create a copy of SeasonSplit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ids = null,Object? arcs = null,Object? service = freezed,Object? long = null,Object? seasons = null,}) {
  return _then(_SeasonSplit(
ids: null == ids ? _self._ids : ids // ignore: cast_nullable_to_non_nullable
as List<String>,arcs: null == arcs ? _self.arcs : arcs // ignore: cast_nullable_to_non_nullable
as bool,service: freezed == service ? _self.service : service // ignore: cast_nullable_to_non_nullable
as String?,long: null == long ? _self.long : long // ignore: cast_nullable_to_non_nullable
as bool,seasons: null == seasons ? _self._seasons : seasons // ignore: cast_nullable_to_non_nullable
as List<SeasonSpan>,
  ));
}


}

// dart format on
