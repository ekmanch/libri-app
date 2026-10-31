import '../models/entry.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/released.dart';
import '../operations/entry_operations.dart';
import '../operations/library_operation.dart';
import '../upcoming/check_control.dart';
import 'check_day_store.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'lookup_source.dart';
import 'movie_dates.dart';

/// The daily check of release dates (Library › Home: Coming soon). Once a
/// day it asks the lookup about every entry linked to a lookup whose
/// release is still ahead, or that has no date at all, and writes the date
/// the lookup has now when it differs ("Update the release date of X"):
/// a delayed game, a movie that got its day, an album moved up. Shows and
/// anime series are not asked: their seasons carry the dates, and the
/// season check keeps those current.
///
/// A movie's dates by kind (in cinemas, digital; DESIGN.md 10c) are read
/// too and kept on the device ([movieDates]), never in `library.json`:
/// `released` holds the first of them whatever Settings › Movies › Release
/// dates says, and the setting only picks which one is shown. A movie out
/// within the last [digitalWindow] days is asked as well, so a digital
/// date that follows the cinemas is learned. A book's date is that of its
/// earliest edition in the [languages] the owner reads when the lookup
/// lists its editions.
///
/// A date the lookup no longer has leaves the entry's own: the owner may
/// know better than a record that went blank. The day is recorded only
/// when no lookup was offline, rate limited or failing, so a check without
/// a connection runs again on the next open.
class ReleaseCheck {
  ReleaseCheck({
    required this.lookups,
    required this.store,
    MovieDateStore? movieDates,
  }) : movieDates = movieDates ?? MemoryMovieDateStore();

  final LookupService lookups;
  final CheckDayStore store;
  final MovieDateStore movieDates;

  /// How long after its first release a movie is still asked about, for
  /// its digital date.
  static const digitalWindow = 180;

  bool _running = false;

  /// Whether the check asks the lookup about [entry] on [today]: linked to
  /// a lookup, not a show or an anime series, and not out yet by its own
  /// date, or without one; or a movie out within [digitalWindow] days whose
  /// digital date ([dates], as recorded) is not known or still ahead.
  static bool isAsked(Entry entry, DateTime today, {MovieDates? dates}) {
    if (entry.source == null || entry.usesSeasons) return false;
    final released = entry.released;
    if (released == null || !released.isReleasedOn(today)) return true;
    if (entry.type != MediaType.movies) return false;
    final day = DateTime(today.year, today.month, today.day);
    final recent = !released.availableFrom.isBefore(
      day.subtract(const Duration(days: digitalWindow)),
    );
    final digital = dates?.digital;
    return recent && (digital == null || !digital.isReleasedOn(today));
  }

  /// Runs the check when it is due today (always with [force]), asking
  /// about every entry [isAsked], or with [include] only those it says.
  /// [languages] are the ones the owner reads, for a book's edition.
  /// [control] hears of each entry asked and can stop the run, which then
  /// records no day.
  Future<List<LibraryOperation>> run(
    Library library,
    DateTime now, {
    bool force = false,
    bool Function(Entry entry)? include,
    Set<String> languages = const {},
    CheckControl? control,
  }) async {
    if (_running) return const [];
    final today = DateTime(now.year, now.month, now.day);
    if (!force && !checkDueOn(await store.lastRun(), now)) return const [];
    final ctl = control ?? CheckControl.none;
    _running = true;
    try {
      final operations = <LibraryOperation>[];
      final dates = Map.of(await movieDates.read());
      var datesChanged = false;
      var complete = true;
      for (final entry in library.entries) {
        if (!isAsked(entry, today, dates: dates[entry.source])) continue;
        if (include != null && !include(entry)) continue;
        if (ctl.cancelled) {
          complete = false;
          break;
        }
        final source = lookups.sourceOf(entry.source!);
        if (source == null || !source.isConfigured) continue;
        final Released? released;
        try {
          released = await _releaseOf(
            entry,
            source,
            languages: languages,
            onDates: (found) {
              if (dates[entry.source!] != found) datesChanged = true;
              dates[entry.source!] = found;
            },
          );
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.offline ||
              e.failure == LookupFailure.rateLimited) {
            complete = false;
            break;
          }
          // A server error is no answer and leaves the day to run again; a
          // 404 or a bad answer is nothing learned about this entry.
          if (e.isTransient) complete = false;
          ctl.tick();
          continue;
        }
        ctl.tick();
        if (released != null && released != entry.released) {
          operations.add(SetReleased(entry.id, released));
        }
      }
      if (datesChanged) await movieDates.write(dates);
      if (complete) await store.recordRun(today);
      return operations;
    } finally {
      _running = false;
    }
  }

  /// The date the lookup has for [entry] now: for a movie the first of its
  /// dates by kind ([onDates] hears them), else the lookup's own; for a
  /// book the earliest edition in [languages] when the lookup lists one
  /// (a book with no edition in them keeps the work's date, since the
  /// owner added it).
  Future<Released?> _releaseOf(
    Entry entry,
    LookupSource source, {
    required Set<String> languages,
    required void Function(MovieDates dates) onDates,
  }) async {
    final id = entry.source!;
    if (entry.type == MediaType.movies) {
      final dates = await source.movieDates(id);
      if (dates != null && !dates.isEmpty) {
        onDates(dates);
        return dates.first;
      }
      return source.releaseDate(id);
    }
    if (entry.type == MediaType.books && languages.isNotEmpty) {
      final edition = await source.editionRelease(id, languages: languages);
      if (edition?.released case final released?) return released;
    }
    return source.releaseDate(id);
  }
}
