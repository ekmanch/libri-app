import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/plan.dart';
import 'package:library_app/data/models/plan_item.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/features/plans/plan_progress.dart';

import '../../helpers/pump_app.dart';

void main() {
  final today = DateTime(2026, 10, 11);

  test('plan state from Started, its dates and its items', () {
    const empty = Plan(id: 'a', name: 'A');
    expect(planState(empty, today: today), PlanState.notStarted);
    // An empty plan is never finished, even when started.
    expect(
      planState(empty.copyWith(started: true), today: today),
      PlanState.active,
    );
    const some = Plan(
      id: 'b',
      name: 'B',
      items: [
        PlanItem(entry: 'x', done: true),
        PlanItem(entry: 'y'),
      ],
    );
    expect(planState(some, today: today), PlanState.notStarted);
    expect(
      planState(some.copyWith(started: true), today: today),
      PlanState.active,
    );
    expect(doneCount(some), 1);
    const all = Plan(
      id: 'c',
      name: 'C',
      year: 2025,
      items: [PlanItem(entry: 'x', done: true)],
    );
    expect(planState(all), PlanState.finished);
    expect(planTitle(all), 'C 2025');
    expect(planTitle(empty), 'A');
  });

  test('the first date makes a plan active and turns Started on', () {
    final dated = Plan(
      id: 'd',
      name: 'D',
      items: [
        PlanItem(
          entry: 'x',
          when: PlanWhen(
            from: DateTime(2026, 10, 20),
            to: DateTime(2026, 10, 22),
          ),
        ),
      ],
    );
    expect(planState(dated, today: today), PlanState.notStarted);
    final onTheDay = DateTime(2026, 10, 20);
    expect(planState(dated, today: onTheDay), PlanState.active);
    // Long after the end date it stays active until every entry is done.
    expect(planState(dated, today: DateTime(2027, 3, 1)), PlanState.active);
    final library = loadFixture().copyWith(plans: [dated]);
    expect(dueStarts(library, today: today), isEmpty);
    final starts = dueStarts(library, today: onTheDay);
    expect(starts.single.planId, 'd');
    final started = starts.single.apply(library).planById('d')!;
    expect(started.started, isTrue);
    expect(dueStarts(starts.single.apply(library), today: onTheDay), isEmpty);
  });

  test('a plan with everything done finishes only after its end date', () {
    final plan = Plan(
      id: 'e',
      name: 'E',
      started: true,
      items: [
        PlanItem(
          entry: 'x',
          done: true,
          when: PlanWhen(
            from: DateTime(2026, 10, 1),
            to: DateTime(2026, 10, 3),
          ),
        ),
        PlanItem(
          entry: 'y',
          done: true,
          when: PlanWhen(
            from: DateTime(2026, 10, 19),
            to: DateTime(2026, 10, 31),
          ),
        ),
        const PlanItem(entry: 'z', done: true),
      ],
    );
    expect(plan.lastDate, DateTime(2026, 10, 31));
    // Before and on the end date it stays Active: more may be added.
    expect(planState(plan, today: DateTime(2026, 10, 23)), PlanState.active);
    expect(planState(plan, today: DateTime(2026, 10, 31)), PlanState.active);
    // The first day after the end date finishes it on its own.
    expect(planState(plan, today: DateTime(2026, 11, 1)), PlanState.finished);
    // The default day is the app clock.
    seasonClock = () => DateTime(2026, 10, 30);
    addTearDown(() => seasonClock = DateTime.now);
    expect(planState(plan), PlanState.active);
    seasonClock = () => DateTime(2026, 11, 1);
    expect(planState(plan), PlanState.finished);
    // An entry left to do keeps it Active after the end date too.
    final open = plan.copyWith(
      items: [
        ...plan.items.take(2),
        const PlanItem(entry: 'z'),
      ],
    );
    expect(planState(open, today: DateTime(2026, 11, 1)), PlanState.active);
    // No dates: finished as soon as everything is done.
    final undated = plan.copyWith(
      items: [for (final i in plan.items) i.copyWith(when: null)],
    );
    expect(undated.lastDate, isNull);
    expect(
      planState(undated, today: DateTime(2026, 10, 23)),
      PlanState.finished,
    );
    // The home card keeps a plan that is all done until its end date.
    final library = loadFixture().copyWith(plans: [plan]);
    expect(activePlan(library, today: DateTime(2026, 10, 31))?.id, 'e');
    expect(activePlan(library, today: DateTime(2026, 11, 1)), isNull);
  });

  test('the fixture has Halloween 2026 as the active plan', () {
    final plan = activePlan(loadFixture());
    expect(plan?.id, 'halloween-2026');
  });
}
