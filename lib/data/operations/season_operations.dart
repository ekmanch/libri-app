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

/// The show with [seasons] and the status they give, in its place.
Library _withSeasons(Library library, Entry show, List<Season> seasons) {
  final index = library.entries.indexWhere((e) => e.id == show.id);
  final entries = [...library.entries];
  entries[index] = show.withSeasons(seasons);
  return library.copyWith(entries: entries);
}

/// Carries a show's old status into seasons that have none (the move to
/// seasons): Want or Done goes to every season that is out; In progress or
/// DNF goes to the latest one out, with the earlier ones Done. One season
/// takes the status whether it is out or not. Seasons with any status set
/// are left as they are.
List<Season> carryOverStatus(
  List<Season> seasons,
  EntryStatus status,
  DateTime today,
) {
  if (seasons.isEmpty || seasons.any((s) => s.status != null)) return seasons;
  if (seasons.length == 1) return [seasons.single.copyWith(status: status)];
  final out = [
    for (final s in seasons)
      if (s.isReleasedOn(today)) s.season,
  ];
  if (out.isEmpty) return seasons;
  final latest = out.last;
  final whole = status == EntryStatus.want || status == EntryStatus.done;
  return [
    for (final s in seasons)
      if (!out.contains(s.season))
        s
      else if (whole || s.season == latest)
        s.copyWith(status: status)
      else
        s.copyWith(status: EntryStatus.done),
  ];
}

/// Whether [entry] is a show still in the shape from before seasons: a
/// date of its own, or no seasons and nothing to fetch them from. A show
/// linked to TMDB with no seasons yet waits for the daily check, which
/// fills it in and carries its status over ([AddSeasons]).
bool needsSeasonMove(Entry entry) {
  if (entry.type != MediaType.shows) return false;
  final empty = entry.seasons?.isEmpty ?? true;
  final fetchable = entry.source?.startsWith('tmdb:tv:') ?? false;
  if (empty) return !fetchable;
  return entry.released != null;
}

/// The move to seasons, for every show still in the old shape
/// ([needsSeasonMove]): the show's own date is dropped; a show without
/// seasons gets a Season 1 with that date and its status, marked manual;
/// one with seasons none of which has a status gets the old status carried
/// over ([carryOverStatus]).
@JsonSerializable()
class MoveShowsToSeasons extends LibraryOperation {
  const MoveShowsToSeasons();

  factory MoveShowsToSeasons.fromJson(Map<String, Object?> json) =>
      _$MoveShowsToSeasonsFromJson(json);

  Map<String, Object?> toJson() => _$MoveShowsToSeasonsToJson(this);

  @override
  Library apply(Library library) {
    if (!library.entries.any(needsSeasonMove)) return library;
    final today = seasonClock();
    return library.copyWith(
      entries: [
        for (final e in library.entries)
          if (!needsSeasonMove(e))
            e
          else if (e.seasons?.isEmpty ?? true)
            e.copyWith(released: null).withSeasons([
              Season(
                season: 1,
                released: e.released,
                status: e.status,
                manual: true,
              ),
            ], today: today)
          else
            e
                .copyWith(released: null)
                .withSeasons(
                  carryOverStatus(e.seasons!, e.status, today),
                  today: today,
                ),
      ],
    );
  }

  @override
  String summary(Library before) => 'Move show dates and statuses into seasons';
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

/// Adds seasons fetched from the lookup. A show that had none drops its
/// own date and has its status carried over ([carryOverStatus]). Only
/// seasons numbered above the show's highest are added, so a season
/// removed in the form never comes back, and re-applying after a sync
/// conflict adds nothing twice. They go at the end, which keeps the list
/// in number order.
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
    if (show.seasons?.isEmpty ?? true) {
      // The first seasons of a show from before seasons: its date goes,
      // its status is carried over.
      final today = seasonClock();
      return _withSeasons(
        library,
        show.copyWith(released: null),
        carryOverStatus(added, show.status, today),
      );
    }
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

/// Puts back a show's seasons as they were, such as after unticking a plan
/// item that marked them Done.
@JsonSerializable()
class SetSeasons extends LibraryOperation {
  const SetSeasons(this.entryId, this.seasons);

  factory SetSeasons.fromJson(Map<String, Object?> json) =>
      _$SetSeasonsFromJson(json);

  Map<String, Object?> toJson() => _$SetSeasonsToJson(this);

  final String entryId;
  final List<Season> seasons;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    if (show == null) return library;
    return _withSeasons(library, show, seasons);
  }

  @override
  String summary(Library before) =>
      'Set the seasons of ${_title(before, entryId)}';
}

/// Removes one season: one the lookup no longer lists (A36).
@JsonSerializable()
class RemoveSeason extends LibraryOperation {
  const RemoveSeason(this.entryId, this.season);

  factory RemoveSeason.fromJson(Map<String, Object?> json) =>
      _$RemoveSeasonFromJson(json);

  Map<String, Object?> toJson() => _$RemoveSeasonToJson(this);

  final String entryId;
  final int season;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null) return library;
    if (!seasons.any((s) => s.season == season)) return library;
    return _withSeasons(library, show, [
      for (final s in seasons)
        if (s.season != season) s,
    ]);
  }

  @override
  String summary(Library before) =>
      'Remove season $season of ${_title(before, entryId)}';
}

/// Keeps a season the lookup no longer lists (A36): it is marked manual,
/// so the daily check leaves it alone from then on.
@JsonSerializable()
class KeepSeason extends LibraryOperation {
  const KeepSeason(this.entryId, this.season);

  factory KeepSeason.fromJson(Map<String, Object?> json) =>
      _$KeepSeasonFromJson(json);

  Map<String, Object?> toJson() => _$KeepSeasonToJson(this);

  final String entryId;
  final int season;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null) return library;
    if (!seasons.any((s) => s.season == season)) return library;
    return _withSeasons(library, show, [
      for (final s in seasons)
        s.season == season ? s.copyWith(manual: true) : s,
    ]);
  }

  @override
  String summary(Library before) =>
      'Keep season $season of ${_title(before, entryId)}';
}

/// Writes the status a show's seasons give, when a season coming out has
/// changed it (the daily check).
@JsonSerializable()
class RefreshShowStatus extends LibraryOperation {
  const RefreshShowStatus(this.entryId);

  factory RefreshShowStatus.fromJson(Map<String, Object?> json) =>
      _$RefreshShowStatusFromJson(json);

  Map<String, Object?> toJson() => _$RefreshShowStatusToJson(this);

  final String entryId;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null) return library;
    return _withSeasons(library, show, seasons);
  }

  @override
  String summary(Library before) =>
      'Update the status of ${_title(before, entryId)} from its seasons';
}

/// Updates the dates of seasons not out yet that the lookup now dates
/// differently ("Coming 2027" becomes "Coming Mar 4, 2027"). [dates] holds
/// each season's number and new date; seasons added in the form are left
/// alone.
@JsonSerializable()
class SetSeasonDates extends LibraryOperation {
  const SetSeasonDates(this.entryId, this.dates);

  factory SetSeasonDates.fromJson(Map<String, Object?> json) =>
      _$SetSeasonDatesFromJson(json);

  Map<String, Object?> toJson() => _$SetSeasonDatesToJson(this);

  final String entryId;
  final List<Season> dates;

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null) return library;
    final byNumber = {for (final d in dates) d.season: d.released};
    return _withSeasons(library, show, [
      for (final s in seasons)
        byNumber.containsKey(s.season) && !s.isManual
            ? s.copyWith(released: byNumber[s.season])
            : s,
    ]);
  }

  @override
  String summary(Library before) =>
      'Update the season dates of ${_title(before, entryId)}';
}
