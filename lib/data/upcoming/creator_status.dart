import 'package:flutter/foundation.dart';

import '../models/follow_kind.dart';
import '../storage/json_file.dart';

/// What the lookups know about a followed creator, kept on the device
/// (`creator_status.json` under the cache folder, never in `library.json`):
/// the provider's id for them, so their releases can be asked for without a
/// search each time, and whether they are no longer active (Settings ›
/// Follow: authors, "No longer active": Wikidata's date of death or
/// dissolution, TMDB's `deathday`). A creator's record is looked up when
/// they first appear and asked again after [recheckAfter].
@immutable
class CreatorStatus {
  const CreatorStatus({
    required this.kind,
    required this.id,
    this.providerId,
    this.inactive,
    required this.checkedOn,
  });

  /// How long an active creator's record stands before it is asked again.
  static const recheckAfter = Duration(days: 90);

  final FollowKind kind;

  /// The follow's id (a tag, an artist's name key).
  final String id;

  /// The provider's id for the creator ("tmdb:person:287", "wikidata:Q42",
  /// "deezer:artist:27", "openlibrary:OL23919A", "igdb:company:70"), or
  /// null when none was found.
  final String? providerId;

  /// Why the creator is no longer active, or null while active (or not
  /// known).
  final Inactive? inactive;

  final DateTime checkedOn;

  /// The record's key in the store.
  String get key => '${kind.key}/$id';

  bool isStaleOn(DateTime today) =>
      inactive == null && !today.isBefore(checkedOn.add(recheckAfter));

  factory CreatorStatus.fromJson(Map<String, Object?> json) => CreatorStatus(
    kind: FollowKind.byKey(json['kind'] as String?) ?? FollowKind.authors,
    id: json['id'] as String,
    providerId: json['providerId'] as String?,
    inactive: switch (json['inactive']) {
      final Map<String, Object?> inactive => Inactive.fromJson(inactive),
      _ => null,
    },
    checkedOn: DateTime.parse(json['checkedOn'] as String),
  );

  Map<String, Object?> toJson() => {
    'kind': kind.key,
    'id': id,
    'providerId': providerId,
    if (inactive case final inactive?) 'inactive': inactive.toJson(),
    'checkedOn': _day(checkedOn),
  };

  static String _day(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is CreatorStatus &&
      other.kind == kind &&
      other.id == id &&
      other.providerId == providerId &&
      other.inactive == inactive &&
      other.checkedOn == checkedOn;

  @override
  int get hashCode => Object.hash(kind, id, providerId, inactive, checkedOn);
}

/// Why a creator is no longer active: died (a person) or disbanded (a band)
/// or dissolved (a studio), and the year when known.
@immutable
class Inactive {
  const Inactive(this.reason, {this.year});

  final InactiveReason reason;
  final int? year;

  /// "Died 2021", "Disbanded", "Dissolved 2010".
  String get label => year == null ? reason.word : '${reason.word} $year';

  factory Inactive.fromJson(Map<String, Object?> json) => Inactive(
    InactiveReason.values.byName(json['reason'] as String),
    year: json['year'] as int?,
  );

  Map<String, Object?> toJson() => {
    'reason': reason.name,
    if (year != null) 'year': year,
  };

  @override
  bool operator ==(Object other) =>
      other is Inactive && other.reason == reason && other.year == year;

  @override
  int get hashCode => Object.hash(reason, year);

  @override
  String toString() => label;
}

enum InactiveReason {
  died('Died'),
  disbanded('Disbanded'),
  dissolved('Dissolved');

  const InactiveReason(this.word);

  final String word;
}

/// Where the creator records are kept.
abstract class CreatorStatusStore {
  Future<Map<String, CreatorStatus>> read();

  Future<void> write(Map<String, CreatorStatus> statuses);
}

/// `creator_status.json` under the cache folder: `{"creators": [...]}`. A
/// cleared cache means the creators are looked up again.
class FileCreatorStatusStore implements CreatorStatusStore {
  FileCreatorStatusStore(this._file);

  final JsonFile _file;

  @override
  Future<Map<String, CreatorStatus>> read() async {
    final creators = (await _file.read())?['creators'];
    if (creators is! List) return const {};
    final result = <String, CreatorStatus>{};
    for (final item in creators) {
      if (item is! Map<String, Object?>) continue;
      try {
        final status = CreatorStatus.fromJson(item);
        result[status.key] = status;
      } on Object {
        // An unreadable record is left out; the next check writes it again.
      }
    }
    return result;
  }

  @override
  Future<void> write(Map<String, CreatorStatus> statuses) => _file.write({
    'creators': [
      for (final key in statuses.keys.toList()..sort()) statuses[key]!.toJson(),
    ],
  });
}

class MemoryCreatorStatusStore implements CreatorStatusStore {
  MemoryCreatorStatusStore([Map<String, CreatorStatus>? statuses])
    : _statuses = statuses ?? {};

  Map<String, CreatorStatus> _statuses;

  @override
  Future<Map<String, CreatorStatus>> read() async => _statuses;

  @override
  Future<void> write(Map<String, CreatorStatus> statuses) async =>
      _statuses = statuses;
}
