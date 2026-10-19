import 'dart:io';

import '../models/entry.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import '../operations/library_operation.dart';
import '../operations/season_operations.dart';
import '../storage/json_file.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'lookup_source.dart';

/// What the daily check keeps on the device (never in `library.json`):
/// the day it last ran, and the seasons it found missing from the lookup
/// on that run, as `"<entry id>#<season>"`.
abstract class SeasonCheckStore {
  Future<DateTime?> lastRun();

  Future<Set<String>> missing();

  Future<void> recordRun(DateTime day, Set<String> missing);
}

/// `season_check.json` under the cache folder:
/// `{"checked": "2026-10-18", "missing": ["shows/carrie-2026#2"]}`. A
/// cleared cache only means one extra check, and a dropped season waiting
/// one more day.
class FileSeasonCheckStore implements SeasonCheckStore {
  FileSeasonCheckStore(Directory cache)
    : _file = JsonFile(
        File('${cache.path}${Platform.pathSeparator}season_check.json'),
      );

  final JsonFile _file;

  @override
  Future<DateTime?> lastRun() async {
    final checked = (await _file.read())?['checked'];
    return checked is String ? DateTime.tryParse(checked) : null;
  }

  @override
  Future<Set<String>> missing() async {
    final missing = (await _file.read())?['missing'];
    return {
      if (missing is List)
        for (final key in missing)
          if (key is String) key,
    };
  }

  @override
  Future<void> recordRun(DateTime day, Set<String> missing) => _file.write({
    'checked':
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    'missing': [...missing]..sort(),
  });
}

class MemorySeasonCheckStore implements SeasonCheckStore {
  DateTime? _day;
  Set<String> _missing = {};

  @override
  Future<DateTime?> lastRun() async => _day;

  @override
  Future<Set<String>> missing() async => _missing;

  @override
  Future<void> recordRun(DateTime day, Set<String> missing) async {
    _day = day;
    _missing = missing;
  }
}

/// A season the lookup dropped that has a status, so the user is asked
/// whether to keep it (Show & seasons › Announced season dropped).
typedef DroppedSeason = ({String entryId, int season, EntryStatus status});

/// What one daily check found: operations to apply at once, and seasons
/// to ask about.
typedef SeasonCheckResult = ({
  List<LibraryOperation> operations,
  List<DroppedSeason> dropped,
});

/// The daily check (DESIGN.md 10c). Once a day it asks the lookup about
/// every show linked to TMDB that is not DNF, and once about any show
/// without seasons whatever its status:
///
/// - Seasons numbered above the show's highest that have a date are added,
///   marked New on a show that had seasons; a show that had none gets them
///   quietly, its own date dropped and its status carried over.
/// - Seasons not out yet that Libri added get the lookup's new date.
/// - A season not out yet that Libri added, missing from the lookup or on
///   a show marked Canceled there on two checks in a row, is removed when
///   it has no status, and asked about when it has one.
/// - A show whose stored status differs from what its seasons give (a
///   season has come out) gets it written.
///
/// Seasons added in the form, kept when asked, or already out are never
/// removed. The day is recorded only when no lookup was offline or rate
/// limited, so a check without a connection runs again on the next open.
class SeasonCheck {
  SeasonCheck({required this.lookups, required this.store});

  final LookupService lookups;
  final SeasonCheckStore store;

  bool _running = false;

  static const _none = (
    operations: <LibraryOperation>[],
    dropped: <DroppedSeason>[],
  );

  /// Whether the check asks the lookup about [entry].
  static bool isAsked(Entry entry) =>
      entry.type == MediaType.shows &&
      (entry.source?.startsWith('tmdb:tv:') ?? false) &&
      (entry.status != EntryStatus.dnf || (entry.seasons?.isEmpty ?? true));

  static String _key(String entryId, int season) => '$entryId#$season';

  Future<SeasonCheckResult> run(Library library, DateTime now) async {
    if (_running) return _none;
    final today = DateTime(now.year, now.month, now.day);
    final last = await store.lastRun();
    if (last != null && !last.isBefore(today)) return _none;
    _running = true;
    try {
      final previous = await store.missing();
      final missing = <String>{};
      final operations = <LibraryOperation>[];
      final dropped = <DroppedSeason>[];
      final touched = <String>{};
      var complete = true;
      for (final show in library.entries.where(isAsked)) {
        final source = lookups.sourceOf(show.source!);
        if (source == null || !source.isConfigured) continue;
        final ShowSeasons? fetched;
        try {
          fetched = await source.seasons(show.source!);
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.offline ||
              e.failure == LookupFailure.rateLimited) {
            complete = false;
            break;
          }
          // Not found or a bad answer: nothing learned, so a season it
          // missed before stays missed. A server error (5xx) is not an
          // answer either, and leaves the day's check to run again.
          if (e.isTransient) complete = false;
          missing.addAll(previous.where((k) => k.startsWith('${show.id}#')));
          continue;
        }
        if (fetched == null) continue;
        final existing = show.seasons ?? const <Season>[];
        final highest = existing.isEmpty ? 0 : existing.last.season;
        final listed = {for (final s in fetched.seasons) s.season: s};

        final added = [
          for (final s in Season.listable(fetched.seasons))
            if (s.season > highest)
              existing.isEmpty ? s : s.copyWith(fresh: true),
        ];
        if (added.isNotEmpty) operations.add(AddSeasons(show.id, added));

        final redated = <Season>[];
        for (final s in existing) {
          if (s.isManual || s.isReleasedOn(today)) continue;
          final date = listed[s.season]?.released;
          if (date != null && date != s.released) {
            redated.add(Season(season: s.season, released: date));
          }
        }
        if (redated.isNotEmpty) {
          operations.add(SetSeasonDates(show.id, redated));
        }

        for (final s in existing) {
          if (s.isManual || s.isReleasedOn(today)) continue;
          if (!fetched.canceled && listed.containsKey(s.season)) continue;
          final key = _key(show.id, s.season);
          missing.add(key);
          if (!previous.contains(key)) continue;
          if (s.status case final status?) {
            dropped.add((entryId: show.id, season: s.season, status: status));
          } else {
            operations.add(RemoveSeason(show.id, s.season));
          }
        }
        if (added.isNotEmpty || redated.isNotEmpty) touched.add(show.id);
      }
      if (complete) {
        // A show whose status its seasons no longer give: a season came
        // out. The operations above write it already for their shows.
        for (final show in library.entries) {
          final seasons = show.seasons;
          if (show.type != MediaType.shows ||
              seasons == null ||
              seasons.isEmpty ||
              touched.contains(show.id)) {
            continue;
          }
          if (Season.showStatus(seasons, today) != show.status) {
            operations.add(RefreshShowStatus(show.id));
          }
        }
        await store.recordRun(today, missing);
      }
      return (operations: operations, dropped: dropped);
    } finally {
      _running = false;
    }
  }
}
