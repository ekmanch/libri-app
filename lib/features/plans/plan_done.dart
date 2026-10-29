import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/plan.dart';
import '../../data/models/plan_item.dart';
import '../../data/models/season.dart';
import '../../data/operations/operations.dart';
import '../shell/app_shell.dart';
import 'plan_progress.dart';

/// The status an entry had before a plan check marked it Done, by plan
/// item, so unticking can put it back. Session state on the device; it is
/// not part of `library.json`.
class StatusBeforeDoneNotifier extends Notifier<Map<String, EntryStatus>> {
  @override
  Map<String, EntryStatus> build() => const {};

  void remember(String key, EntryStatus status) =>
      state = {...state, key: status};

  void forget(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }

  /// Returns and forgets the remembered status.
  EntryStatus? take(String key) {
    final status = state[key];
    if (status != null) forget(key);
    return status;
  }
}

final statusBeforeDoneProvider =
    NotifierProvider<StatusBeforeDoneNotifier, Map<String, EntryStatus>>(
      StatusBeforeDoneNotifier.new,
    );

String planItemKey(String planId, String entryId) => '$planId/$entryId';

/// A show's seasons before a plan check marked them Done, by plan item, so
/// unticking can put them back exactly (DESIGN.md: a show's status comes
/// from its seasons).
class SeasonsBeforeDoneNotifier extends Notifier<Map<String, List<Season>>> {
  @override
  Map<String, List<Season>> build() => const {};

  void remember(String key, List<Season> seasons) =>
      state = {...state, key: seasons};

  List<Season>? take(String key) {
    final seasons = state[key];
    if (seasons != null) state = {...state}..remove(key);
    return seasons;
  }
}

final seasonsBeforeDoneProvider =
    NotifierProvider<SeasonsBeforeDoneNotifier, Map<String, List<Season>>>(
      SeasonsBeforeDoneNotifier.new,
    );

/// Ticks or unticks a plan item (Plans › Plan checklist; Plan with timing on;
/// Entry details (timeline on); Entry details (timeline off)).
///
/// Ticking also marks the entry Done when it was not, and remembers what
/// it was (a show: its seasons, every one that is out marked Done). Unticking puts that status back, but only if the entry is still
/// Done; a status changed elsewhere in between stays. An entry that was
/// already Done when ticked is left alone when unticked.
///
/// Ticking an item starts the plan, so unticking one later, or adding an entry
/// to a finished plan, leaves it Active (the Plans › Edit plan note). Returns
/// true when this tick finished the plan: the last entry ticked, and the
/// plan's end date passed (or no dates at all); before that day the plan
/// stays Active and finishes on its own the day after ([planState]).
Future<bool> togglePlanItemDone(
  WidgetRef ref, {
  required Plan plan,
  required PlanItem item,
  required Entry entry,
}) async {
  final repository = ref.read(libraryRepositoryProvider);
  final memory = ref.read(statusBeforeDoneProvider.notifier);
  final key = planItemKey(plan.id, entry.id);
  final done = !item.done;
  await repository.apply(SetPlanItem(plan.id, item.copyWith(done: done)));
  if (done) {
    await repository.apply(SetPlanStarted(plan.id, true));
    if (entry.status == EntryStatus.done) {
      memory.forget(key);
    } else {
      memory.remember(key, entry.status);
      if (entry.seasons case final seasons? when seasons.isNotEmpty) {
        ref.read(seasonsBeforeDoneProvider.notifier).remember(key, seasons);
      }
      await repository.apply(SetStatus(entry.id, EntryStatus.done));
    }
  } else {
    final previous = memory.take(key);
    final seasons = ref.read(seasonsBeforeDoneProvider.notifier).take(key);
    if (previous != null && entry.status == EntryStatus.done) {
      await repository.apply(
        seasons != null
            ? SetSeasons(entry.id, seasons)
            : SetStatus(entry.id, previous),
      );
    }
  }
  if (!done) return false;
  final after = (await repository.load()).planById(plan.id);
  return after != null && planState(after) == PlanState.finished;
}

/// [togglePlanItemDone], and when the tick finishes the plan a short
/// "Halloween 2026 finished" message whose Undo unticks the item again. A
/// tick that leaves everything done before the end date shows no message:
/// the plan is still Active then.
Future<void> togglePlanItemDoneWithUndo(
  BuildContext context,
  WidgetRef ref, {
  required Plan plan,
  required PlanItem item,
  required Entry entry,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final finished = await togglePlanItemDone(
    ref,
    plan: plan,
    item: item,
    entry: entry,
  );
  if (!finished) return;
  final repository = ref.read(libraryRepositoryProvider);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${planTitle(plan)} finished'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(
          20,
          0,
          20,
          AppShell.contentBottomPadding,
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final library = await repository.load();
            final now = library.planById(plan.id);
            final nowItem = now?.itemFor(entry.id);
            final nowEntry = library.entryById(entry.id);
            if (now == null || nowItem == null || nowEntry == null) return;
            if (!nowItem.done) return;
            await togglePlanItemDone(
              ref,
              plan: now,
              item: nowItem,
              entry: nowEntry,
            );
          },
        ),
      ),
    );
}
