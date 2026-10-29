import '../../data/models/library.dart';
import '../../data/models/plan.dart';
import '../../data/models/season.dart';
import '../../data/operations/plan_operations.dart';
import 'plan_dates.dart';

/// Where a plan stands, as grouped on Plans › Plans overview (the Plans › Edit
/// plan note).
enum PlanState { active, notStarted, finished }

/// Finished: at least one entry, every entry done (removed ones are no
/// longer in the plan), and the plan's end date, when it has one, has passed:
/// on or before its last date a plan with everything done stays Active, since
/// more may still be added; it finishes the day after, or the moment the last
/// entry is ticked once that day has come. A plan with no dates finishes when
/// everything is done. An empty plan is never finished. Active: Started is
/// on, or the plan's first date has come. Otherwise not started. A plan never
/// goes back to not started on its own after its end date. [today] defaults
/// to the app clock ([seasonClock]), so tests can fix the day.
PlanState planState(Plan plan, {DateTime? today}) {
  if (plan.items.isNotEmpty && plan.items.every((i) => i.done)) {
    final last = plan.lastDate;
    if (last == null ||
        dateOnly(last).isBefore(dateOnly(today ?? seasonClock()))) {
      return PlanState.finished;
    }
  }
  if (plan.started || planIsDue(plan, today: today)) return PlanState.active;
  return PlanState.notStarted;
}

/// Whether the plan's first date is today or past.
bool planIsDue(Plan plan, {DateTime? today}) {
  final first = plan.firstDate;
  if (first == null) return false;
  return !dateOnly(first).isAfter(dateOnly(today ?? seasonClock()));
}

/// The Started switches to turn on because a plan's first date has come,
/// so the switch always shows the real state.
List<SetPlanStarted> dueStarts(Library library, {DateTime? today}) => [
  for (final plan in library.plans)
    if (!plan.started && planIsDue(plan, today: today))
      SetPlanStarted(plan.id, true),
];

int doneCount(Plan plan) => plan.items.where((i) => i.done).length;

/// "Halloween 2026", or just the name when there is no year.
String planTitle(Plan plan) => plan.title;

/// The plan shown on the library home card: the first active one.
Plan? activePlan(Library library, {DateTime? today}) {
  for (final plan in library.plans) {
    if (planState(plan, today: today) == PlanState.active) return plan;
  }
  return null;
}
