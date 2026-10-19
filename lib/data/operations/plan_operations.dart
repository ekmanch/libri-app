import 'package:json_annotation/json_annotation.dart';

import '../models/entry_id.dart';
import '../models/library.dart';
import '../models/plan.dart';
import '../models/plan_item.dart';
import 'library_operation.dart';

part 'plan_operations.g.dart';

/// The plan's title for a summary, or its id when it is gone.
String _planTitle(Library library, String planId) =>
    library.planById(planId)?.title ?? planId;

String _entryTitle(Library library, String entryId) =>
    library.entryById(entryId)?.title ?? entryId;

Library _replacePlan(Library library, Plan plan) {
  final index = library.plans.indexWhere((p) => p.id == plan.id);
  if (index < 0) return library;
  final plans = [...library.plans];
  plans[index] = plan;
  return library.copyWith(plans: plans);
}

/// Appends a plan. A taken id gets a numeric suffix.
@JsonSerializable()
class AddPlan extends LibraryOperation {
  const AddPlan(this.plan);

  factory AddPlan.fromJson(Map<String, Object?> json) =>
      _$AddPlanFromJson(json);

  Map<String, Object?> toJson() => _$AddPlanToJson(this);

  final Plan plan;

  @override
  Library apply(Library library) {
    final id = EntryId.unique(plan.id, library.plans.map((p) => p.id));
    return library.copyWith(
      plans: [
        ...library.plans,
        plan.copyWith(id: id),
      ],
    );
  }

  @override
  String summary(Library before) => 'Add the plan ${plan.title}';
}

/// Replaces a plan in place, keeping its id and position.
@JsonSerializable()
class UpdatePlan extends LibraryOperation {
  const UpdatePlan(this.plan);

  factory UpdatePlan.fromJson(Map<String, Object?> json) =>
      _$UpdatePlanFromJson(json);

  Map<String, Object?> toJson() => _$UpdatePlanToJson(this);

  final Plan plan;

  @override
  Library apply(Library library) {
    if (library.planById(plan.id) == null) return library;
    return _replacePlan(library, plan).withUnusedTagsRemoved();
  }

  @override
  String summary(Library before) => 'Edit the plan ${plan.title}';
}

@JsonSerializable()
class DeletePlan extends LibraryOperation {
  const DeletePlan(this.planId);

  factory DeletePlan.fromJson(Map<String, Object?> json) =>
      _$DeletePlanFromJson(json);

  Map<String, Object?> toJson() => _$DeletePlanToJson(this);

  final String planId;

  @override
  Library apply(Library library) {
    if (library.planById(planId) == null) return library;
    return library
        .copyWith(plans: library.plans.where((p) => p.id != planId).toList())
        .withUnusedTagsRemoved();
  }

  @override
  String summary(Library before) =>
      'Delete the plan ${_planTitle(before, planId)}';
}

/// Adds an item to a plan, or replaces the item for the same entry in place.
@JsonSerializable()
class SetPlanItem extends LibraryOperation {
  const SetPlanItem(this.planId, this.item);

  factory SetPlanItem.fromJson(Map<String, Object?> json) =>
      _$SetPlanItemFromJson(json);

  Map<String, Object?> toJson() => _$SetPlanItemToJson(this);

  final String planId;
  final PlanItem item;

  @override
  Library apply(Library library) {
    final plan = library.planById(planId);
    if (plan == null) return library;
    final items = [...plan.items];
    final index = items.indexWhere((i) => i.entry == item.entry);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
    return _replacePlan(library, plan.copyWith(items: items));
  }

  /// Names the one thing that changed when it can: adding, ticking, the
  /// note or the date.
  @override
  String summary(Library before) {
    final title = _entryTitle(before, item.entry);
    final plan = _planTitle(before, planId);
    final old = before.planById(planId)?.itemFor(item.entry);
    if (old == null) return 'Add $title to $plan';
    final changed = old.copyWith(done: item.done);
    if (old.done != item.done && changed == item) {
      return item.done ? 'Tick $title in $plan' : 'Untick $title in $plan';
    }
    if (old.copyWith(note: item.note) == item) {
      return 'Edit the note on $title in $plan';
    }
    if (old.copyWith(when: item.when) == item) {
      return item.when == null
          ? 'Clear the date of $title in $plan'
          : 'Set the date of $title in $plan';
    }
    return 'Edit $title in $plan';
  }
}

/// Removes an entry from one plan. The entry itself stays.
@JsonSerializable()
class RemovePlanItem extends LibraryOperation {
  const RemovePlanItem(this.planId, this.entryId);

  factory RemovePlanItem.fromJson(Map<String, Object?> json) =>
      _$RemovePlanItemFromJson(json);

  Map<String, Object?> toJson() => _$RemovePlanItemToJson(this);

  final String planId;
  final String entryId;

  @override
  Library apply(Library library) {
    final plan = library.planById(planId);
    if (plan == null) return library;
    return _replacePlan(
      library,
      plan.copyWith(
        items: plan.items.where((i) => i.entry != entryId).toList(),
      ),
    );
  }

  @override
  String summary(Library before) =>
      'Remove ${_entryTitle(before, entryId)} from ${_planTitle(before, planId)}';
}

/// Turns a plan's Started switch on or off (Plans › Edit plan). The app also
/// turns it on when the plan's first date arrives.
@JsonSerializable()
class SetPlanStarted extends LibraryOperation {
  const SetPlanStarted(this.planId, this.started);

  factory SetPlanStarted.fromJson(Map<String, Object?> json) =>
      _$SetPlanStartedFromJson(json);

  Map<String, Object?> toJson() => _$SetPlanStartedToJson(this);

  final String planId;
  final bool started;

  @override
  Library apply(Library library) {
    final plan = library.planById(planId);
    if (plan == null || plan.started == started) return library;
    return _replacePlan(library, plan.copyWith(started: started));
  }

  @override
  String summary(Library before) => started
      ? 'Start ${_planTitle(before, planId)}'
      : 'Mark ${_planTitle(before, planId)} as not started';
}
