import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/released.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/fitted_title.dart';
import '../../widgets/labels.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/wheel_picker.dart';

/// The first year on the wheel; older years are typed (Add / edit entry ›
/// Released: type the year).
const releasedWheelFirstYear = 1800;

/// How far past this year the wheel reaches.
const releasedWheelYearsAhead = 5;

/// Opens the Released picker (Add / edit entry › Released: wheel picker): three
/// wheels, Year, Month and Day. Month and Day start on "—", so the value can be
/// a year, a year and month, or a full date. Every change is applied at once
/// through [onChanged]; Done and swiping down both just close. Clear hands back
/// null. [today] fixes the current year, for tests and captures.
Future<void> showReleasedSheet(
  BuildContext context, {
  required Released? initial,
  required ValueChanged<Released?> onChanged,
  DateTime? today,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => ReleasedSheet(
      initial: initial,
      onChanged: onChanged,
      today: today ?? DateTime.now(),
    ),
  );
}

class ReleasedSheet extends StatefulWidget {
  const ReleasedSheet({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.today,
  });

  final Released? initial;
  final ValueChanged<Released?> onChanged;
  final DateTime today;

  static const hint =
      'Tap the year to type it. "—" leaves the month or day out.';

  @override
  State<ReleasedSheet> createState() => _ReleasedSheetState();
}

class _ReleasedSheetState extends State<ReleasedSheet> {
  /// Whether the field has a value. The wheels show something either way
  /// (the current year when nothing is set), but only a wheel moved or a
  /// year typed turns that into a value.
  late bool _set = widget.initial != null;
  late int _year = widget.initial?.year ?? widget.today.year;

  /// 0 means "—".
  late int _month = widget.initial?.month ?? 0;
  late int _day = widget.initial?.day ?? 0;

  bool _typing = false;
  late final _typed = TextEditingController();

  late final List<String> _years = [
    for (
      var y = releasedWheelFirstYear;
      y <= widget.today.year + releasedWheelYearsAhead;
      y++
    )
      '$y',
  ];

  static const _months = ['—', ...monthAbbreviations];

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// The days of the chosen month; only "—" until a month is picked.
  int get _daysInMonth => _month == 0 ? 0 : DateTime(_year, _month + 1, 0).day;

  List<String> get _days => ['—', for (var d = 1; d <= _daysInMonth; d++) '$d'];

  Released? get _value => !_set
      ? null
      : Released(
          _year,
          _month == 0 ? null : _month,
          _month == 0 || _day == 0 ? null : _day,
        );

  void _update(void Function() change) {
    setState(() {
      change();
      _set = true;
      // A day the new month does not have: the month's last day instead.
      if (_day > _daysInMonth) _day = _daysInMonth;
    });
    widget.onChanged(_value);
  }

  void _clear() {
    setState(() {
      _set = false;
      _year = widget.today.year;
      _month = 0;
      _day = 0;
      _typing = false;
    });
    widget.onChanged(null);
  }

  void _startTyping() {
    _typed.text = '$_year';
    setState(() => _typing = true);
  }

  void _onTyped(String text) {
    if (text.length != 4) return;
    final year = int.parse(text);
    if (year < 1) return;
    _update(() => _year = year);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final value = _value;
    final yearIndex = (_year - releasedWheelFirstYear).clamp(
      0,
      _years.length - 1,
    );
    final titleStyle = theme.textTheme.headlineSmall!;
    return SheetFrame(
      // Scrolls when the keyboard leaves it too little room (Add / edit entry ›
      // Released: type the year).
      scrollable: true,
      // The sheet's own header, so the title steps down a size when Clear
      // and Done leave it no room at a large text size.
      header: Row(
        children: [
          Expanded(
            child: FittedTitle(
              'Released',
              style: titleStyle,
              sizes: [titleStyle.fontSize!, 20, 18],
            ),
          ),
          if (_set) ...[
            AppButton(
              label: 'Clear',
              kind: AppButtonKind.outline,
              compact: true,
              onPressed: _clear,
            ),
            const SizedBox(width: 8),
          ],
          AppButton(
            label: 'Done',
            compact: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            value == null ? 'Not set' : releasedLongLabel(value),
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 10),
          Stack(
            children: [
              // The band behind the chosen row, across all three wheels.
              Positioned(
                left: 0,
                right: 0,
                top:
                    WheelColumn.captionHeight +
                    WheelColumn.itemExtent * (WheelColumn.visibleRows ~/ 2),
                height: WheelColumn.itemExtent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 115,
                    child: _typing
                        ? _YearField(controller: _typed, onChanged: _onTyped)
                        : WheelColumn(
                            caption: 'Year',
                            items: _years,
                            selected: yearIndex,
                            onChanged: (i) => _update(
                              () => _year = releasedWheelFirstYear + i,
                            ),
                            onTapSelected: _startTyping,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 100,
                    child: WheelColumn(
                      caption: 'Month',
                      items: _months,
                      selected: _month,
                      onChanged: (i) => _update(() => _month = i),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 80,
                    child: WheelColumn(
                      caption: 'Day',
                      items: _days,
                      selected: _day,
                      onChanged: (i) => _update(() => _day = i),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            ReleasedSheet.hint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The Year column while the year is typed (Add / edit entry › Released: type
/// the year): a numeric field in the middle row, where the chosen year was.
class _YearField extends StatelessWidget {
  const _YearField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: WheelColumn.captionHeight,
          child: Text(
            'Year',
            style: theme.textTheme.labelMedium!.copyWith(
              fontSize: 12,
              color: colors.muted,
            ),
          ),
        ),
        SizedBox(
          height: WheelColumn.height,
          child: Center(
            child: SizedBox(
              height: WheelColumn.itemExtent,
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textAlign: TextAlign.center,
                onChanged: onChanged,
                style: theme.textTheme.bodyLarge!.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  semanticCounterText: '',
                  counterText: '',
                  fillColor: theme.scaffoldBackgroundColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
