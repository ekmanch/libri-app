import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/plan.dart';
import 'package:library_app/data/models/plan_item.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/operations/operations.dart';

import '../../helpers/sample_library.dart';

void main() {
  test('AddPlan appends and keeps the id unique', () {
    final result = AddPlan(halloweenPlan.copyWith(year: 2027))
        .apply(sampleLibrary());
    expect(result.plans.length, 3);
    expect(result.plans.last.id, 'halloween-2026-2');
  });

  test(
    'UpdatePlan replaces in place and prunes tags, keeping plan-only tags',
    () {
      final library = sampleLibrary();
      final result = UpdatePlan(
        library.plans.last.copyWith(tags: const ['halloween']),
      ).apply(library);
      expect(result.plans.map((p) => p.id), [
        'halloween-2026',
        'christmas-2026',
      ]);
      expect(result.plans.last.tags, ['halloween']);
      expect(result.tags[TagCategory.season], ['halloween']);
      expect(
        UpdatePlan(const Plan(id: 'nope', name: 'x')).apply(library),
        library,
      );
    },
  );

  test('DeletePlan removes the plan and its now-unused tag', () {
    final result = const DeletePlan('christmas-2026').apply(sampleLibrary());
    expect(result.plans.map((p) => p.id), ['halloween-2026']);
    expect(result.tags[TagCategory.season], ['halloween']);
    expect(const DeletePlan('nope').apply(sampleLibrary()), sampleLibrary());
  });

  test('SetPlanItem adds or replaces the item for an entry', () {
    final library = sampleLibrary();
    final added = SetPlanItem(
      'halloween-2026',
      PlanItem(entry: dirt.id),
    ).apply(library);
    expect(added.plans.first.items.map((i) => i.entry), [mummy.id, dirt.id]);

    final replaced = SetPlanItem(
      'halloween-2026',
      PlanItem(entry: mummy.id, done: true),
    ).apply(added);
    expect(replaced.plans.first.items.map((i) => i.entry), [mummy.id, dirt.id]);
    expect(replaced.plans.first.items.first.done, isTrue);
    expect(
      SetPlanItem('nope', PlanItem(entry: dirt.id)).apply(library),
      library,
    );
  });

  test('RemovePlanItem keeps the entry itself', () {
    final result = RemovePlanItem(
      'halloween-2026',
      mummy.id,
    ).apply(sampleLibrary());
    expect(result.plans.first.items, isEmpty);
    expect(result.entryById(mummy.id), isNotNull);
  });

  test('AddTag adds under a category and ignores duplicates', () {
    final library = sampleLibrary();
    final added = const AddTag('cozy', [TagCategory.mood]).apply(library);
    expect(added.tags[TagCategory.mood], ['lighthearted', 'cozy']);
    final newCategory = const AddTag('studio-ghibli', [
      TagCategory.studios,
    ]).apply(library);
    expect(newCategory.tags[TagCategory.studios], ['studio-ghibli']);
    // A new category sits in declaration order, not at the end of the
    // map where a Dart map would put it: Studios lands before Other even
    // when Other was added first.
    final withOther = const AddTag('rewatch', [
      TagCategory.other,
    ]).apply(library);
    final studiosLast = const AddTag('pixar', [
      TagCategory.studios,
    ]).apply(withOther);
    expect(studiosLast.tags.keys.toList(), [
      TagCategory.genre,
      TagCategory.mood,
      TagCategory.season,
      TagCategory.studios,
      TagCategory.other,
    ]);
    expect(
      const AddTag('halloween', [TagCategory.other]).apply(library),
      library,
    );
  });
  test('plan operations summarize themselves', () {
    final library = sampleLibrary();
    final item = halloweenPlan.items.single;
    expect(
      AddPlan(halloweenPlan.copyWith(year: 2027)).summary(library),
      'Add the plan Halloween 2027',
    );
    expect(
      UpdatePlan(halloweenPlan).summary(library),
      'Edit the plan Halloween 2026',
    );
    expect(
      const DeletePlan('christmas-2026').summary(library),
      'Delete the plan Christmas',
    );
    expect(
      SetPlanItem('christmas-2026', PlanItem(entry: dirt.id)).summary(library),
      'Add Dirt to Christmas',
    );
    expect(
      SetPlanItem(halloweenPlan.id, item.copyWith(done: true)).summary(library),
      'Tick The Mummy in Halloween 2026',
    );
    expect(
      SetPlanItem(
        halloweenPlan.id,
        item.copyWith(note: 'With popcorn'),
      ).summary(library),
      'Edit the note on The Mummy in Halloween 2026',
    );
    expect(
      SetPlanItem(halloweenPlan.id, item.copyWith(when: null)).summary(library),
      'Clear the date of The Mummy in Halloween 2026',
    );
    expect(
      SetPlanItem(
        halloweenPlan.id,
        item.copyWith(done: true, note: 'x'),
      ).summary(library),
      'Edit The Mummy in Halloween 2026',
    );
    expect(
      RemovePlanItem(halloweenPlan.id, mummy.id).summary(library),
      'Remove The Mummy from Halloween 2026',
    );
    expect(
      const SetPlanStarted('christmas-2026', true).summary(library),
      'Start Christmas',
    );
    expect(
      const AddTag('cozy', [TagCategory.mood]).summary(library),
      'Add the tag #cozy',
    );
  });
}
