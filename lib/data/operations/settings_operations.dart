import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/follow_kind.dart';

/// One small change to `settings.json`, the counterpart of
/// `LibraryOperation` for the settings (DESIGN.md section 8). Queued in
/// `pending.json` with the library's operations and sent as its own commit
/// whose message is the summary ("Unfollow J. K. Rowling"); re-applied to a
/// fresh copy after a conflict like any operation. Every operation is
/// tolerant and gives the settings back unchanged when nothing changes.
abstract class SettingsOperation {
  const SettingsOperation();

  AppSettings apply(AppSettings settings);

  /// A short account of the change in the imperative, the commit message
  /// when saving to GitHub.
  String summary(AppSettings before);

  /// The operation's own fields, for the queue (`operation_json.dart` adds
  /// the `op` key).
  Map<String, Object?> toJson();
}

/// Plans › New plan starts with the Timeline switch [on].
@immutable
class SetTimelineDefault extends SettingsOperation {
  const SetTimelineDefault(this.on);

  final bool on;

  factory SetTimelineDefault.fromJson(Map<String, Object?> json) =>
      SetTimelineDefault(json['on'] == true);

  @override
  AppSettings apply(AppSettings settings) =>
      settings.copyWith(timelineDefault: on);

  @override
  String summary(AppSettings before) =>
      'Turn ${on ? 'on' : 'off'} the timeline for new plans';

  @override
  Map<String, Object?> toJson() => {'on': on};
}

/// Plans › New plan starts with the Seasonal theme switch [on].
@immutable
class SetSeasonalThemeDefault extends SettingsOperation {
  const SetSeasonalThemeDefault(this.on);

  final bool on;

  factory SetSeasonalThemeDefault.fromJson(Map<String, Object?> json) =>
      SetSeasonalThemeDefault(json['on'] == true);

  @override
  AppSettings apply(AppSettings settings) =>
      settings.copyWith(seasonalThemeDefault: on);

  @override
  String summary(AppSettings before) =>
      'Turn ${on ? 'on' : 'off'} seasonal touches for new plans';

  @override
  Map<String, Object?> toJson() => {'on': on};
}

/// The default game platform (Settings), or none.
@immutable
class SetDefaultPlatform extends SettingsOperation {
  const SetDefaultPlatform(this.platform);

  final String? platform;

  factory SetDefaultPlatform.fromJson(Map<String, Object?> json) =>
      SetDefaultPlatform(json['platform'] as String?);

  @override
  AppSettings apply(AppSettings settings) =>
      settings.copyWith(defaultPlatform: platform);

  @override
  String summary(AppSettings before) => platform == null
      ? 'Clear the default platform'
      : 'Set default platform to $platform';

  @override
  Map<String, Object?> toJson() => {'platform': platform};
}

/// The master switch of Settings › Upcoming releases.
@immutable
class SetUpcomingEnabled extends SettingsOperation {
  const SetUpcomingEnabled(this.on);

  final bool on;

  factory SetUpcomingEnabled.fromJson(Map<String, Object?> json) =>
      SetUpcomingEnabled(json['on'] == true);

  @override
  AppSettings apply(AppSettings settings) =>
      settings.copyWith(upcomingEnabled: on);

  @override
  String summary(AppSettings before) =>
      'Turn ${on ? 'on' : 'off'} the checks for new releases';

  @override
  Map<String, Object?> toJson() => {'on': on};
}

/// Ticks or unticks one follow (Settings › Follow: authors; the follow mark
/// on a creator's tag in Library › Entry details). [defaultOn] is whether the
/// follow is on by default (the kind's default, and the creator active), so
/// the settings store only the exception; [name] is for the summary.
@immutable
class SetFollow extends SettingsOperation {
  const SetFollow(
    this.kind,
    this.id, {
    required this.name,
    required this.on,
    required this.defaultOn,
  });

  final FollowKind kind;
  final String id;
  final String name;
  final bool on;
  final bool defaultOn;

  factory SetFollow.fromJson(Map<String, Object?> json) => SetFollow(
    FollowKind.byKey(json['kind'] as String?) ?? FollowKind.authors,
    json['followId'] as String,
    name: json['name'] as String? ?? json['followId'] as String,
    on: json['on'] == true,
    defaultOn: json['defaultOn'] == true,
  );

  @override
  AppSettings apply(AppSettings settings) =>
      settings.withFollow(kind, id, on: on, defaultOn: defaultOn);

  @override
  String summary(AppSettings before) => '${on ? 'Follow' : 'Unfollow'} $name';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.key,
    // Not 'id': the queue's own key.
    'followId': id,
    'name': name,
    'on': on,
    'defaultOn': defaultOn,
  };
}

/// Follow all or Unfollow all on a kind's list: every follow in [defaults]
/// (id to whether it is on by default) set [on].
@immutable
class SetFollows extends SettingsOperation {
  const SetFollows(this.kind, this.defaults, {required this.on});

  final FollowKind kind;

  /// The follows to set, each with whether it is on by default.
  final Map<String, bool> defaults;
  final bool on;

  factory SetFollows.fromJson(Map<String, Object?> json) => SetFollows(
    FollowKind.byKey(json['kind'] as String?) ?? FollowKind.authors,
    {
      if (json['defaults'] case final Map<String, Object?> defaults)
        for (final e in defaults.entries) e.key: e.value == true,
    },
    on: json['on'] == true,
  );

  @override
  AppSettings apply(AppSettings settings) {
    var result = settings;
    for (final MapEntry(key: id, value: defaultOn) in defaults.entries) {
      result = result.withFollow(kind, id, on: on, defaultOn: defaultOn);
    }
    return result;
  }

  @override
  String summary(AppSettings before) =>
      '${on ? 'Follow' : 'Unfollow'} all ${kind.label.toLowerCase()}';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.key,
    'defaults': defaults,
    'on': on,
  };
}

/// Not interested on a row of Library › Coming soon: everything upcoming
/// ([hidden]), or the row shown again. [title] is for the summary.
@immutable
class SetNotInterested extends SettingsOperation {
  const SetNotInterested(this.key, {required this.title, this.hidden = true});

  /// The row's key: an entry's id, `<show id>#<season>` for a season, a
  /// lookup id for a found release or series part.
  final String key;
  final String title;
  final bool hidden;

  factory SetNotInterested.fromJson(Map<String, Object?> json) =>
      SetNotInterested(
        json['key'] as String,
        title: json['title'] as String? ?? json['key'] as String,
        hidden: json['hidden'] != false,
      );

  @override
  AppSettings apply(AppSettings settings) => settings.copyWith(
    notInterested: hidden
        ? {...settings.notInterested, key}
        : ({...settings.notInterested}..remove(key)),
  );

  @override
  String summary(AppSettings before) =>
      hidden ? 'Hide $title from upcoming' : 'Show $title in upcoming';

  @override
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'hidden': hidden,
  };
}

/// Forgets Not interested keys whose rows can no longer come back: the entry
/// is gone or released, the season is out, the recorded part or release has
/// come out or is in the library by now (`staleNotInterested`, run after
/// the daily checks), so the list does not grow for ever.
@immutable
class ForgetNotInterested extends SettingsOperation {
  const ForgetNotInterested(this.keys);

  final List<String> keys;

  factory ForgetNotInterested.fromJson(Map<String, Object?> json) =>
      ForgetNotInterested([
        for (final k in json['keys'] as List<Object?>? ?? const [])
          if (k is String) k,
      ]);

  @override
  AppSettings apply(AppSettings settings) => settings.copyWith(
    notInterested: {...settings.notInterested}..removeAll(keys),
  );

  @override
  String summary(AppSettings before) {
    final n = keys.where(before.notInterested.contains).length;
    return 'Forget $n hidden upcoming ${n == 1 ? 'row' : 'rows'} that came out';
  }

  @override
  Map<String, Object?> toJson() => {'keys': keys};
}

/// The commit message for several settings operations saved together.
/// Ticks of one kind in one direction read as one ("Unfollow 3 authors",
/// every name in the body); anything else is the first summary and how
/// many more, like the library's.
String settingsMessage(
  List<({SettingsOperation operation, String summary})> ops,
) {
  if (ops.length == 1) return ops.single.summary;
  final follows = ops.map((o) => o.operation).whereType<SetFollow>().toList();
  if (follows.length == ops.length &&
      follows.every(
        (f) => f.kind == follows.first.kind && f.on == follows.first.on,
      )) {
    final kind = follows.first.kind;
    final noun = kind == FollowKind.shows
        ? 'shows'
        : kind == FollowKind.series
        ? 'series'
        : kind.label.toLowerCase();
    final subject =
        '${follows.first.on ? 'Follow' : 'Unfollow'} ${ops.length} $noun';
    return '$subject\n\n${ops.map((o) => '- ${o.summary}').join('\n')}';
  }
  final others = ops.length - 1;
  final subject =
      '${ops.first.summary} and $others other change${others == 1 ? '' : 's'}';
  return '$subject\n\n${ops.map((o) => '- ${o.summary}').join('\n')}';
}
