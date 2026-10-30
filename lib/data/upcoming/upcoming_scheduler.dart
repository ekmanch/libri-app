import 'package:flutter/foundation.dart';

import '../lookup/check_day_store.dart';
import '../lookup/release_check.dart';
import '../lookup/season_check.dart';
import '../lookup/series_check.dart';
import '../lookup/text_clean.dart';
import '../models/app_settings.dart';
import '../models/entry.dart';
import '../models/entry_status.dart';
import '../models/follow_kind.dart';
import '../models/library.dart';
import '../net/network_kind.dart';
import '../operations/library_operation.dart';
import '../storage/json_file.dart';
import 'check_control.dart';
import 'creator_check.dart';
import 'follows.dart';

/// What the scheduler remembers on the device (`check_schedule.json` under
/// the cache folder): the last day a run completed, when the checks last
/// asked anything, and how many releases that run found that were new.
@immutable
class UpcomingSchedule {
  const UpcomingSchedule({this.lastRun, this.lastChecked, this.newCount = 0});

  static const none = UpcomingSchedule();

  /// The last day every check completed, so the weekly shares of the days
  /// since are caught up.
  final DateTime? lastRun;

  /// When the checks last ran (complete or not), for "Last checked".
  final DateTime? lastChecked;

  /// Releases that run found that were not recorded before ("3 new").
  final int newCount;

  factory UpcomingSchedule.fromJson(Map<String, Object?> json) =>
      UpcomingSchedule(
        lastRun: _date(json['lastRun']),
        lastChecked: _date(json['lastChecked']),
        newCount: (json['newCount'] as num?)?.toInt() ?? 0,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  Map<String, Object?> toJson() => {
    'lastRun': lastRun == null ? null : _day(lastRun!),
    'lastChecked': lastChecked?.toIso8601String(),
    'newCount': newCount,
  };

  static String _day(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is UpcomingSchedule &&
      other.lastRun == lastRun &&
      other.lastChecked == lastChecked &&
      other.newCount == newCount;

  @override
  int get hashCode => Object.hash(lastRun, lastChecked, newCount);
}

abstract class UpcomingScheduleStore {
  Future<UpcomingSchedule> read();

  Future<void> write(UpcomingSchedule schedule);
}

class FileUpcomingScheduleStore implements UpcomingScheduleStore {
  FileUpcomingScheduleStore(this._file);

  final JsonFile _file;

  @override
  Future<UpcomingSchedule> read() async {
    final json = await _file.read();
    return json == null
        ? UpcomingSchedule.none
        : UpcomingSchedule.fromJson(json);
  }

  @override
  Future<void> write(UpcomingSchedule schedule) =>
      _file.write(schedule.toJson());
}

class MemoryUpcomingScheduleStore implements UpcomingScheduleStore {
  MemoryUpcomingScheduleStore([UpcomingSchedule? schedule])
    : _schedule = schedule ?? UpcomingSchedule.none;

  UpcomingSchedule _schedule;

  @override
  Future<UpcomingSchedule> read() async => _schedule;

  @override
  Future<void> write(UpcomingSchedule schedule) async => _schedule = schedule;
}

/// Why a run did nothing, or what it did.
enum UpcomingRunOutcome {
  /// The master switch is off: nothing is followed, nothing is fetched.
  disabled,

  /// Only on Wi-Fi is on and the phone is on mobile data.
  onMobileData,

  /// Every check already ran today.
  alreadyRan,

  /// The checks ran (some may have stopped short; see [UpcomingRunResult]).
  ran,
}

/// What a run of the scheduler did, for the shell: the operations the
/// checks produced are applied through the callback as they come; the
/// dropped seasons are for Show & seasons › Announced season dropped.
typedef UpcomingRunResult = ({
  UpcomingRunOutcome outcome,
  List<DroppedSeason> dropped,
  bool partsChanged,
  bool releasesChanged,
  bool complete,
});

/// Runs the checks for new releases on their schedule (DESIGN.md 10c): on
/// the first open of each day (and each return to the foreground until a
/// run completed that day), what the owner wants and what is dated every
/// day, the rest once a week, a seventh of it each day, with the sevenths of
/// missed days caught up on the next open. Check now runs the whole set at
/// once, with progress and Stop. Only on Wi-Fi skips the scheduled run on
/// mobile data; the master switch off stops every check.
///
/// The season check asks daily about shows with a season still to come,
/// the release date check about entries set Want or dated, the series check
/// about series with a dated part recorded; everything else, and every
/// creator, takes its turn by a stable share of its id.
class UpcomingScheduler {
  UpcomingScheduler({
    this.seasons,
    this.releases,
    this.series,
    this.creators,
    required this.store,
    this.network = const FixedNetworkKind(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SeasonCheck? seasons;
  final ReleaseCheck? releases;
  final SeriesCheck? series;
  final CreatorCheck? creators;
  final UpcomingScheduleStore store;
  final NetworkKind network;
  final DateTime Function() _now;

  /// How far the current run has come, for Settings › Upcoming releases.
  final progress = ValueNotifier<CheckProgress>(CheckProgress.idle);

  bool _stop = false;
  bool _running = false;

  bool get isRunning => _running;

  /// Stops the run in progress after the item being asked about; the
  /// checks record no day, so the next open takes them up again.
  void stop() => _stop = true;

  void dispose() => progress.dispose();

  /// Which of the seven weekly shares [id] is in: a stable hash of the id,
  /// so the same item is always asked on the same weekday.
  static int shareOf(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % 7;
  }

  /// The share whose turn it is on [day].
  static int shareOn(DateTime day) =>
      DateTime(day.year, day.month, day.day).difference(_epoch).inDays % 7;

  static final _epoch = DateTime(2026);

  /// The shares due on [today]: today's, and those of the days since the
  /// last completed run that were missed (all seven after a week away). A
  /// first run, with no completed run to count from, does all seven, so a
  /// new install learns its library's state at once.
  static Set<int> dueShares(DateTime? lastRun, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    if (lastRun == null) return {0, 1, 2, 3, 4, 5, 6};
    final last = DateTime(lastRun.year, lastRun.month, lastRun.day);
    final missed = day.difference(last).inDays;
    if (missed >= 7) return {0, 1, 2, 3, 4, 5, 6};
    return {
      for (var i = 0; i < missed; i++) shareOn(day.subtract(Duration(days: i))),
    };
  }

  /// Whether [show] has a season still to come on [today].
  static bool hasComingSeason(Entry show, DateTime today) =>
      show.seasons?.any(
        (s) => s.released != null && !s.released!.isReleasedOn(today),
      ) ??
      false;

  /// Runs what is due ([everything]: all of it, now, whatever the day or
  /// the network). Operations the checks produce go to [apply] as they
  /// come, so the library shows them at once.
  Future<UpcomingRunResult> run({
    required Library library,
    required AppSettings settings,
    required bool wifiOnly,
    bool everything = false,
    required Future<void> Function(LibraryOperation operation) apply,
  }) async {
    const none = <DroppedSeason>[];
    UpcomingRunResult outcome(UpcomingRunOutcome o) => (
      outcome: o,
      dropped: none,
      partsChanged: false,
      releasesChanged: false,
      complete: false,
    );
    if (_running) return outcome(UpcomingRunOutcome.alreadyRan);
    if (!settings.upcomingEnabled) return outcome(UpcomingRunOutcome.disabled);
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final schedule = await store.read();
    if (!everything) {
      if (!await _anyDue(today)) return outcome(UpcomingRunOutcome.alreadyRan);
      if (wifiOnly && await network.isOnMobileData()) {
        return outcome(UpcomingRunOutcome.onMobileData);
      }
    }
    _running = true;
    _stop = false;
    try {
      final shares = everything
          ? const {0, 1, 2, 3, 4, 5, 6}
          : dueShares(schedule.lastRun, today);
      bool inShare(String id) => shares.contains(shareOf(id));
      final statuses = await creators?.statuses.read() ?? const {};
      final follows = deriveFollows(library, settings, statuses: statuses);
      final recordedParts = await series?.upcoming.read() ?? const [];
      final datedSeries = {
        for (final p in recordedParts)
          if (p.released.day != null || p.released.month != null)
            '${p.type.name}/${titleKey(p.seriesName)}',
      };

      bool showDue(Entry show) =>
          hasComingSeason(show, today) || inShare(show.id);
      bool entryDue(Entry entry) =>
          entry.status == EntryStatus.want ||
          entry.released != null ||
          inShare(entry.id);
      bool seriesDue(String key, List<Entry> parts) =>
          datedSeries.contains(key) || inShare(key);
      bool creatorDue(Follow f) => inShare(f.key);

      final total =
          library.entries.where(SeasonCheck.isAsked).where(showDue).length +
          library.entries
              .where((e) => ReleaseCheck.isAsked(e, today))
              .where(entryDue)
              .length +
          SeriesCheck.seriesOf(library).entries
              .where((e) => SeriesCheck.isFollowed(e.value))
              .where((e) => seriesDue(e.key, e.value))
              .length +
          [
            for (final kind in FollowKind.values)
              if (kind.isCreator) ...follows.of(kind),
          ].where(creatorDue).length;
      progress.value = CheckProgress(running: true, done: 0, total: total);
      final control = CheckControl(
        onTick: () => progress.value = progress.value.copyWith(
          done: progress.value.done + 1,
        ),
        cancelled: () => _stop,
      );

      var dropped = none;
      var partsChanged = false;
      var releasesChanged = false;
      if (seasons case final check?) {
        final result = await check.run(
          library,
          now,
          force: everything,
          include: showDue,
          control: control,
        );
        for (final operation in result.operations) {
          await apply(operation);
        }
        dropped = result.dropped;
      }
      if (releases case final check?) {
        final operations = await check.run(
          library,
          now,
          force: everything,
          include: entryDue,
          control: control,
        );
        for (final operation in operations) {
          await apply(operation);
        }
      }
      if (series case final check?) {
        partsChanged = await check.run(
          library,
          now,
          force: everything,
          include: seriesDue,
          control: control,
        );
      }
      var found = 0;
      if (creators case final check?) {
        final result = await check.run(
          follows,
          now,
          force: everything,
          include: creatorDue,
          control: control,
        );
        releasesChanged = result.wrote;
        found = result.found;
      }
      final complete = !_stop && await _allRanOn(today);
      await store.write(
        UpcomingSchedule(
          lastRun: complete ? today : schedule.lastRun,
          lastChecked: now,
          newCount: found,
        ),
      );
      return (
        outcome: UpcomingRunOutcome.ran,
        dropped: dropped,
        partsChanged: partsChanged,
        releasesChanged: releasesChanged,
        complete: complete,
      );
    } finally {
      _running = false;
      progress.value = CheckProgress.idle;
    }
  }

  List<CheckDayStore> get _dayStores => [
    ?releases?.store,
    ?series?.store,
    ?creators?.store,
  ];

  /// Whether any check has not run today yet.
  Future<bool> _anyDue(DateTime today) async {
    if (seasons case final check?) {
      if (checkDueOn(await check.store.lastRun(), today)) return true;
    }
    for (final store in _dayStores) {
      if (checkDueOn(await store.lastRun(), today)) return true;
    }
    return false;
  }

  Future<bool> _allRanOn(DateTime today) async => !await _anyDue(today);
}
