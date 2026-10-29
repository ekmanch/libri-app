import 'package:freezed_annotation/freezed_annotation.dart';

import 'plan_item.dart';

part 'plan.freezed.dart';
part 'plan.g.dart';

/// A named list of entries, for example "Halloween 2026". An entry matches
/// the plan's tags if it has any of them.
@freezed
abstract class Plan with _$Plan {
  const Plan._();

  const factory Plan({
    required String id,
    required String name,
    int? year,
    @Default([]) List<String> tags,
    @Default(false) bool timeline,
    @JsonKey(name: 'seasonal_theme') @Default(false) bool seasonalTheme,

    /// Set by the Started switch in Plans › Edit plan, and by the app when the
    /// plan's first date arrives. Never cleared on its own.
    @Default(false) bool started,
    @Default([]) List<PlanItem> items,
  }) = _Plan;

  factory Plan.fromJson(Map<String, Object?> json) => _$PlanFromJson(json);

  /// The earliest "When" among the items, or null when none has one.
  DateTime? get firstDate {
    DateTime? first;
    for (final item in items) {
      final from = item.when?.from;
      if (from != null && (first == null || from.isBefore(first))) {
        first = from;
      }
    }
    return first;
  }

  /// The latest "When" end among the items, or null when none has one: the
  /// plan's end date, after which a plan with everything done is Finished.
  DateTime? get lastDate {
    DateTime? last;
    for (final item in items) {
      final to = item.when?.to;
      if (to != null && (last == null || to.isAfter(last))) last = to;
    }
    return last;
  }

  /// The name with the year, as the UI shows it: "Halloween 2026".
  String get title => year == null ? name : '$name $year';

  PlanItem? itemFor(String entryId) {
    for (final item in items) {
      if (item.entry == entryId) return item;
    }
    return null;
  }
}
