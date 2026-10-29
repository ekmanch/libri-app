import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/library.dart';
import '../../data/models/season.dart';
import '../../data/preferences/preferences_store.dart';

/// When each entry last changed, as seen from this phone, for the home's In
/// progress order (Library › Home: the most recently changed first).
///
/// `library.json` records when an entry was added, not when it changed, so
/// the phone keeps its own note: whenever the library it shows changes, every
/// entry that differs from before is stamped with the app clock
/// ([seasonClock]). That covers edits made here and changes pulled from
/// GitHub alike. Entries no longer in the library are dropped. Stored on the
/// device in `changes.json`, never in `library.json`; an entry without a
/// stamp counts from the day it was added.
class RecentChanges {
  /// Reads `{"<entry id>": "<ISO 8601 date and time>"}`; unreadable values
  /// are skipped.
  static Map<String, DateTime> fromJson(Map<String, Object?> json) => {
    for (final MapEntry(:key, :value) in json.entries)
      if (value is String) key: ?DateTime.tryParse(value),
  };

  static Map<String, Object?> toJson(Map<String, DateTime> changes) => {
    for (final MapEntry(:key, :value) in changes.entries)
      key: value.toIso8601String(),
  };

  /// [before]'s stamps brought up to date for [next]: every entry that is
  /// not the same as in [previous] is stamped [now]; entries gone from the
  /// library lose theirs. With no [previous] (the first load) nothing is
  /// stamped, only pruned.
  static Map<String, DateTime> update(
    Map<String, DateTime> before, {
    required Library? previous,
    required Library next,
    required DateTime now,
  }) {
    final result = <String, DateTime>{};
    for (final entry in next.entries) {
      final was = previous?.entryById(entry.id);
      if (previous != null && was != entry) {
        result[entry.id] = now;
      } else if (before[entry.id] case final at?) {
        result[entry.id] = at;
      }
    }
    return mapEquals(result, before) ? before : result;
  }
}

/// Where the stamps are kept; a memory store outside the running app.
final recentChangesStoreProvider = Provider<PreferencesStore>(
  (ref) => MemoryPreferencesStore(),
);

/// The stamps as read at startup. Overridden in `main`.
final initialRecentChangesProvider = Provider<Map<String, DateTime>>(
  (ref) => const {},
);

class RecentChangesNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    listenSelf((previous, next) {
      if (previous != null && !identical(previous, next)) {
        // A failed save only loses an order hint; the app goes on.
        ref
            .read(recentChangesStoreProvider)
            .save(RecentChanges.toJson(next))
            .catchError((Object _) {});
      }
    });
    ref.listen(libraryProvider, (previous, next) {
      final library = next.value;
      if (library == null) return;
      state = RecentChanges.update(
        state,
        previous: previous?.value,
        next: library,
        now: seasonClock(),
      );
    });
    return ref.watch(initialRecentChangesProvider);
  }
}

final recentChangesProvider =
    NotifierProvider<RecentChangesNotifier, Map<String, DateTime>>(
      RecentChangesNotifier.new,
    );
