// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Entry {

 String get id; MediaType get type; String get title;@ReleasedConverter() Released? get released; String? get creator; EntryStatus get status; int? get rating; List<String> get tags; String get note; String get description;@JsonKey(name: 'seasonal_only') bool get seasonalOnly;@DateOnlyConverter() DateTime get added;/// The lookup id, "tmdb:movie:603", "deezer:album:302127",
/// "openlibrary:OL45804W", or null until a match is picked in A13 or
/// "Look up again". Always written, like `rating`. Covers and track lists
/// for entries without one are matched on the device and never stored
/// here. Changing the type clears it; editing the title never does.
 String? get source;@JsonKey(includeIfNull: false) String? get platform;@JsonKey(includeIfNull: false) List<BookFormat>? get formats;@JsonKey(includeIfNull: false) MusicKind? get kind;@JsonKey(includeIfNull: false) String? get album;@JsonKey(includeIfNull: false) List<Track>? get tracks;@JsonKey(includeIfNull: false) List<Season>? get seasons;
/// Create a copy of Entry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EntryCopyWith<Entry> get copyWith => _$EntryCopyWithImpl<Entry>(this as Entry, _$identity);

  /// Serializes this Entry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Entry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Entry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.released, _this.released) || other.released == _this.released)&&(identical(other.creator, _this.creator) || other.creator == _this.creator)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.rating, _this.rating) || other.rating == _this.rating)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.note, _this.note) || other.note == _this.note)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.seasonalOnly, _this.seasonalOnly) || other.seasonalOnly == _this.seasonalOnly)&&(identical(other.added, _this.added) || other.added == _this.added)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.platform, _this.platform) || other.platform == _this.platform)&&const DeepCollectionEquality().equals(other.formats, _this.formats)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.album, _this.album) || other.album == _this.album)&&const DeepCollectionEquality().equals(other.tracks, _this.tracks)&&const DeepCollectionEquality().equals(other.seasons, _this.seasons));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Entry;
  return Object.hashAll([runtimeType,_this.id,_this.type,_this.title,_this.released,_this.creator,_this.status,_this.rating,const DeepCollectionEquality().hash(_this.tags),_this.note,_this.description,_this.seasonalOnly,_this.added,_this.source,_this.platform,const DeepCollectionEquality().hash(_this.formats),_this.kind,_this.album,const DeepCollectionEquality().hash(_this.tracks),const DeepCollectionEquality().hash(_this.seasons)]);
}

@override
String toString() {
  final _this = this as Entry;
  return 'Entry(id: ${_this.id}, type: ${_this.type}, title: ${_this.title}, released: ${_this.released}, creator: ${_this.creator}, status: ${_this.status}, rating: ${_this.rating}, tags: ${_this.tags}, note: ${_this.note}, description: ${_this.description}, seasonalOnly: ${_this.seasonalOnly}, added: ${_this.added}, source: ${_this.source}, platform: ${_this.platform}, formats: ${_this.formats}, kind: ${_this.kind}, album: ${_this.album}, tracks: ${_this.tracks}, seasons: ${_this.seasons})';
}


}

/// @nodoc
abstract mixin class $EntryCopyWith<$Res>  {
  factory $EntryCopyWith(Entry value, $Res Function(Entry) _then) = _$EntryCopyWithImpl;
@useResult
$Res call({
 String id, MediaType type, String title,@ReleasedConverter() Released? released, String? creator, EntryStatus status, int? rating, List<String> tags, String note, String description,@JsonKey(name: 'seasonal_only') bool seasonalOnly,@DateOnlyConverter() DateTime added, String? source,@JsonKey(includeIfNull: false) String? platform,@JsonKey(includeIfNull: false) List<BookFormat>? formats,@JsonKey(includeIfNull: false) MusicKind? kind,@JsonKey(includeIfNull: false) String? album,@JsonKey(includeIfNull: false) List<Track>? tracks,@JsonKey(includeIfNull: false) List<Season>? seasons
});




}
/// @nodoc
class _$EntryCopyWithImpl<$Res>
    implements $EntryCopyWith<$Res> {
  _$EntryCopyWithImpl(this._self, this._then);

  final Entry _self;
  final $Res Function(Entry) _then;

/// Create a copy of Entry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? title = null,Object? released = freezed,Object? creator = freezed,Object? status = null,Object? rating = freezed,Object? tags = null,Object? note = null,Object? description = null,Object? seasonalOnly = null,Object? added = null,Object? source = freezed,Object? platform = freezed,Object? formats = freezed,Object? kind = freezed,Object? album = freezed,Object? tracks = freezed,Object? seasons = freezed,}) {
  return _then(Entry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,released: freezed == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released?,creator: freezed == creator ? _self.creator : creator // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as EntryStatus,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int?,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,seasonalOnly: null == seasonalOnly ? _self.seasonalOnly : seasonalOnly // ignore: cast_nullable_to_non_nullable
as bool,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as DateTime,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String?,formats: freezed == formats ? _self.formats : formats // ignore: cast_nullable_to_non_nullable
as List<BookFormat>?,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MusicKind?,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,tracks: freezed == tracks ? _self.tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<Track>?,seasons: freezed == seasons ? _self.seasons : seasons // ignore: cast_nullable_to_non_nullable
as List<Season>?,
  ));
}

}


/// Adds pattern-matching-related methods to [Entry].
extension EntryPatterns on Entry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Entry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Entry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Entry value)  $default,){
final _that = this;
switch (_that) {
case _Entry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Entry value)?  $default,){
final _that = this;
switch (_that) {
case _Entry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  MediaType type,  String title, @ReleasedConverter()  Released? released,  String? creator,  EntryStatus status,  int? rating,  List<String> tags,  String note,  String description, @JsonKey(name: 'seasonal_only')  bool seasonalOnly, @DateOnlyConverter()  DateTime added,  String? source, @JsonKey(includeIfNull: false)  String? platform, @JsonKey(includeIfNull: false)  List<BookFormat>? formats, @JsonKey(includeIfNull: false)  MusicKind? kind, @JsonKey(includeIfNull: false)  String? album, @JsonKey(includeIfNull: false)  List<Track>? tracks, @JsonKey(includeIfNull: false)  List<Season>? seasons)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Entry() when $default != null:
return $default(_that.id,_that.type,_that.title,_that.released,_that.creator,_that.status,_that.rating,_that.tags,_that.note,_that.description,_that.seasonalOnly,_that.added,_that.source,_that.platform,_that.formats,_that.kind,_that.album,_that.tracks,_that.seasons);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  MediaType type,  String title, @ReleasedConverter()  Released? released,  String? creator,  EntryStatus status,  int? rating,  List<String> tags,  String note,  String description, @JsonKey(name: 'seasonal_only')  bool seasonalOnly, @DateOnlyConverter()  DateTime added,  String? source, @JsonKey(includeIfNull: false)  String? platform, @JsonKey(includeIfNull: false)  List<BookFormat>? formats, @JsonKey(includeIfNull: false)  MusicKind? kind, @JsonKey(includeIfNull: false)  String? album, @JsonKey(includeIfNull: false)  List<Track>? tracks, @JsonKey(includeIfNull: false)  List<Season>? seasons)  $default,) {final _that = this;
switch (_that) {
case _Entry():
return $default(_that.id,_that.type,_that.title,_that.released,_that.creator,_that.status,_that.rating,_that.tags,_that.note,_that.description,_that.seasonalOnly,_that.added,_that.source,_that.platform,_that.formats,_that.kind,_that.album,_that.tracks,_that.seasons);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  MediaType type,  String title, @ReleasedConverter()  Released? released,  String? creator,  EntryStatus status,  int? rating,  List<String> tags,  String note,  String description, @JsonKey(name: 'seasonal_only')  bool seasonalOnly, @DateOnlyConverter()  DateTime added,  String? source, @JsonKey(includeIfNull: false)  String? platform, @JsonKey(includeIfNull: false)  List<BookFormat>? formats, @JsonKey(includeIfNull: false)  MusicKind? kind, @JsonKey(includeIfNull: false)  String? album, @JsonKey(includeIfNull: false)  List<Track>? tracks, @JsonKey(includeIfNull: false)  List<Season>? seasons)?  $default,) {final _that = this;
switch (_that) {
case _Entry() when $default != null:
return $default(_that.id,_that.type,_that.title,_that.released,_that.creator,_that.status,_that.rating,_that.tags,_that.note,_that.description,_that.seasonalOnly,_that.added,_that.source,_that.platform,_that.formats,_that.kind,_that.album,_that.tracks,_that.seasons);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Entry extends Entry {
  const _Entry({required this.id, required this.type, required this.title, @ReleasedConverter() this.released, this.creator, required this.status, this.rating,  List<String> tags = const [], this.note = '', this.description = '', @JsonKey(name: 'seasonal_only') this.seasonalOnly = false, @DateOnlyConverter() required this.added, this.source, @JsonKey(includeIfNull: false) this.platform, @JsonKey(includeIfNull: false)  List<BookFormat>? formats, @JsonKey(includeIfNull: false) this.kind, @JsonKey(includeIfNull: false) this.album, @JsonKey(includeIfNull: false)  List<Track>? tracks, @JsonKey(includeIfNull: false)  List<Season>? seasons}): _tags = tags,_formats = formats,_tracks = tracks,_seasons = seasons,super._();
  factory _Entry.fromJson(Map<String, dynamic> json) => _$EntryFromJson(json);

@override final  String id;
@override final  MediaType type;
@override final  String title;
@override@ReleasedConverter() final  Released? released;
@override final  String? creator;
@override final  EntryStatus status;
@override final  int? rating;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override@JsonKey() final  String note;
@override@JsonKey() final  String description;
@override@JsonKey(name: 'seasonal_only') final  bool seasonalOnly;
@override@DateOnlyConverter() final  DateTime added;
/// The lookup id, "tmdb:movie:603", "deezer:album:302127",
/// "openlibrary:OL45804W", or null until a match is picked in A13 or
/// "Look up again". Always written, like `rating`. Covers and track lists
/// for entries without one are matched on the device and never stored
/// here. Changing the type clears it; editing the title never does.
@override final  String? source;
@override@JsonKey(includeIfNull: false) final  String? platform;
 final  List<BookFormat>? _formats;
@override@JsonKey(includeIfNull: false) List<BookFormat>? get formats {
  final value = _formats;
  if (value == null) return null;
  if (_formats is EqualUnmodifiableListView) return _formats;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override@JsonKey(includeIfNull: false) final  MusicKind? kind;
@override@JsonKey(includeIfNull: false) final  String? album;
 final  List<Track>? _tracks;
@override@JsonKey(includeIfNull: false) List<Track>? get tracks {
  final value = _tracks;
  if (value == null) return null;
  if (_tracks is EqualUnmodifiableListView) return _tracks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<Season>? _seasons;
@override@JsonKey(includeIfNull: false) List<Season>? get seasons {
  final value = _seasons;
  if (value == null) return null;
  if (_seasons is EqualUnmodifiableListView) return _seasons;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of Entry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EntryCopyWith<_Entry> get copyWith => __$EntryCopyWithImpl<_Entry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EntryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Entry&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.title, title) || other.title == title)&&(identical(other.released, released) || other.released == released)&&(identical(other.creator, creator) || other.creator == creator)&&(identical(other.status, status) || other.status == status)&&(identical(other.rating, rating) || other.rating == rating)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.note, note) || other.note == note)&&(identical(other.description, description) || other.description == description)&&(identical(other.seasonalOnly, seasonalOnly) || other.seasonalOnly == seasonalOnly)&&(identical(other.added, added) || other.added == added)&&(identical(other.source, source) || other.source == source)&&(identical(other.platform, platform) || other.platform == platform)&&const DeepCollectionEquality().equals(other.formats, _formats)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.album, album) || other.album == album)&&const DeepCollectionEquality().equals(other.tracks, _tracks)&&const DeepCollectionEquality().equals(other.seasons, _seasons));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,type,title,released,creator,status,rating,const DeepCollectionEquality().hash(_tags),note,description,seasonalOnly,added,source,platform,const DeepCollectionEquality().hash(_formats),kind,album,const DeepCollectionEquality().hash(_tracks),const DeepCollectionEquality().hash(_seasons)]);
}

@override
String toString() {
    return 'Entry(id: $id, type: $type, title: $title, released: $released, creator: $creator, status: $status, rating: $rating, tags: $tags, note: $note, description: $description, seasonalOnly: $seasonalOnly, added: $added, source: $source, platform: $platform, formats: $formats, kind: $kind, album: $album, tracks: $tracks, seasons: $seasons)';
}


}

/// @nodoc
abstract mixin class _$EntryCopyWith<$Res> implements $EntryCopyWith<$Res> {
  factory _$EntryCopyWith(_Entry value, $Res Function(_Entry) _then) = __$EntryCopyWithImpl;
@override @useResult
$Res call({
 String id, MediaType type, String title,@ReleasedConverter() Released? released, String? creator, EntryStatus status, int? rating, List<String> tags, String note, String description,@JsonKey(name: 'seasonal_only') bool seasonalOnly,@DateOnlyConverter() DateTime added, String? source,@JsonKey(includeIfNull: false) String? platform,@JsonKey(includeIfNull: false) List<BookFormat>? formats,@JsonKey(includeIfNull: false) MusicKind? kind,@JsonKey(includeIfNull: false) String? album,@JsonKey(includeIfNull: false) List<Track>? tracks,@JsonKey(includeIfNull: false) List<Season>? seasons
});




}
/// @nodoc
class __$EntryCopyWithImpl<$Res>
    implements _$EntryCopyWith<$Res> {
  __$EntryCopyWithImpl(this._self, this._then);

  final _Entry _self;
  final $Res Function(_Entry) _then;

/// Create a copy of Entry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? title = null,Object? released = freezed,Object? creator = freezed,Object? status = null,Object? rating = freezed,Object? tags = null,Object? note = null,Object? description = null,Object? seasonalOnly = null,Object? added = null,Object? source = freezed,Object? platform = freezed,Object? formats = freezed,Object? kind = freezed,Object? album = freezed,Object? tracks = freezed,Object? seasons = freezed,}) {
  return _then(_Entry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as MediaType,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,released: freezed == released ? _self.released : released // ignore: cast_nullable_to_non_nullable
as Released?,creator: freezed == creator ? _self.creator : creator // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as EntryStatus,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int?,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,seasonalOnly: null == seasonalOnly ? _self.seasonalOnly : seasonalOnly // ignore: cast_nullable_to_non_nullable
as bool,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as DateTime,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String?,formats: freezed == formats ? _self._formats : formats // ignore: cast_nullable_to_non_nullable
as List<BookFormat>?,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MusicKind?,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,tracks: freezed == tracks ? _self._tracks : tracks // ignore: cast_nullable_to_non_nullable
as List<Track>?,seasons: freezed == seasons ? _self._seasons : seasons // ignore: cast_nullable_to_non_nullable
as List<Season>?,
  ));
}


}

// dart format on
