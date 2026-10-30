import 'package:flutter/foundation.dart';

import '../lookup/lookup_match.dart';
import '../models/follow_kind.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../storage/json_file.dart';
import 'creator_status.dart';

/// A creator as a provider knows them: its id for them, and whether they
/// are no longer active when the provider says (TMDB's `deathday`); null
/// [inactive] means active or not known.
typedef CreatorMatch = ({String providerId, Inactive? inactive});

/// A lookup that can follow creators for new releases (DESIGN.md 10c): TMDB
/// for directors, actors and studios' movies, Open Library for authors,
/// Deezer for artists, IGDB for studios' games, the fake for all. Every
/// method throws `LookupException` on failure.
abstract interface class CreatorLookup {
  /// The kinds of creator this lookup answers for.
  Set<FollowKind> get creatorKinds;

  /// The creator named [name] of [kind], or null when the provider has no
  /// one by that name.
  Future<CreatorMatch?> findCreator(FollowKind kind, String name);

  /// The releases of the creator [providerId] (from [findCreator]) that are
  /// still ahead on [today], or came out within the last thirty days, as
  /// matches a new entry can start from; the provider's own order.
  Future<List<LookupMatch>> creatorReleases(
    String providerId,
    FollowKind kind, {
    required DateTime today,
  });
}

/// A lookup that knows when people die and bands or studios dissolve, for
/// the "No longer active" group: Wikidata, asked for many names at once.
abstract interface class InactiveLookup {
  /// For each of [names] that it knows, why they are no longer active;
  /// a name that is missing is active or not known.
  Future<Map<String, Inactive>> inactiveOf(FollowKind kind, List<String> names);
}

/// Whether a release found for a creator is worth listing: still ahead on
/// [today] by the release rule, or out within the last thirty days.
bool isRecentOrAhead(Released? released, DateTime today) {
  if (released == null) return false;
  final from = released.availableFrom;
  final day = DateTime(today.year, today.month, today.day);
  return from.isAfter(day) ||
      !from.isBefore(day.subtract(const Duration(days: 30)));
}

/// A release the creator check found (Library › Coming soon: everything
/// upcoming, as an Add row; the home lists only what the owner entered),
/// kept on the device in `found_releases.json`, never in `library.json`.
@immutable
class FoundRelease {
  const FoundRelease({
    required this.kind,
    required this.creatorId,
    required this.creatorName,
    required this.match,
    required this.foundOn,
  });

  final FollowKind kind;

  /// The follow's id, so a release of a creator no longer followed is
  /// left out.
  final String creatorId;
  final String creatorName;

  /// The release as the lookup lists it: type, title, lookup id, date,
  /// creator, description, cover. Add to library starts the entry form from
  /// it, prefilled.
  final LookupMatch match;

  final DateTime foundOn;

  /// The row's key, which Not interested hides it by.
  String get key => match.source;

  factory FoundRelease.fromJson(Map<String, Object?> json) {
    final released = json['released'] as String?;
    return FoundRelease(
      kind: FollowKind.byKey(json['kind'] as String?) ?? FollowKind.authors,
      creatorId: json['creator'] as String,
      creatorName: json['creatorName'] as String? ?? '',
      match: LookupMatch(
        type: MediaType.values.byName(json['type'] as String),
        title: json['title'] as String,
        source: json['source'] as String,
        released: released == null ? null : Released.tryParse(released),
        creator: json['by'] as String?,
        description: json['description'] as String? ?? '',
        coverUrl: json['cover'] as String?,
        largeCoverUrl: json['largeCover'] as String?,
      ),
      foundOn: DateTime.parse(json['foundOn'] as String),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.key,
    'creator': creatorId,
    'creatorName': creatorName,
    'type': match.type.name,
    'title': match.title,
    'source': match.source,
    'released': match.released?.toString(),
    'by': match.creator,
    'description': match.description,
    'cover': match.coverUrl,
    'largeCover': match.largeCoverUrl,
    'foundOn': foundOn.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is FoundRelease &&
      other.kind == kind &&
      other.creatorId == creatorId &&
      other.creatorName == creatorName &&
      other.match == match &&
      other.foundOn == foundOn;

  @override
  int get hashCode => Object.hash(kind, creatorId, creatorName, match, foundOn);

  @override
  String toString() => 'FoundRelease(${kind.key}/$creatorId: ${match.title})';
}

/// Where the found releases are kept.
abstract class FoundReleaseStore {
  Future<List<FoundRelease>> read();

  Future<void> write(List<FoundRelease> releases);
}

/// `found_releases.json` under the cache folder: `{"releases": [...]}`. A
/// cleared cache means no releases until the next check.
class FileFoundReleaseStore implements FoundReleaseStore {
  FileFoundReleaseStore(this._file);

  final JsonFile _file;

  @override
  Future<List<FoundRelease>> read() async {
    final releases = (await _file.read())?['releases'];
    if (releases is! List) return const [];
    final result = <FoundRelease>[];
    for (final item in releases) {
      if (item is! Map<String, Object?>) continue;
      try {
        result.add(FoundRelease.fromJson(item));
      } on Object {
        // An unreadable record is left out; the next check writes it again.
      }
    }
    return result;
  }

  @override
  Future<void> write(List<FoundRelease> releases) => _file.write({
    'releases': [for (final r in releases) r.toJson()],
  });
}

class MemoryFoundReleaseStore implements FoundReleaseStore {
  MemoryFoundReleaseStore([List<FoundRelease>? releases])
    : _releases = releases ?? const [];

  List<FoundRelease> _releases;

  @override
  Future<List<FoundRelease>> read() async => _releases;

  @override
  Future<void> write(List<FoundRelease> releases) async => _releases = releases;
}
