import 'package:flutter/foundation.dart';

import '../lookup/season_check.dart';
import '../lookup/series_check.dart';
import '../models/app_settings.dart';
import '../models/creator_names.dart';
import '../models/entry.dart';
import '../models/entry_kind.dart';
import '../models/entry_status.dart';
import '../models/follow_kind.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/tag_category.dart';
import 'creator_status.dart';

/// One thing the app follows for new releases (Settings › Upcoming releases,
/// Follow: authors, Follow: actors), derived from the library: a show or
/// anime series with seasons, a series, or a creator (an author, artist,
/// director, studio or actor) behind the entries. Never typed.
@immutable
class Follow {
  const Follow({
    required this.kind,
    required this.id,
    required this.name,
    required this.detail,
    required this.entryIds,
    required this.followed,
    this.ticked = false,
    this.inactive,
    this.providerId,
  });

  final FollowKind kind;

  /// The id the settings store the follow by: an entry's id for a show, a
  /// series' key for a series, a tag for a tagged creator, the lowercase
  /// name for an artist.
  final String id;

  /// "J. K. Rowling", "Stranger Things", "The Lord of the Rings".
  final String name;

  /// What the library has: "3 books", "2 movies, 1 show", "3 seasons".
  final String detail;

  /// The entries the follow comes from.
  final List<String> entryIds;

  /// Whether the follow is on, after the settings.
  final bool followed;

  /// Whether the owner ticked it although it is off by default (an actor, a
  /// creator no longer active), so the check asks about them anyway.
  final bool ticked;

  /// Why the creator is no longer active (the "No longer active" group),
  /// or null.
  final Inactive? inactive;

  /// The provider's id for the creator, when it has been looked up.
  final String? providerId;

  bool get isActive => inactive == null;

  /// The key the device's creator records are kept under
  /// (`CreatorStatus.key`): "authors/stephen-king".
  String get key => '${kind.key}/$id';

  /// Whether the follow is on until the owner unticks it: the kind's
  /// default, and the creator active.
  bool get defaultOn => kind.defaultOn && isActive;

  /// The row's second line: the detail, or for the No longer active group
  /// "Died 2021 · Series still checked" (an author's series still get the
  /// series check) or "Died 2000 · Not checked".
  String get secondLine => switch (inactive) {
    null => detail,
    final inactive =>
      '${inactive.label} · '
          '${kind == FollowKind.authors ? 'Series still checked' : 'Not checked'}',
  };

  Follow copyWith({bool? followed, Inactive? inactive, String? providerId}) =>
      Follow(
        kind: kind,
        id: id,
        name: name,
        detail: detail,
        entryIds: entryIds,
        followed: followed ?? this.followed,
        ticked: ticked,
        inactive: inactive ?? this.inactive,
        providerId: providerId ?? this.providerId,
      );

  @override
  String toString() => 'Follow(${kind.key}: $name, ${followed ? 'on' : 'off'})';
}

/// The follows of every kind, as the library and the settings give them.
@immutable
class Follows {
  const Follows(this.byKind);

  final Map<FollowKind, List<Follow>> byKind;

  List<Follow> of(FollowKind kind) => byKind[kind] ?? const [];

  /// The active follows of [kind] that are on.
  List<Follow> followedOf(FollowKind kind) => [
    for (final f in of(kind))
      if (f.followed) f,
  ];

  /// The count on the kind's row (Settings › Upcoming releases): "119" when
  /// every active one is followed, "10 of 25" otherwise; the inactive ones
  /// count only while ticked.
  String countLabel(FollowKind kind) {
    final all = of(kind);
    final counted = all.where((f) => f.isActive || f.followed).length;
    final followed = all.where((f) => f.followed).length;
    return followed == counted ? '$followed' : '$followed of $counted';
  }

  /// "10 of 25 followed" under a kind's title: the followed of all of them,
  /// the inactive ones included.
  String followedLabel(FollowKind kind) {
    final all = of(kind);
    return '${all.where((f) => f.followed).length} of ${all.length} followed';
  }

  /// The active follows of [kind] with their defaults, for Follow all and
  /// Unfollow all (the No longer active ones are left alone).
  Map<String, bool> activeDefaults(FollowKind kind) => {
    for (final f in of(kind))
      if (f.isActive) f.id: f.defaultOn,
  };

  /// Whether Follow all or Unfollow all is offered: Unfollow all while more
  /// than half of the active follows are on.
  bool mostFollowed(FollowKind kind) {
    final active = of(kind).where((f) => f.isActive).toList();
    return active.where((f) => f.followed).length > active.length / 2;
  }

  /// How many kinds have at least one follow on, of the seven ("6 of 7
  /// kinds" on the Settings row).
  int get kindsFollowed =>
      FollowKind.values.where((k) => followedOf(k).isNotEmpty).length;

  /// The follow of [kind] with [id], or null.
  Follow? find(FollowKind kind, String id) {
    for (final f in of(kind)) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// The id an artist is followed by: the name in lowercase, so names that
/// differ only in case are one artist (as the music list groups them).
String artistFollowId(String name) => name.trim().toLowerCase();

/// Names that are not an artist (the music list's own two).
const _notArtists = {'various artists', 'unknown artist', ''};

/// Derives every follow from [library] (DESIGN.md 10c), the settings saying
/// which are on, and [statuses] (the device's creator records) saying which
/// creators are no longer active:
///
/// - Shows and anime: every show, and anime series, linked to a lookup
///   whose status is not DNF (the season check's own rule).
/// - Series and collections: every series with a part Done or In progress
///   (the series check's rule).
/// - Authors, directors, studios, actors: the tags of that category, each
///   with the entries that carry the tag in that role; a creator is listed
///   while at least one of their entries is not DNF.
/// - Artists: the album artists of albums and songs.
Follows deriveFollows(
  Library library,
  AppSettings settings, {
  Map<String, CreatorStatus> statuses = const {},
}) {
  final result = <FollowKind, List<Follow>>{};
  for (final kind in FollowKind.values) {
    final follows = switch (kind) {
      FollowKind.shows => _shows(library),
      FollowKind.series => _series(library),
      FollowKind.artists => _artists(library),
      _ => _tagged(library, kind, kind.category!),
    };
    result[kind] = [
      for (final f in follows)
        _withSettings(f, settings, statuses['${kind.key}/${f.id}']),
    ]..sort(_byName);
  }
  return Follows(result);
}

Follow _withSettings(Follow f, AppSettings settings, CreatorStatus? status) {
  final inactive = status?.inactive;
  final defaultOn = f.kind.defaultOn && inactive == null;
  return Follow(
    kind: f.kind,
    id: f.id,
    name: f.name,
    detail: f.detail,
    entryIds: f.entryIds,
    inactive: inactive,
    providerId: status?.providerId,
    followed: settings.isFollowed(f.kind, f.id, defaultOn: defaultOn),
    ticked: settings.followedOf(f.kind).contains(f.id),
  );
}

int _byName(Follow a, Follow b) {
  final c = _sortKey(a.name).compareTo(_sortKey(b.name));
  return c != 0 ? c : a.id.compareTo(b.id);
}

String _sortKey(String name) {
  var key = name.trim().toLowerCase();
  if (key.startsWith('the ')) key = key.substring(4).trimLeft();
  return key;
}

Iterable<Follow> _shows(Library library) sync* {
  for (final entry in library.entries) {
    if (!SeasonCheck.isAsked(entry) || entry.status == EntryStatus.dnf) {
      continue;
    }
    final seasons = entry.seasons?.length ?? 0;
    yield Follow(
      kind: FollowKind.shows,
      id: entry.id,
      name: entry.title,
      detail: seasons == 0
          ? 'No seasons yet'
          : '$seasons ${seasons == 1 ? 'season' : 'seasons'}',
      entryIds: [entry.id],
      followed: true,
    );
  }
}

Iterable<Follow> _series(Library library) sync* {
  for (final MapEntry(key: key, value: parts) in SeriesCheck.seriesOf(
    library,
  ).entries) {
    if (!SeriesCheck.isFollowed(parts)) continue;
    final first = parts.first;
    yield Follow(
      kind: FollowKind.series,
      id: key,
      name: first.series!.name,
      detail: '${_count(first.type, parts.length)} in your library',
      entryIds: [for (final e in parts) e.id],
      followed: true,
    );
  }
}

Iterable<Follow> _artists(Library library) sync* {
  final byId = <String, List<Entry>>{};
  final names = <String, String>{};
  for (final entry in library.entries) {
    if (entry.type != MediaType.music) continue;
    final name = (entry.creator ?? '').trim();
    final id = artistFollowId(name);
    if (_notArtists.contains(id)) continue;
    names.putIfAbsent(id, () => name);
    byId.putIfAbsent(id, () => []).add(entry);
  }
  for (final MapEntry(key: id, value: entries) in byId.entries) {
    final albums = entries.where((e) => e.kind != EntryKind.song).length;
    final songs = entries.length - albums;
    yield Follow(
      kind: FollowKind.artists,
      id: id,
      name: names[id]!,
      detail: [
        if (albums > 0) '$albums ${albums == 1 ? 'album' : 'albums'}',
        if (songs > 0) '$songs ${songs == 1 ? 'song' : 'songs'}',
      ].join(', '),
      entryIds: [for (final e in entries) e.id],
      followed: true,
    );
  }
}

Iterable<Follow> _tagged(
  Library library,
  FollowKind kind,
  TagCategory category,
) sync* {
  for (final tag in library.tags[category] ?? const <String>[]) {
    final entries = [
      for (final e in library.entries)
        if (e.hasTagAs(tag, category)) e,
    ];
    if (entries.isEmpty || entries.every((e) => e.status == EntryStatus.dnf)) {
      continue;
    }
    yield Follow(
      kind: kind,
      id: tag,
      name: tagDisplayName(tag, library),
      detail: _countsByType(entries),
      entryIds: [for (final e in entries) e.id],
      followed: true,
    );
  }
}

/// "2 movies, 1 show", in type order.
String _countsByType(List<Entry> entries) {
  final parts = <String>[];
  for (final type in MediaType.values) {
    final n = entries.where((e) => e.type == type).length;
    if (n > 0) parts.add(_count(type, n));
  }
  return parts.join(', ');
}

String _count(MediaType type, int n) {
  final (one, many) = switch (type) {
    MediaType.movies => ('movie', 'movies'),
    MediaType.shows => ('show', 'shows'),
    MediaType.books => ('book', 'books'),
    MediaType.games => ('game', 'games'),
    MediaType.music => ('album', 'albums'),
    MediaType.anime => ('anime', 'anime'),
  };
  return '$n ${n == 1 ? one : many}';
}
