import '../../data/models/entry_id.dart';
import '../../data/models/library.dart';
import '../../data/models/plan.dart';
import 'plan_progress.dart';

/// A plan id from its name and year: "halloween-2026", "summer-vacation".
String newPlanId(String name, int? year, Iterable<String> existingIds) {
  final slug = slugify([name, if (year != null) '$year'].join(' '));
  return EntryId.unique(slug.isEmpty ? 'plan' : slug, existingIds);
}

/// Plans with the same name as [plan], newest year first; [plan] included.
/// These are the choices in the year chip on the plan screen (Plans › Plan
/// checklist).
List<Plan> planYears(Library library, Plan plan) {
  final same = library.plans
      .where((p) => p.name.toLowerCase() == plan.name.toLowerCase())
      .toList();
  same.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
  return same;
}

/// The year a copy of [plan] would get: the year after it, or after this
/// year when the plan has none.
int nextYearFor(Plan plan, {DateTime? today}) =>
    (plan.year ?? (today ?? DateTime.now()).year) + 1;

/// A new plan built from [source] (Plans › New plan, "Copy a plan"): same
/// linked tags and switches, and the items that were not finished, without
/// their dates and checkmarks. The caller gives it a name, year and id.
Plan copyPlan(
  Plan source, {
  required String id,
  required String name,
  required int? year,
}) => Plan(
  id: id,
  name: name,
  year: year,
  tags: source.tags,
  timeline: source.timeline,
  seasonalTheme: source.seasonalTheme,
  items: [
    for (final item in source.items)
      if (!item.done) item.copyWith(done: false, when: null),
  ],
);

/// The first unfinished items, for "Next up" on the plans overview (Plans ›
/// Plans overview).
List<String> nextUp(Plan plan, Library library, {int count = 2}) => [
  for (final item in plan.items)
    if (!item.done)
      if (library.entryById(item.entry) case final entry?) entry.title,
].take(count).toList();

/// "Empty, linked to #christmas", "Linked to #halloween", or "6 entries".
String planSubtitle(Plan plan) {
  final tags = plan.tags.map((t) => '#$t').join(', ');
  if (plan.items.isEmpty) {
    return tags.isEmpty ? 'Empty' : 'Empty, linked to $tags';
  }
  if (tags.isNotEmpty) return 'Linked to $tags';
  final n = plan.items.length;
  return '$n ${n == 1 ? 'entry' : 'entries'}';
}

/// "2 of 6 done".
String progressLabel(Plan plan) =>
    '${doneCount(plan)} of ${plan.items.length} done';
