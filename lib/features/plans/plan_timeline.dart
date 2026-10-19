import '../../data/models/plan.dart';
import '../../data/models/plan_item.dart';
import 'plan_dates.dart';

/// Where a timeline group sits relative to today (Plans › Plan with timing on).
enum TimelineState { past, current, future, undated }

/// Items that share the same "When", shown under one heading with a rail
/// on the left. The rail is filled for the past, filled up to today for
/// the current group, and empty for what is still to come.
class TimelineGroup {
  const TimelineGroup({
    required this.title,
    required this.dates,
    required this.state,
    required this.items,
    this.todayFraction,
  });

  /// "Earlier", "Last week", "This week", "Sat Oct 17", "Later" or
  /// "Whenever".
  final String title;

  /// "Oct 19–31", "One day", "No date".
  final String dates;
  final TimelineState state;
  final List<PlanItem> items;

  /// For the current group: how far today is through the period, 0 to 1.
  final double? todayFraction;
}

/// Groups a plan's items for the timeline by time, not by type (the Plans ›
/// Plan with timing on note). Buckets, in order: Earlier, Last week, This week,
/// then each future single day ("Sat Oct 17") and Later, by date, and Whenever
/// for undated items. Inside a bucket items follow the global type order
/// ([typeRank], lower first), then date, then the plan's order.
List<TimelineGroup> timelineGroups(
  Plan plan, {
  DateTime? today,
  int Function(PlanItem item)? typeRank,
}) {
  final now = dateOnly(today ?? DateTime.now());
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  final weekEnd = weekStart.add(const Duration(days: 6));
  final lastWeekStart = weekStart.subtract(const Duration(days: 7));

  final earlier = <PlanItem>[];
  final lastWeek = <PlanItem>[];
  final thisWeek = <PlanItem>[];
  final later = <PlanItem>[];
  final days = <DateTime, List<PlanItem>>{};
  final undated = <PlanItem>[];
  for (final item in plan.items) {
    final when = item.when;
    if (when == null) {
      undated.add(item);
      continue;
    }
    final from = dateOnly(when.from), to = dateOnly(when.to);
    if (to.isBefore(lastWeekStart)) {
      earlier.add(item);
    } else if (to.isBefore(weekStart)) {
      lastWeek.add(item);
    } else if (!from.isAfter(weekEnd)) {
      thisWeek.add(item);
    } else if (when.isSingleDay) {
      days.putIfAbsent(from, () => []).add(item);
    } else {
      later.add(item);
    }
  }

  List<PlanItem> ordered(List<PlanItem> items) {
    final order = {for (final (i, item) in plan.items.indexed) item: i};
    return [...items]..sort((a, b) {
      final t = (typeRank?.call(a) ?? 0).compareTo(typeRank?.call(b) ?? 0);
      if (t != 0) return t;
      final fa = a.when?.from, fb = b.when?.from;
      if (fa != null && fb != null) {
        final d = fa.compareTo(fb);
        if (d != 0) return d;
      }
      return order[a]!.compareTo(order[b]!);
    });
  }

  String span(List<PlanItem> items) {
    var from = items.first.when!.from, to = items.first.when!.to;
    for (final item in items) {
      if (item.when!.from.isBefore(from)) from = item.when!.from;
      if (item.when!.to.isAfter(to)) to = item.when!.to;
    }
    return formatWhen(
      PlanWhen(from: from, to: to),
      year: plan.year,
    );
  }

  DateTime start(List<PlanItem> items) => items
      .map((i) => dateOnly(i.when!.from))
      .reduce((a, b) => a.isBefore(b) ? a : b);

  final groups = <TimelineGroup>[
    if (earlier.isNotEmpty)
      TimelineGroup(
        title: 'Earlier',
        dates: span(earlier),
        state: TimelineState.past,
        items: ordered(earlier),
      ),
    if (lastWeek.isNotEmpty)
      TimelineGroup(
        title: 'Last week',
        dates: span(lastWeek),
        state: TimelineState.past,
        items: ordered(lastWeek),
      ),
    if (thisWeek.isNotEmpty)
      TimelineGroup(
        title: 'This week',
        dates: formatWhen(
          PlanWhen(from: weekStart, to: weekEnd),
          year: plan.year,
        ),
        state: TimelineState.current,
        items: ordered(thisWeek),
        todayFraction: (now.difference(weekStart).inDays + 0.5) / 7,
      ),
  ];
  final future =
      <(DateTime, int, TimelineGroup)>[
        for (final MapEntry(key: day, value: items) in days.entries)
          (
            day,
            0,
            TimelineGroup(
              title: formatWeekdayDay(day),
              dates: 'One day',
              state: TimelineState.future,
              items: ordered(items),
            ),
          ),
        if (later.isNotEmpty)
          (
            start(later),
            1,
            TimelineGroup(
              title: 'Later',
              dates: span(later),
              state: TimelineState.future,
              items: ordered(later),
            ),
          ),
      ]..sort((a, b) {
        final d = a.$1.compareTo(b.$1);
        return d != 0 ? d : a.$2.compareTo(b.$2);
      });
  groups.addAll(future.map((f) => f.$3));
  if (undated.isNotEmpty) {
    groups.add(
      TimelineGroup(
        title: 'Whenever',
        dates: 'No date',
        state: TimelineState.undated,
        items: ordered(undated),
      ),
    );
  }
  return groups;
}
