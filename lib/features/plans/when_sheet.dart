import 'package:flutter/material.dart';

import '../../data/models/plan_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/chips.dart';
import '../../widgets/labels.dart';
import '../../widgets/sheet_frame.dart';
import 'plan_dates.dart';

/// What the When picker was closed with. [when] null means no date.
@immutable
class WhenChoice {
  const WhenChoice(this.when);

  final PlanWhen? when;
}

/// A day or a period for a plan item (Plans › When: a day or a period). One tap
/// picks a day, a second tap stretches it to a period, a third starts over.
/// Resolves with null when dismissed.
Future<WhenChoice?> showWhenSheet(
  BuildContext context, {
  required PlanWhen? current,
  DateTime? today,
}) {
  return showAppSheet<WhenChoice>(
    context,
    inheritTheme: true,
    builder: (context) => WhenSheet(current: current, today: today),
  );
}

class WhenSheet extends StatefulWidget {
  const WhenSheet({super.key, required this.current, this.today});

  final PlanWhen? current;
  final DateTime? today;

  @override
  State<WhenSheet> createState() => _WhenSheetState();
}

class _WhenSheetState extends State<WhenSheet> {
  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late DateTime? _from = widget.current?.from;
  late DateTime? _to = widget.current == null || widget.current!.isSingleDay
      ? null
      : widget.current!.to;
  late DateTime _month = DateTime(
    (_from ?? _today).year,
    (_from ?? _today).month,
  );

  PlanWhen? get _value =>
      _from == null ? null : PlanWhen(from: _from!, to: _to ?? _from!);

  void _tap(DateTime day) {
    setState(() {
      if (_from == null || _to != null) {
        _from = day;
        _to = null;
      } else if (day.isBefore(_from!)) {
        _to = _from;
        _from = day;
      } else if (day == _from) {
        _to = null;
      } else {
        _to = day;
      }
    });
  }

  void _pickWeek(int weeksAhead) {
    final monday = _today
        .subtract(Duration(days: _today.weekday - 1))
        .add(Duration(days: 7 * weeksAhead));
    setState(() {
      _from = monday;
      _to = monday.add(const Duration(days: 6));
      _month = DateTime(monday.year, monday.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final value = _value;
    final summary = value == null
        ? 'No date (Whenever)'
        : formatWhen(value, year: _today.year);
    final firstWeekday = _month.weekday; // 1 = Monday.
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 1; i < firstWeekday; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return SheetFrame(
      header: Row(
        children: [
          Expanded(child: Text('When', style: theme.textTheme.titleLarge)),
          AppButton(
            label: 'Done',
            compact: true,
            onPressed: () => Navigator.pop(context, WhenChoice(value)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(
                label: 'This week',
                selected: false,
                style: PillChipStyle.accent,
                horizontalPadding: 13,
                onTap: () => _pickWeek(0),
              ),
              PillChip(
                label: 'Next week',
                selected: false,
                style: PillChipStyle.accent,
                horizontalPadding: 13,
                onTap: () => _pickWeek(1),
              ),
              PillChip(
                label: 'No date',
                selected: false,
                style: PillChipStyle.accent,
                horizontalPadding: 13,
                onTap: () => setState(() {
                  _from = null;
                  _to = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Transform.translate(
                offset: const Offset(-12, 0),
                child: IconButton(
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                  tooltip: 'Previous month',
                  color: scheme.onSurface,
                  icon: const StrokeIcon(AppIcons.back, size: 20),
                ),
              ),
              Expanded(
                child: Text(
                  '${monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Transform.translate(
                offset: const Offset(12, 0),
                child: IconButton(
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                  tooltip: 'Next month',
                  color: scheme.onSurface,
                  icon: const StrokeIcon(AppIcons.chevronRight, size: 20),
                ),
              ),
            ],
          ),
          Row(
            children: [
              for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: Center(
                      child: Text(
                        w,
                        style: theme.textTheme.labelMedium!.copyWith(
                          fontSize: 12,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < cells.length ~/ 7; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 2),
              child: Stack(
                children: [
                  // The range band is one shape per week row, so there are no
                  // seams between the days (Plans › When: a day or a period).
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BandPainter(
                        span: bandSpan(
                          cells.sublist(row * 7, row * 7 + 7),
                          _from,
                          _to,
                        ),
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.10,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final day in cells.sublist(row * 7, row * 7 + 7))
                        Expanded(
                          child: day == null
                              ? const SizedBox(height: 44)
                              : _DayCell(
                                  day: day,
                                  from: _from,
                                  to: _to,
                                  onTap: () => _tap(day),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.surfaceHigh)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Selected',
                    style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
                  ),
                ),
                Text(summary, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.from,
    required this.to,
    required this.onTap,
  });

  final DateTime day;
  final DateTime? from;
  final DateTime? to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lo = from, hi = to ?? from;
    final isEnd = lo != null && (day == lo || day == hi);
    final inRange =
        lo != null && hi != null && day.isAfter(lo) && day.isBefore(hi);
    return Semantics(
      button: true,
      selected: isEnd || inRange,
      label: formatWeekdayDay(day),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isEnd ? scheme.primaryContainer : null,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isEnd ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the range band runs in one week row of [days] (null for blanks),
/// in cell units from the row's left edge: from the center of the start
/// day to the center of the end day, or to the row's edge where the range
/// carries on into the next or previous row. Null when the row has no band,
/// and for a single day.
@visibleForTesting
(double, double)? bandSpan(List<DateTime?> days, DateTime? from, DateTime? to) {
  final lo = from, hi = to;
  if (lo == null || hi == null || hi == lo) return null;
  int? first, last;
  for (final (i, day) in days.indexed) {
    if (day == null || day.isBefore(lo) || day.isAfter(hi)) continue;
    first ??= i;
    last = i;
  }
  if (first == null || last == null) return null;
  final left = days[first] == lo
      ? first + 0.5
      : (first == 0 ? 0.0 : first.toDouble());
  final right = days[last] == hi
      ? last + 0.5
      : (last == days.length - 1 ? days.length.toDouble() : last + 1.0);
  return right > left ? (left, right) : null;
}

class _BandPainter extends CustomPainter {
  const _BandPainter({required this.span, required this.color});

  final (double, double)? span;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = span;
    if (s == null) return;
    final cell = size.width / 7;
    // As tall as the day dots and centered on them; square ends, hidden
    // under the start and end dots.
    const height = 40.0;
    final top = (size.height - height) / 2;
    canvas.drawRect(
      Rect.fromLTWH(s.$1 * cell, top, (s.$2 - s.$1) * cell, height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.span != span || old.color != color;
}
