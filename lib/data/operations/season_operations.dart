import 'package:json_annotation/json_annotation.dart';

import '../models/entry.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import '../models/season_span.dart';
import 'library_operation.dart';

part 'season_operations.g.dart';

/// The show (or anime series) for a season operation, or null when it is
/// gone or has no seasons to speak of ([Entry.usesSeasons]).
Entry? _show(Library library, String entryId) {
  final entry = library.entryById(entryId);
  return entry != null && entry.usesSeasons ? entry : null;
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

/// Catch-up (Show & seasons › All seasons, just added: catch up): marks every
/// season numbered below [before] Done. Later seasons and the show's own status
/// stay as they are.
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

/// Removes one season: one the lookup no longer lists (Show & seasons ›
/// Announced season dropped).
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

/// Keeps a season the lookup no longer lists (Show & seasons › Announced season
/// dropped): it is marked manual, so the daily check leaves it alone from then
/// on.
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

/// Re-splits an anime series' seasons (the daily check, once, for an anime
/// whose seasons came from the TMDB show it was matched to before they came
/// from AniList's chain): Frieren's one TMDB season of 38 episodes becomes
/// AniList's season 1 (episodes 1–28) and season 2 (29–38). [before] is
/// the old split and [after] the new one, each season with its episode
/// count. A new season takes the status of the old seasons its episodes
/// overlap (one status as it is; several as [Season.showStatus] combines
/// them), and a "new" mark when one of them had it; a new season beyond the
/// old episodes has no status and is marked new. Seasons marked manual stay
/// as they are, and a new season with a manual one's number is left out.
/// When the show's other seasons are no longer the old split's (the owner
/// edited them, or the re-split was applied already), nothing changes.
@JsonSerializable()
class ResplitSeasons extends LibraryOperation {
  const ResplitSeasons(this.entryId, this.before, this.after);

  factory ResplitSeasons.fromJson(Map<String, Object?> json) =>
      _$ResplitSeasonsFromJson(json);

  Map<String, Object?> toJson() => _$ResplitSeasonsToJson(this);

  final String entryId;
  final List<SeasonSpan> before;
  final List<SeasonSpan> after;

  /// Each season's episodes as a range, first and last (null: open to the
  /// end), counted from 1 over the whole show. A season after one whose
  /// count is not known has no range.
  static Map<int, (int, int?)> ranges(List<SeasonSpan> split) {
    final ranges = <int, (int, int?)>{};
    var next = 1;
    for (final s in [...split]..sort((a, b) => a.season.compareTo(b.season))) {
      final count = s.episodes;
      if (count == null) {
        ranges[s.season] = (next, null);
        break;
      }
      if (count <= 0) continue;
      ranges[s.season] = (next, next + count - 1);
      next += count;
    }
    return ranges;
  }

  static bool _overlaps((int, int?) a, (int, int?) b) =>
      (a.$2 == null || b.$1 <= a.$2!) && (b.$2 == null || a.$1 <= b.$2!);

  /// Whether [show]'s seasons other than manual ones are the old split's,
  /// and the new split is a different one.
  bool appliesTo(Entry show) {
    final own = {
      for (final s in show.seasons ?? const <Season>[])
        if (!s.isManual) s.season,
    };
    final old = {for (final s in before) s.season};
    if (own.isEmpty || !old.containsAll(own)) return false;
    final oldRanges = ranges(before);
    final newRanges = ranges(after);
    if (oldRanges.length != newRanges.length) return true;
    for (final MapEntry(:key, :value) in oldRanges.entries) {
      if (newRanges[key] != value) return true;
    }
    return false;
  }

  @override
  Library apply(Library library) {
    final show = _show(library, entryId);
    final seasons = show?.seasons;
    if (show == null || seasons == null || !appliesTo(show)) return library;
    final today = seasonClock();
    final manual = {
      for (final s in seasons)
        if (s.isManual) s.season: s,
    };
    final old = {
      for (final s in seasons)
        if (!s.isManual) s.season: s,
    };
    final oldRanges = ranges(before);
    final newRanges = ranges(after);
    final split = <Season>[];
    for (final span in [
      ...after,
    ]..sort((a, b) => a.season.compareTo(b.season))) {
      if (manual.containsKey(span.season)) continue;
      final range = newRanges[span.season];
      final overlapped = [
        if (range != null)
          for (final MapEntry(:key, :value) in oldRanges.entries)
            if (old[key] case final s? when _overlaps(range, value)) s,
      ];
      final withStatus = [
        for (final s in overlapped)
          if (s.status != null) Season(season: s.season, status: s.status),
      ];
      final status = withStatus.isEmpty
          ? null
          : Season.showStatus(withStatus, today);
      final fresh =
          overlapped.isEmpty || overlapped.any((s) => s.fresh == true);
      split.add(
        Season(
          season: span.season,
          released: span.released,
          status: status,
          fresh: fresh && status == null ? true : null,
        ),
      );
    }
    // A season with neither a date nor a status waits for the lookup to
    // date it, as when the daily check adds seasons.
    final listed = [
      for (final s in split)
        if (s.released != null || s.status != null) s,
      ...manual.values,
    ]..sort((a, b) => a.season.compareTo(b.season));
    return _withSeasons(library, show, listed);
  }

  @override
  String summary(Library before) =>
      'Split the seasons of ${_title(before, entryId)} as AniList does';
}
