import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../storage/json_file.dart';
import '../upcoming/check_control.dart';
import '../upcoming/creator_lookup.dart';
import 'check_day_store.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'movie_dates.dart';
import 'lookup_source.dart';
import 'series_service.dart';
import 'text_clean.dart';

/// A part of a series the owner follows whose release is still ahead, as
/// the daily check found it (for Library › Coming soon: everything;
/// the home's Coming soon lists only entries set Want): the series
/// as the library's entry names it, a part in the library the series page
/// opens by, and the part as the lookup lists it. Kept on the device in
/// `upcoming_parts.json`, never in `library.json`. The reader drops the ones
/// that are in the library by now, hidden by the owner, or of a series no
/// longer followed.
@immutable
class UpcomingPart {
  const UpcomingPart({
    required this.type,
    required this.seriesName,
    required this.entryId,
    required this.title,
    required this.released,
    this.number,
    this.source,
    this.cover,
    this.extra = false,
  });

  final MediaType type;

  /// The series name as the library's entries carry it.
  final String seriesName;

  /// A part of the series in the library, whose series page shows this one.
  final String entryId;

  final String title;
  final Released released;
  final int? number;

  /// The part's lookup id, by which a library entry is matched to it, and
  /// which Choose what to show hides it by.
  final String? source;

  /// The part's cover image at the size the cache keeps, as the lookup's
  /// list carried it when the check ran; null while the title has no art
  /// yet, so the add sheet shows the placeholder. The image is fetched when
  /// the sheet opens, never by the check, and each check records the URL
  /// again, so a cover that appears closer to release is picked up.
  final String? cover;

  /// Whether the automatic rules count the part as an extra, hidden until
  /// the owner shows it.
  final bool extra;

  /// The key Choose what to show hides the part by: its lookup id, else its
  /// title (as `seriesPartKey` in `series.dart`).
  String get partKey => source ?? 'title:${titleKey(title)}';

  factory UpcomingPart.fromJson(Map<String, Object?> json) => UpcomingPart(
    type: MediaType.values.byName(json['type'] as String),
    seriesName: json['series'] as String,
    entryId: json['entry'] as String,
    title: json['title'] as String,
    released: Released.parse(json['released'] as String),
    number: json['number'] as int?,
    source: json['source'] as String?,
    cover: json['cover'] as String?,
    extra: json['extra'] == true,
  );

  Map<String, Object?> toJson() => {
    'type': type.name,
    'series': seriesName,
    'entry': entryId,
    'title': title,
    'released': released.toString(),
    'number': number,
    'source': source,
    'cover': ?cover,
    if (extra) 'extra': true,
  };

  @override
  bool operator ==(Object other) =>
      other is UpcomingPart &&
      other.type == type &&
      other.seriesName == seriesName &&
      other.entryId == entryId &&
      other.title == title &&
      other.released == released &&
      other.number == number &&
      other.source == source &&
      other.cover == cover &&
      other.extra == extra;

  @override
  int get hashCode => Object.hash(
    type,
    seriesName,
    entryId,
    title,
    released,
    number,
    source,
    cover,
  );

  @override
  String toString() => 'UpcomingPart($seriesName: $title, $released)';
}

/// Where the upcoming parts the daily check found are kept.
abstract class UpcomingPartsStore {
  Future<List<UpcomingPart>> read();

  Future<void> write(List<UpcomingPart> parts);
}

/// `upcoming_parts.json` under the cache folder: `{"parts": [...]}`. A
/// cleared cache means no recorded parts until the next check.
class FileUpcomingPartsStore implements UpcomingPartsStore {
  FileUpcomingPartsStore(this._file);

  final JsonFile _file;

  @override
  Future<List<UpcomingPart>> read() async {
    final parts = (await _file.read())?['parts'];
    if (parts is! List) return const [];
    final result = <UpcomingPart>[];
    for (final item in parts) {
      if (item is! Map<String, Object?>) continue;
      try {
        result.add(UpcomingPart.fromJson(item));
      } on Object {
        // An unreadable part is left out; the next check writes it again.
      }
    }
    return result;
  }

  @override
  Future<void> write(List<UpcomingPart> parts) => _file.write({
    'parts': [for (final p in parts) p.toJson()],
  });
}

class MemoryUpcomingPartsStore implements UpcomingPartsStore {
  MemoryUpcomingPartsStore([List<UpcomingPart>? parts])
    : _parts = parts ?? const [];

  List<UpcomingPart> _parts;

  @override
  Future<List<UpcomingPart>> read() async => _parts;

  @override
  Future<void> write(List<UpcomingPart> parts) async => _parts = parts;
}

/// The daily check of the series the owner follows (Library › Home: Coming
/// soon). A series is followed when a part of it in the library is Done or
/// In progress: something of it was read, watched or played. Once a day
/// the check asks the lookup for each followed series' parts, through
/// [SeriesService.refresh] (a list with a part still to come is fetched
/// again daily, the rest weekly), and records every part whose release is
/// still ahead in [upcoming], for Library › Coming soon: everything
/// to show. Nothing is written to
/// `library.json`.
///
/// Offline or rate limited, the lookup is not asked further; the stored
/// lists still give the record, and the day is not recorded, so the next
/// open tries again.
class SeriesCheck {
  SeriesCheck({
    required this.series,
    required this.store,
    required this.upcoming,
  });

  final SeriesService series;
  final CheckDayStore store;
  final UpcomingPartsStore upcoming;

  LookupService get lookups => series.lookups;

  /// How long after its listed release a book part is still asked for its
  /// edition in the languages read.
  static const editionWindow = 365;

  bool _running = false;

  /// Whether the series [parts] belong to is followed: a part of it in the
  /// library is Done or In progress.
  static bool isFollowed(Iterable<Entry> parts) => parts.any(
    (e) => e.status == EntryStatus.done || e.status == EntryStatus.inProgress,
  );

  /// The library's series by type and name (compared like a title), each
  /// with its parts in library order.
  static Map<String, List<Entry>> seriesOf(Library library) {
    final groups = <String, List<Entry>>{};
    for (final entry in library.entries) {
      final name = entry.series?.name;
      if (name == null || !entry.canHaveSeries) continue;
      groups
          .putIfAbsent('${entry.type.name}/${titleKey(name)}', () => [])
          .add(entry);
    }
    return groups;
  }

  /// Runs the check when it is due. True when the record of upcoming parts
  /// was written, so the home reads it again.
  /// Runs the check when it is due today (always with [force]), asking the
  /// lookup about every followed series, or with [include] only those it
  /// says (by the key of [seriesOf]); the rest keep their stored lists.
  /// A book part is recorded only when it has an edition in the
  /// [languages] the owner reads, dated by that edition (DESIGN.md 10c);
  /// the series page keeps listing it. [control] hears of each series
  /// asked and can stop the run, which then records no day.
  Future<bool> run(
    Library library,
    DateTime now, {
    bool force = false,
    bool Function(String key, List<Entry> parts)? include,
    Set<String> languages = const {},
    CheckControl? control,
  }) async {
    if (_running) return false;
    final today = DateTime(now.year, now.month, now.day);
    if (!force && !checkDueOn(await store.lastRun(), now)) return false;
    final ctl = control ?? CheckControl.none;
    _running = true;
    try {
      final found = <UpcomingPart>[];
      var complete = true;
      for (final MapEntry(:key, value: parts) in seriesOf(library).entries) {
        if (!isFollowed(parts)) continue;
        final asked = include == null || include(key, parts);
        if (asked && ctl.cancelled) complete = false;
        // The part the lookup knows best: one linked to it, else the first.
        final through = parts.firstWhere(
          (e) => e.source != null,
          orElse: () => parts.first,
        );
        final result = await series.refresh(
          through,
          now: now,
          askLookup: asked && complete,
        );
        if (asked && complete) ctl.tick();
        final listed = result.parts;
        if (result.failure case final failure?) {
          if (failure.failure == LookupFailure.offline ||
              failure.failure == LookupFailure.rateLimited ||
              failure.isTransient) {
            complete = false;
          }
        }
        if (listed == null) continue;
        for (final part in listed.parts) {
          var released = seriesPartRelease(part);
          if (released == null) continue;
          final out = released.isReleasedOn(today);
          // A book out within the last year may still be to come in the
          // languages read: an English volume follows the Japanese one by
          // months.
          final asksEdition =
              through.type == MediaType.books &&
              languages.isNotEmpty &&
              part.source != null &&
              (!out || isRecentOrAhead(released, today, days: editionWindow));
          if (out && !asksEdition) continue;
          if (asksEdition) {
            final edition = await _edition(part.source!, languages);
            if (edition != null) {
              if (!edition.inLanguages) continue;
              released = edition.released ?? released;
            }
            if (released.isReleasedOn(today)) continue;
          }
          found.add(
            UpcomingPart(
              type: through.type,
              seriesName: through.series!.name,
              entryId: through.id,
              title: part.title,
              released: released,
              number: part.number,
              source: part.source,
              cover: part.cover,
              extra: part.extra,
            ),
          );
        }
      }
      await upcoming.write(found);
      if (complete) await store.recordRun(today);
      return true;
    } finally {
      _running = false;
    }
  }

  /// A part's edition in the owner's languages; null when the lookup
  /// cannot say or does not answer, which keeps the part as listed.
  Future<EditionRelease?> _edition(String source, Set<String> languages) async {
    final lookup = lookups.sourceOf(source);
    if (lookup == null || !lookup.isConfigured) return null;
    try {
      return await lookup.editionRelease(source, languages: languages);
    } on LookupException {
      return null;
    }
  }
}
