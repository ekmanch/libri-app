import 'package:json_annotation/json_annotation.dart';

import '../models/entry.dart';
import '../models/entry_id.dart';
import '../models/entry_kind.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import '../models/track.dart';
import 'library_operation.dart';

part 'entry_operations.g.dart';

/// The entry's title for a summary, or its id when it is gone.
String _title(Library library, String entryId) =>
    library.entryById(entryId)?.title ?? entryId;

/// Mid-sentence status words: "want", "in progress", "done", "DNF".
String _statusWord(EntryStatus status) => switch (status) {
  EntryStatus.want => 'want',
  EntryStatus.inProgress => 'in progress',
  EntryStatus.done => 'done',
  EntryStatus.dnf => 'DNF',
};

/// [entry] with [status]. A show's (or anime series') status comes from
/// its seasons: one season takes the status; with more, every season that
/// is out does, so ticking a show in a plan marks what has aired Done.
Entry _withStatus(Entry entry, EntryStatus status) {
  final seasons = entry.seasons;
  if (!entry.usesSeasons || seasons == null || seasons.isEmpty) {
    return entry.copyWith(status: status);
  }
  final today = seasonClock();
  return entry.withSeasons([
    for (final s in seasons)
      seasons.length == 1 || s.isReleasedOn(today)
          ? s.copyWith(status: status, fresh: null)
          : s,
  ], today: today);
}

/// A show's status as its seasons give it; other entries as they are.
Entry _derived(Entry entry) =>
    entry.usesSeasons && (entry.seasons?.isNotEmpty ?? false)
    ? entry.withSeasons(entry.seasons)
    : entry;

/// Replaces the entry with the same id in place. Missing: unchanged.
Library _replaceEntry(Library library, Entry entry) {
  final index = library.entries.indexWhere((e) => e.id == entry.id);
  if (index < 0) return library;
  final entries = [...library.entries];
  entries[index] = entry;
  return library.copyWith(entries: entries);
}

@JsonSerializable()
class SetStatus extends LibraryOperation {
  const SetStatus(this.entryId, this.status);

  factory SetStatus.fromJson(Map<String, Object?> json) =>
      _$SetStatusFromJson(json);

  Map<String, Object?> toJson() => _$SetStatusToJson(this);

  final String entryId;
  final EntryStatus status;

  @override
  Library apply(Library library) {
    final entry = library.entryById(entryId);
    if (entry == null) return library;
    if (!EntryStatus.optionsForEntry(entry).contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'not allowed for ${entry.type.name}',
      );
    }
    return _replaceEntry(library, _withStatus(entry, status));
  }

  @override
  String summary(Library before) =>
      'Mark ${_title(before, entryId)} as ${_statusWord(status)}';
}

/// Sets an anime's kind, series or movie, when the lookup tells the daily
/// check which it is (an anime linked to AniList before kinds existed).
/// Only the kind changes; the seasons of a series come with [AddSeasons].
@JsonSerializable()
class SetKind extends LibraryOperation {
  const SetKind(this.entryId, this.kind);

  factory SetKind.fromJson(Map<String, Object?> json) =>
      _$SetKindFromJson(json);

  Map<String, Object?> toJson() => _$SetKindToJson(this);

  final String entryId;
  final EntryKind kind;

  @override
  Library apply(Library library) {
    final entry = library.entryById(entryId);
    if (entry == null) return library;
    final allowed = switch (entry.type) {
      MediaType.music => EntryKind.musicKinds,
      MediaType.anime => EntryKind.animeKinds,
      _ => const <EntryKind>[],
    };
    if (!allowed.contains(kind)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'not allowed for ${entry.type.name}',
      );
    }
    return _replaceEntry(library, entry.copyWith(kind: kind));
  }

  @override
  String summary(Library before) {
    final word = switch (kind) {
      EntryKind.album => 'an album',
      EntryKind.song => 'a song',
      EntryKind.series => 'a series',
      EntryKind.movie => 'a movie',
    };
    return 'Mark ${_title(before, entryId)} as $word';
  }
}

@JsonSerializable()
class SetRating extends LibraryOperation {
  const SetRating(this.entryId, this.rating)
    : assert(rating == null || (rating >= 1 && rating <= 10));

  factory SetRating.fromJson(Map<String, Object?> json) =>
      _$SetRatingFromJson(json);

  Map<String, Object?> toJson() => _$SetRatingToJson(this);

  final String entryId;

  /// 1 to 10, or null to clear.
  final int? rating;

  @override
  Library apply(Library library) {
    final entry = library.entryById(entryId);
    if (entry == null) return library;
    return _replaceEntry(library, entry.copyWith(rating: rating));
  }

  @override
  String summary(Library before) => rating == null
      ? 'Clear the rating of ${_title(before, entryId)}'
      : 'Rate ${_title(before, entryId)} $rating of 10';
}

/// Appends an entry. The caller builds the id with [EntryId.generate]; if
/// that id is taken by the time the operation runs (after a sync conflict),
/// a numeric suffix is added. Tags the entry uses must already exist in the
/// tag map (see [AddTag]).
@JsonSerializable()
class AddEntry extends LibraryOperation {
  const AddEntry(this.entry);

  factory AddEntry.fromJson(Map<String, Object?> json) =>
      _$AddEntryFromJson(json);

  Map<String, Object?> toJson() => _$AddEntryToJson(this);

  final Entry entry;

  @override
  Library apply(Library library) {
    final id = EntryId.unique(entry.id, library.entries.map((e) => e.id));
    return library.copyWith(
      entries: [
        ...library.entries,
        _derived(entry).copyWith(id: id),
      ],
    );
  }

  @override
  String summary(Library before) => 'Add ${entry.title}';
}

/// Replaces an entry in place, keeping its id and position.
@JsonSerializable()
class UpdateEntry extends LibraryOperation {
  const UpdateEntry(this.entry);

  factory UpdateEntry.fromJson(Map<String, Object?> json) =>
      _$UpdateEntryFromJson(json);

  Map<String, Object?> toJson() => _$UpdateEntryToJson(this);

  final Entry entry;

  @override
  Library apply(Library library) {
    if (library.entryById(entry.id) == null) return library;
    return _replaceEntry(library, _derived(entry)).withUnusedTagsRemoved();
  }

  @override
  String summary(Library before) => 'Edit ${entry.title}';
}

/// Removes an entry everywhere: from the list and from every plan.
@JsonSerializable()
class DeleteEntry extends LibraryOperation {
  const DeleteEntry(this.entryId);

  factory DeleteEntry.fromJson(Map<String, Object?> json) =>
      _$DeleteEntryFromJson(json);

  Map<String, Object?> toJson() => _$DeleteEntryToJson(this);

  final String entryId;

  @override
  Library apply(Library library) {
    if (library.entryById(entryId) == null) return library;
    return library
        .copyWith(
          entries: library.entries.where((e) => e.id != entryId).toList(),
          plans: [
            for (final plan in library.plans)
              plan.copyWith(
                items: plan.items.where((i) => i.entry != entryId).toList(),
              ),
          ],
        )
        .withUnusedTagsRemoved();
  }

  @override
  String summary(Library before) => 'Delete ${_title(before, entryId)}';
}

bool _sameTrack(Track a, Track b) =>
    a.id != null && b.id != null ? a.id == b.id : a.title == b.title;

/// Adds or replaces a rated track on an album entry. Tracks match by lookup
/// id when both have one, otherwise by title.
@JsonSerializable()
class RateTrack extends LibraryOperation {
  const RateTrack(this.entryId, this.track);

  factory RateTrack.fromJson(Map<String, Object?> json) =>
      _$RateTrackFromJson(json);

  Map<String, Object?> toJson() => _$RateTrackToJson(this);

  final String entryId;
  final Track track;

  @override
  Library apply(Library library) {
    if (track.rating < 1 || track.rating > 10) {
      throw ArgumentError.value(track.rating, 'rating', 'must be 1 to 10');
    }
    final entry = library.entryById(entryId);
    if (entry == null) return library;
    final tracks = [...?entry.tracks];
    final index = tracks.indexWhere((t) => _sameTrack(t, track));
    if (index < 0) {
      tracks.add(track);
    } else {
      tracks[index] = track;
    }
    return _replaceEntry(library, entry.copyWith(tracks: tracks));
  }

  @override
  String summary(Library before) =>
      'Rate ${track.title} on ${_title(before, entryId)} ${track.rating} of 10';
}

/// Removes a track's rating. When no rated tracks remain the `tracks` field
/// is dropped, since only rated tracks are stored.
@JsonSerializable()
class ClearTrackRating extends LibraryOperation {
  const ClearTrackRating(this.entryId, {this.trackId, this.title})
    : assert(trackId != null || title != null);

  factory ClearTrackRating.fromJson(Map<String, Object?> json) =>
      _$ClearTrackRatingFromJson(json);

  Map<String, Object?> toJson() => _$ClearTrackRatingToJson(this);

  final String entryId;
  final String? trackId;
  final String? title;

  @override
  Library apply(Library library) {
    final entry = library.entryById(entryId);
    if (entry == null || entry.tracks == null) return library;
    final probe = Track(title: title ?? '', id: trackId, rating: 1);
    final tracks = entry.tracks!.where((t) => !_sameTrack(t, probe)).toList();
    return _replaceEntry(
      library,
      entry.copyWith(tracks: tracks.isEmpty ? null : tracks),
    );
  }

  @override
  String summary(Library before) {
    var name = title;
    if (trackId != null) {
      for (final track in before.entryById(entryId)?.tracks ?? const []) {
        if (track.id == trackId) name = track.title;
      }
    }
    final album = _title(before, entryId);
    return name == null || name.isEmpty
        ? 'Clear a track rating on $album'
        : 'Clear the rating of $name on $album';
  }
}
