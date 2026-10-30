import '../lookup/series_check.dart';
import '../models/app_settings.dart';
import '../models/library.dart';
import 'creator_lookup.dart';

/// The Not interested keys of [settings] whose rows cannot come back, so
/// they can be forgotten (`ForgetNotInterested`) and the list does not grow
/// for ever: an entry's id when the entry is gone or its release is out, a
/// season key when the show or the season is gone or the season is out, and
/// a lookup id when the recorded part or release has come out or an entry
/// with that id is in the library by now. A lookup id that nothing records
/// (a release of a creator since unfollowed, a part of a series no longer
/// followed) is kept: re-following must not bring the row back.
List<String> staleNotInterested(
  AppSettings settings,
  Library library, {
  required List<UpcomingPart> parts,
  required List<FoundRelease> releases,
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final owned = {for (final e in library.entries) ?e.source};
  final partDates = {for (final p in parts) ?p.source: p.released};
  final releaseDates = {for (final r in releases) r.key: r.match.released};
  final stale = <String>[];
  for (final key in settings.notInterested) {
    final hash = key.indexOf('#');
    if (hash > 0 && int.tryParse(key.substring(hash + 1)) != null) {
      final show = library.entryById(key.substring(0, hash));
      final number = int.parse(key.substring(hash + 1));
      final season = show?.seasons
          ?.where((s) => s.season == number)
          .firstOrNull;
      if (show == null || season == null || season.isReleasedOn(day)) {
        stale.add(key);
      }
      continue;
    }
    final entry = library.entryById(key);
    if (entry != null) {
      final released = entry.released;
      if (released != null && released.isReleasedOn(day)) stale.add(key);
      continue;
    }
    if (owned.contains(key)) {
      stale.add(key);
      continue;
    }
    if (key.contains('/') && !key.contains(':')) {
      // An entry id that is no longer in the library.
      stale.add(key);
      continue;
    }
    final released = releaseDates.containsKey(key)
        ? releaseDates[key]
        : partDates[key];
    if (released != null && !isRecentOrAhead(released, day)) stale.add(key);
  }
  return stale;
}
