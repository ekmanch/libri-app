import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/lookup/season_check.dart';
import '../../data/models/app_settings.dart';
import '../../data/operations/settings_operations.dart';
import '../../data/repository/library_repository.dart';
import '../../data/upcoming/not_interested.dart';
import '../../data/upcoming/check_control.dart';
import '../../data/upcoming/upcoming_scheduler.dart';
import '../library/upcoming.dart';
import '../settings/display_preferences.dart';

/// Runs the checks for new releases (DESIGN.md 10c) for the shell (on the
/// first open of the day and each return to the foreground) and for Check
/// now in Settings › Upcoming releases, applying what they find to the
/// library and telling the screens to read the records again. Seasons the
/// lookup dropped go to [droppedSeasonsProvider], which the shell asks
/// about (Show & seasons › Announced season dropped).
final upcomingChecksProvider = Provider<UpcomingChecks>(
  (ref) => UpcomingChecks(ref),
);

class UpcomingChecks {
  UpcomingChecks(this._ref);

  final Ref _ref;
  bool _carriedOver = false;

  /// Runs what is due, or with [everything] the whole set now. Null when
  /// the library is not loaded.
  Future<UpcomingRunResult?> run({bool everything = false}) async {
    final library = _ref.read(libraryProvider).value;
    if (library == null) return null;
    final repository = _ref.read(libraryRepositoryProvider);
    await carryOver();
    final AppSettings settings;
    try {
      settings = await repository.loadSettings();
    } on Object {
      // Not connected, or the settings cannot be read: nothing to follow.
      return null;
    }
    final scheduler = _ref.read(upcomingSchedulerProvider);
    final result = await scheduler.run(
      library: library,
      settings: settings,
      wifiOnly: _ref.read(displayPreferencesProvider).upcomingWifiOnly,
      everything: everything,
      apply: (operation) => repository.apply(operation),
    );
    if (result.outcome == UpcomingRunOutcome.ran) {
      if (result.partsChanged) _ref.invalidate(upcomingPartsProvider);
      if (result.releasesChanged) _ref.invalidate(foundReleasesProvider);
      _ref.invalidate(creatorStatusesProvider);
      _ref.invalidate(upcomingScheduleProvider);
      if (result.dropped.isNotEmpty) {
        _ref.read(droppedSeasonsProvider.notifier).add(result.dropped);
      }
      await _forgetStale(repository, settings);
    }
    return result;
  }

  /// Not interested keys whose rows are out or gone leave the settings, so
  /// the list does not grow for ever (`staleNotInterested`).
  Future<void> _forgetStale(
    LibraryRepository repository,
    AppSettings settings,
  ) async {
    final library = _ref.read(libraryProvider).value;
    final scheduler = _ref.read(upcomingSchedulerProvider);
    if (library == null || settings.notInterested.isEmpty) return;
    final stale = staleNotInterested(
      await repository.loadSettings(),
      library,
      parts: await scheduler.series?.upcoming.read() ?? const [],
      releases: await scheduler.creators?.releases.read() ?? const [],
      today: DateTime.now(),
    );
    if (stale.isNotEmpty) {
      await repository.applySettings(ForgetNotInterested(stale));
    }
  }

  /// Stops the run in progress (Stop in Settings › Upcoming releases).
  void stop() => _ref.read(upcomingSchedulerProvider).stop();

  /// Once per session: the plan defaults, the default platform and the Not
  /// interested rows a `preferences.json` from before `settings.json` holds
  /// go into the synced settings, then leave the preferences.
  Future<void> carryOver() async {
    if (_carriedOver) return;
    final prefs = _ref.read(displayPreferencesProvider);
    if (prefs.legacy.isEmpty && prefs.hiddenUpcoming.isEmpty) {
      _carriedOver = true;
      return;
    }
    final repository = _ref.read(libraryRepositoryProvider);
    final library = _ref.read(libraryProvider).value;
    try {
      final legacy = prefs.legacy;
      if (legacy.timelineDefault case final on?) {
        await repository.applySettings(SetTimelineDefault(on));
      }
      if (legacy.seasonalThemeDefault case final on?) {
        await repository.applySettings(SetSeasonalThemeDefault(on));
      }
      if (legacy.hasDefaultPlatform) {
        await repository.applySettings(SetDefaultPlatform(legacy.platform));
      }
      for (final key in prefs.hiddenUpcoming) {
        await repository.applySettings(
          SetNotInterested(key, title: _titleOf(key, library)),
        );
      }
    } on Object {
      // Not connected yet: tried again on the next run.
      return;
    }
    _carriedOver = true;
    _ref.read(displayPreferencesProvider.notifier).clearLegacy();
  }

  /// "Stranger Things, Season 5" for a season key, the entry's title for an
  /// entry's id, else the key itself.
  static String _titleOf(String key, library) {
    final hash = key.indexOf('#');
    final entryId = hash < 0 ? key : key.substring(0, hash);
    final title = library?.entryById(entryId)?.title;
    if (title == null) return key;
    return hash < 0 ? title : '$title, Season ${key.substring(hash + 1)}';
  }
}

/// Seasons the daily check found dropped that the owner gave a status, to
/// be asked about one at a time (Show & seasons › Announced season dropped).
final droppedSeasonsProvider =
    NotifierProvider<DroppedSeasonsNotifier, List<DroppedSeason>>(
      DroppedSeasonsNotifier.new,
    );

class DroppedSeasonsNotifier extends Notifier<List<DroppedSeason>> {
  @override
  List<DroppedSeason> build() => const [];

  void add(List<DroppedSeason> dropped) => state = [...state, ...dropped];

  /// Takes every season queued, leaving none.
  List<DroppedSeason> take() {
    final taken = state;
    state = const [];
    return taken;
  }
}

/// How far the run in progress has come, for Settings › Upcoming releases
/// ("Checking 184 of 423…", Stop).
final upcomingProgressProvider = StreamProvider<CheckProgress>((ref) {
  final progress = ref.watch(upcomingSchedulerProvider).progress;
  final controller = StreamController<CheckProgress>();
  controller.add(progress.value);
  void listen() => controller.add(progress.value);
  progress.addListener(listen);
  ref.onDispose(() {
    progress.removeListener(listen);
    controller.close();
  });
  return controller.stream;
});

/// When the checks last ran and what they found ("Last checked · Today 07:12
/// · 3 new"). Read again after each run.
final upcomingScheduleProvider = FutureProvider<UpcomingSchedule>(
  (ref) => ref.watch(upcomingScheduleStoreProvider).read(),
);

/// The key a season is hidden by, as `UpcomingItem.seasonKey` forms it.
String upcomingSeasonKey(String entryId, int season) =>
    UpcomingItem.seasonKey(entryId, season);
