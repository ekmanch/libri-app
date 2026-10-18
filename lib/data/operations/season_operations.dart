import 'package:json_annotation/json_annotation.dart';

import '../models/entry.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import 'library_operation.dart';

part 'season_operations.g.dart';

/// The show for a season operation, or null when it is gone or not a show.
Entry? _show(Library library, String entryId) {
  final entry = library.entryById(entryId);
  return entry?.type == MediaType.shows ? entry : null;
}

Library _withSeasons(Library library, Entry show, List<Season> seasons) {
  final index = library.entries.indexWhere((e) => e.id == show.id);
  final entries = [...library.entries];
  entries[index] = show.copyWith(seasons: seasons.isEmpty ? null : seasons);
  return library.copyWith(entries: entries);
}

String _title(Library library, String entryId) =>
    library.entryById(entryId)?.title ?? entryId;

/// "season 3", "seasons 1–5", "seasons 2, 4 and 5".
String seasonsPhrase(List<int> numbers) {
  if (numbers.length == 1) return 'season ${numbers.single}';
  final sorted = [...numbers]..sort();
  final consecutive = sorted.last - sorted.first == sorted.length - 1;
  if (consecutive) return 'seasons ${sorted.first}–${sorted.last}';
  final head = sorted.sublist(0, sorted.length - 1).join(', ');
  return 'seasons $head and ${sorted.last}';
}

String _statusWord(EntryStatus? status) => switch (status) {
  null => 'not set',
  EntryStatus.want => 'want',
  EntryStatus.inProgress => 'in progress',
  EntryStatus.done => 'done',
  EntryStatus.dnf => 'DNF',
};

/// Sets one season's status, or clears it with null. Any status clears the
/// "new" mark. The show's own status never changes.
@JsonSerializable()
class SetSeasonStatus extends LibraryOperation {
  const SetSeasonStatus(this.entryId, this.season, this.status);

  factory SetSeasonStatus.fromJson(Map<String, Object?> json) =>
      _$SetSeasonStatusFromJson(json);

  Map<String, Object?> toJson() => _$SetSeasonStatusToJson(this);

  final String entryId;
  final int season;
  final EntryStatus? status;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null) return library;
    if (!seasons.any((s) => s.season == season)) return library;
    return _withSeasons(library, show, [
      for (final s in seasons)
        s.season == season
            ? s.copyWith(status: status, fresh: status == null ? s.fresh : null)
            : s,
    ]);
  }

  @override
  String summary(Library before) => status == null
      ? 'Clear the status of ${_title(before, entryId)} season $season'
      : 'Mark ${_title(before, entryId)} season $season '
            'as ${_statusWord(status)}';
}

/// Catch-up (A33): marks every season numbered below [before] Done. Later
/// seasons and the show's own status stay as they are.
@JsonSerializable()
class MarkSeasonsDone extends LibraryOperation {
  const MarkSeasonsDone(this.entryId, this.before);

  factory MarkSeasonsDone.fromJson(Map<String, Object?> json) =>
      _$MarkSeasonsDoneFromJson(json);

  Map<String, Object?> toJson() => _$MarkSeasonsDoneToJson(this);

  final String entryId;
  final int before;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null) return library;
    return _withSeasons(library, show, [
      for (final s in seasons)
        s.season < before
            ? s.copyWith(status: EntryStatus.done, fresh: null)
            : s,
    ]);
  }

  @override
  String summary(Library library) {
    final numbers = [
      for (final s in library.entryById(entryId)?.seasons ?? const <Season>[])
        if (s.season < before) s.season,
    ];
    final what = numbers.isEmpty ? 'earlier seasons' : seasonsPhrase(numbers);
    return 'Mark ${_title(library, entryId)} $what as done';
  }
}

/// Adds seasons fetched from the lookup. Only seasons numbered above the
/// show's highest are added, so a season removed in the form never comes
/// back, and re-applying after a sync conflict adds nothing twice. They go
/// at the end, which keeps the list in number order.
@JsonSerializable()
class AddSeasons extends LibraryOperation {
  const AddSeasons(this.entryId, this.seasons);

  factory AddSeasons.fromJson(Map<String, Object?> json) =>
      _$AddSeasonsFromJson(json);

  Map<String, Object?> toJson() => _$AddSeasonsToJson(this);

  final String entryId;
  final List<Season> seasons;

  List<Season> _added(Entry show) {
    final existing = show.seasons ?? const <Season>[];
    final highest = existing.isEmpty ? 0 : existing.last.season;
    final added = seasons.where((s) => s.season > highest).toList()
      ..sort((a, b) => a.season.compareTo(b.season));
    return added;
  }

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    if (show == null) return library;
    final added = _added(show);
    if (added.isEmpty) return library;
    return _withSeasons(library, show, [...?show.seasons, ...added]);
  }

  @override
  String summary(Library before) {
    final show = _show(before, entryId);
    final added = show == null ? seasons : _added(show);
    final numbers = [for (final s in added) s.season];
    final what = numbers.isEmpty ? 'seasons' : seasonsPhrase(numbers);
    return 'Add $what of ${_title(before, entryId)}';
  }
}
