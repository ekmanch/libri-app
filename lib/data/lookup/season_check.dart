import 'dart:io';

import '../models/entry.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import '../operations/season_operations.dart';
import '../storage/json_file.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';

/// When the daily check for new seasons last ran, kept on the device
/// (never in `library.json`).
abstract class SeasonCheckStore {
  Future<DateTime?> lastRun();

  Future<void> recordRun(DateTime day);
}

/// `season_check.json` under the cache folder: `{"checked": "2026-10-18"}`.
/// A cleared cache only means one extra check.
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
  Future<void> recordRun(DateTime day) => _file.write({
    'checked':
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
  });
}

class MemorySeasonCheckStore implements SeasonCheckStore {
  DateTime? _day;

  @override
  Future<DateTime?> lastRun() async => _day;

  @override
  Future<void> recordRun(DateTime day) async => _day = day;
}

/// Once a day, asks the lookup for new seasons of the shows being watched
/// or finished (In progress or Done; Want and DNF are skipped) that carry a
/// lookup id. A season is added once it is out or at most two weeks away
/// ([Season.isListableOn]), numbered above the show's highest. Added to a
/// show that already had seasons, it is marked New; a show that had none
/// gets every season quietly, as when a show is added.
///
/// The day is recorded only when no lookup was offline or rate limited, so
/// a check without a connection runs again on the next open. A build
/// without the key asks nothing and records the day.
class SeasonCheck {
  SeasonCheck({required this.lookups, required this.store});

  final LookupService lookups;
  final SeasonCheckStore store;

  bool _running = false;

  static bool isChecked(Entry entry) =>
      entry.type == MediaType.shows &&
      entry.source != null &&
      (entry.status == EntryStatus.inProgress ||
          entry.status == EntryStatus.done);

  /// The operations that add the new seasons, or none when the check ran
  /// today already (or is running).
  Future<List<AddSeasons>> run(Library library, DateTime now) async {
    if (_running) return const [];
    final today = DateTime(now.year, now.month, now.day);
    final last = await store.lastRun();
    if (last != null && !last.isBefore(today)) return const [];
    _running = true;
    try {
      final operations = <AddSeasons>[];
      var complete = true;
      for (final show in library.entries.where(isChecked)) {
        final source = lookups.sourceOf(show.source!);
        if (source == null || !source.isConfigured) continue;
        final List<Season>? fetched;
        try {
          fetched = await source.seasons(show.source!);
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.offline ||
              e.failure == LookupFailure.rateLimited) {
            complete = false;
            break;
          }
          continue;
        }
        if (fetched == null) continue;
        final existing = show.seasons ?? const <Season>[];
        final highest = existing.isEmpty ? 0 : existing.last.season;
        final added = [
          for (final s in Season.listable(fetched))
            if (s.season > highest)
              existing.isEmpty ? s : s.copyWith(fresh: true),
        ];
        if (added.isNotEmpty) operations.add(AddSeasons(show.id, added));
      }
      if (complete) await store.recordRun(today);
      return operations;
    } finally {
      _running = false;
    }
  }
}
