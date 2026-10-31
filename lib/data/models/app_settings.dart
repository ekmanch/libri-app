import 'package:flutter/foundation.dart';

import 'follow_kind.dart';
import 'release_dates.dart';

/// `settings.json`, version 1 (DESIGN.md section 8): the settings that are
/// about the library rather than one phone, kept next to `library.json` in
/// the library repo and synced like it. Every key but `version` is
/// optional and an absent key means its default, so a new file is
/// `{"version": 1}` and a setting put back to its default leaves the file.
///
/// Theme, accent, views, sorts, Only on Wi-Fi and everything fetched stay
/// on the device (`DisplayPreferences`).
@immutable
class AppSettings {
  const AppSettings({
    this.timelineDefault = false,
    this.seasonalThemeDefault = true,
    this.defaultPlatform = defaultPlatformDefault,
    this.languages,
    this.releaseDates = ReleaseDates.both,
    this.upcomingEnabled = true,
    this.unfollowed = const {},
    this.followed = const {},
    this.notInterested = const {},
  });

  static const version = 1;
  static const defaults = AppSettings();
  static const defaultPlatformDefault = 'PC';

  /// The platforms Settings offers as the default (the canvas's list).
  static const platformChoices = [
    'PC',
    'PlayStation 5',
    'Xbox Series X|S',
    'Switch 2',
    'Steam Deck',
  ];

  /// What a new plan's Timeline switch starts as (Plans › New plan).
  final bool timelineDefault;

  /// What a new plan's Seasonal theme switch starts as.
  final bool seasonalThemeDefault;

  /// Pre-selected on a new game that came out on it (Add / edit entry);
  /// null means none.
  final String? defaultPlatform;

  /// The languages the owner reads, as ISO 639-1 codes, sorted (Settings ›
  /// Books › Languages you read): Coming soon lists only the book editions
  /// in them and the add-a-book search ranks those first. Null until the
  /// list is first written: the first run with the library writes the
  /// phone's system languages plus English (`defaultReadingLanguages`), so
  /// every device reads the same list from then on.
  final List<String>? languages;

  /// Which of a movie's release dates Coming soon and the details show
  /// (Settings › Movies › Release dates). `released` is never changed by it.
  final ReleaseDates releaseDates;

  /// The master switch of Settings › Upcoming releases: off, nothing is
  /// followed and nothing is fetched.
  final bool upcomingEnabled;

  /// Per kind, the ids of the follows the owner unticked although they are
  /// on by default ([FollowKind.defaultOn], and the creator active).
  final Map<FollowKind, Set<String>> unfollowed;

  /// Per kind, the ids the owner ticked although they are off by default:
  /// actors, and creators who are no longer active.
  final Map<FollowKind, Set<String>> followed;

  /// The rows of Library › Coming soon: everything upcoming the owner marked
  /// Not interested, by the row's key: an entry's id, `<show id>#<season>`
  /// for a season, a lookup id for a found release or a series part.
  final Set<String> notInterested;

  Set<String> unfollowedOf(FollowKind kind) => unfollowed[kind] ?? const {};

  Set<String> followedOf(FollowKind kind) => followed[kind] ?? const {};

  /// Whether the follow [id] of [kind] is on: on by default
  /// ([defaultOn]: the kind's default, and the creator still active) unless
  /// unticked, else off unless ticked.
  bool isFollowed(FollowKind kind, String id, {required bool defaultOn}) =>
      defaultOn
      ? !unfollowedOf(kind).contains(id)
      : followedOf(kind).contains(id);

  /// With the follow [id] of [kind] set [on], stored as the exception to
  /// its default ([defaultOn]) or removed from both lists when it is the
  /// default.
  AppSettings withFollow(
    FollowKind kind,
    String id, {
    required bool on,
    required bool defaultOn,
  }) {
    final exception = on != defaultOn;
    return copyWith(
      unfollowed: _put(unfollowed, kind, id, exception && !on),
      followed: _put(followed, kind, id, exception && on),
    );
  }

  static Map<FollowKind, Set<String>> _put(
    Map<FollowKind, Set<String>> all,
    FollowKind kind,
    String id,
    bool present,
  ) {
    final ids = {...all[kind] ?? const <String>{}};
    if (present) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    return {
      for (final e in all.entries)
        if (e.key != kind) e.key: e.value,
      if (ids.isNotEmpty) kind: ids,
    };
  }

  AppSettings copyWith({
    bool? timelineDefault,
    bool? seasonalThemeDefault,
    Object? defaultPlatform = _keep,
    List<String>? languages,
    ReleaseDates? releaseDates,
    bool? upcomingEnabled,
    Map<FollowKind, Set<String>>? unfollowed,
    Map<FollowKind, Set<String>>? followed,
    Set<String>? notInterested,
  }) => AppSettings(
    timelineDefault: timelineDefault ?? this.timelineDefault,
    seasonalThemeDefault: seasonalThemeDefault ?? this.seasonalThemeDefault,
    defaultPlatform: defaultPlatform == _keep
        ? this.defaultPlatform
        : defaultPlatform as String?,
    languages: languages ?? this.languages,
    releaseDates: releaseDates ?? this.releaseDates,
    upcomingEnabled: upcomingEnabled ?? this.upcomingEnabled,
    unfollowed: unfollowed ?? this.unfollowed,
    followed: followed ?? this.followed,
    notInterested: notInterested ?? this.notInterested,
  );

  /// Sentinel for [copyWith], so a null [defaultPlatform] can be set.
  static const _keep = Object();

  /// The canonical form: keys in this order, only the keys that differ from
  /// the defaults (`"default_platform": null` is such a key: None differs
  /// from PC), lists sorted. `version` is always written.
  Map<String, Object?> toJson() {
    const d = defaults;
    final games = <String, Object?>{
      if (defaultPlatform != d.defaultPlatform)
        'default_platform': defaultPlatform,
    };
    final books = <String, Object?>{
      if (languages case final languages?)
        'languages': [...languages.map((c) => c.toLowerCase()).toSet()]..sort(),
    };
    final movies = <String, Object?>{
      if (releaseDates != d.releaseDates) 'release_dates': releaseDates.key,
    };
    final upcoming = <String, Object?>{
      if (upcomingEnabled != d.upcomingEnabled) 'enabled': upcomingEnabled,
      if (unfollowed.values.any((s) => s.isNotEmpty))
        'unfollowed': _idsJson(unfollowed),
      if (followed.values.any((s) => s.isNotEmpty))
        'followed': _idsJson(followed),
      if (notInterested.isNotEmpty)
        'not_interested': [...notInterested]..sort(),
    };
    return {
      'version': version,
      if (timelineDefault != d.timelineDefault)
        'timeline_default': timelineDefault,
      if (seasonalThemeDefault != d.seasonalThemeDefault)
        'seasonal_theme_default': seasonalThemeDefault,
      if (games.isNotEmpty) 'games': games,
      if (books.isNotEmpty) 'books': books,
      if (movies.isNotEmpty) 'movies': movies,
      if (upcoming.isNotEmpty) 'upcoming': upcoming,
    };
  }

  static Map<String, List<String>> _idsJson(Map<FollowKind, Set<String>> ids) =>
      {
        for (final kind in FollowKind.values)
          if (ids[kind] case final set? when set.isNotEmpty)
            kind.key: [...set]..sort(),
      };

  static Map<FollowKind, Set<String>> _idsFromJson(Object? raw) => {
    if (raw is Map)
      for (final MapEntry(:key, :value) in raw.entries)
        if (FollowKind.byKey(key as String?) case final kind?
            when value is List && value.isNotEmpty)
          kind: {...value.whereType<String>()},
  };

  /// Reads [toJson]'s form. Anything missing or unknown, such as a key from a
  /// newer build, falls back to its default; unknown keys are dropped on the
  /// next save.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = defaults;
    final games = json['games'];
    final books = json['books'];
    final movies = json['movies'];
    final upcoming = json['upcoming'];
    final gamesMap = games is Map<String, Object?>
        ? games
        : const <String, Object?>{};
    final booksMap = books is Map<String, Object?>
        ? books
        : const <String, Object?>{};
    final moviesMap = movies is Map<String, Object?>
        ? movies
        : const <String, Object?>{};
    final upcomingMap = upcoming is Map<String, Object?>
        ? upcoming
        : const <String, Object?>{};
    final platform = gamesMap['default_platform'];
    return AppSettings(
      timelineDefault: switch (json['timeline_default']) {
        final bool on => on,
        _ => d.timelineDefault,
      },
      seasonalThemeDefault: switch (json['seasonal_theme_default']) {
        final bool on => on,
        _ => d.seasonalThemeDefault,
      },
      defaultPlatform: !gamesMap.containsKey('default_platform')
          ? d.defaultPlatform
          : platform is String
          ? platform
          : null,
      languages: switch (booksMap['languages']) {
        final List<Object?> codes => [
          for (final c in codes)
            if (c is String && c.isNotEmpty) c.toLowerCase(),
        ],
        _ => null,
      },
      releaseDates:
          ReleaseDates.byKey(moviesMap['release_dates'] as String?) ??
          d.releaseDates,
      upcomingEnabled: switch (upcomingMap['enabled']) {
        final bool on => on,
        _ => d.upcomingEnabled,
      },
      unfollowed: _idsFromJson(upcomingMap['unfollowed']),
      followed: _idsFromJson(upcomingMap['followed']),
      notInterested: switch (upcomingMap['not_interested']) {
        final List<Object?> keys => {
          for (final k in keys)
            if (k is String) k,
        },
        _ => const {},
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.timelineDefault == timelineDefault &&
      other.seasonalThemeDefault == seasonalThemeDefault &&
      other.defaultPlatform == defaultPlatform &&
      listEquals(other.languages, languages) &&
      other.releaseDates == releaseDates &&
      other.upcomingEnabled == upcomingEnabled &&
      _sameIds(other.unfollowed, unfollowed) &&
      _sameIds(other.followed, followed) &&
      setEquals(other.notInterested, notInterested);

  static bool _sameIds(
    Map<FollowKind, Set<String>> a,
    Map<FollowKind, Set<String>> b,
  ) {
    for (final kind in FollowKind.values) {
      if (!setEquals(a[kind] ?? const {}, b[kind] ?? const {})) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    timelineDefault,
    seasonalThemeDefault,
    defaultPlatform,
    languages == null ? null : Object.hashAll(languages!),
    releaseDates,
    upcomingEnabled,
    _idsHash(unfollowed),
    _idsHash(followed),
    Object.hashAllUnordered(notInterested),
  );

  static int _idsHash(Map<FollowKind, Set<String>> ids) => Object.hashAll([
    for (final kind in FollowKind.values)
      Object.hashAllUnordered(ids[kind] ?? const {}),
  ]);

  @override
  String toString() => 'AppSettings(${toJson()})';
}
