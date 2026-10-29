import '../models/entry.dart';
import '../models/library.dart';
import '../models/released.dart';
import '../operations/entry_operations.dart';
import '../operations/library_operation.dart';
import 'check_day_store.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';

/// The daily check of release dates (Library › Home: Coming soon). Once a
/// day it asks the lookup about every entry linked to a lookup whose
/// release is still ahead, or that has no date at all, and writes the date
/// the lookup has now when it differs ("Update the release date of X"):
/// a delayed game, a movie that got its day, an album moved up. Shows and
/// anime series are not asked: their seasons carry the dates, and the
/// season check keeps those current.
///
/// A date the lookup no longer has leaves the entry's own: the owner may
/// know better than a record that went blank. The day is recorded only
/// when no lookup was offline, rate limited or failing, so a check without
/// a connection runs again on the next open.
class ReleaseCheck {
  ReleaseCheck({required this.lookups, required this.store});

  final LookupService lookups;
  final CheckDayStore store;

  bool _running = false;

  /// Whether the check asks the lookup about [entry] on [today]: linked to
  /// a lookup, not a show or an anime series, and not out yet by its own
  /// date, or without one.
  static bool isAsked(Entry entry, DateTime today) {
    if (entry.source == null || entry.usesSeasons) return false;
    final released = entry.released;
    return released == null || !released.isReleasedOn(today);
  }

  Future<List<LibraryOperation>> run(Library library, DateTime now) async {
    if (_running) return const [];
    final today = DateTime(now.year, now.month, now.day);
    if (!checkDueOn(await store.lastRun(), now)) return const [];
    _running = true;
    try {
      final operations = <LibraryOperation>[];
      var complete = true;
      for (final entry in library.entries) {
        if (!isAsked(entry, today)) continue;
        final source = lookups.sourceOf(entry.source!);
        if (source == null || !source.isConfigured) continue;
        final Released? released;
        try {
          released = await source.releaseDate(entry.source!);
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.offline ||
              e.failure == LookupFailure.rateLimited) {
            complete = false;
            break;
          }
          // A server error is no answer and leaves the day to run again; a
          // 404 or a bad answer is nothing learned about this entry.
          if (e.isTransient) complete = false;
          continue;
        }
        if (released != null && released != entry.released) {
          operations.add(SetReleased(entry.id, released));
        }
      }
      if (complete) await store.recordRun(today);
      return operations;
    } finally {
      _running = false;
    }
  }
}
