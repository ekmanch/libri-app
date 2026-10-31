import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models/entry_status.dart';
import '../data/models/media_type.dart';
import '../theme/app_theme.dart';
import 'labels.dart';

/// How the selected segment is shown.
enum SegmentedStyle {
  /// A neutral fill: status filters on a list screen, the theme picker.
  neutral,

  /// The accent fill: choosing a status in the entry details sheet.
  accent,
}

class SegmentOption<T> {
  const SegmentOption(this.value, this.label);
  final T value;
  final String label;
}

/// A row of segments, one selected. 48 dp tall, each at least 48 dp wide.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.style = SegmentedStyle.neutral,
    this.inset = false,
    this.trackColor,
    this.equalWidths = false,
  });

  final List<SegmentOption<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final SegmentedStyle style;

  /// True inside a sheet, where the track is a darker well ([LibraryColors.tray])
  /// instead of the surface color, which would vanish against the sheet.
  final bool inset;

  /// A track color of its own, without a border (the plan header's tabs).
  final Color? trackColor;

  /// Every segment the same width, like a two-column grid (Plans › New plan,
  /// and the tabs of Plan checklist).
  final bool equalWidths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final accent = style == SegmentedStyle.accent;
    final labelStyle = theme.textTheme.labelMedium!.copyWith(fontSize: 13.5);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor ?? (inset ? colors.tray : scheme.surface),
        borderRadius: BorderRadius.circular(14),
        border: inset || trackColor != null
            ? null
            : Border.all(color: colors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = equalWidths
              ? List.filled(
                  segments.length,
                  (constraints.maxWidth - gap * (segments.length - 1)) /
                      segments.length,
                )
              : segmentWidths(
                  labels: [for (final s in segments) s.label],
                  available: constraints.maxWidth,
                  measure: (label) => _textWidth(context, label, labelStyle),
                );
          final total =
              widths.fold(0.0, (a, b) => a + b) + gap * (segments.length - 1);
          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, segment) in segments.indexed) ...[
                if (i > 0) const SizedBox(width: gap),
                SizedBox(
                  width: widths[i],
                  child: _Segment(
                    label: segment.label,
                    style: labelStyle,
                    selected: segment.value == selected,
                    background: accent
                        ? scheme.primaryContainer
                        : colors.selectedFill,
                    foreground: accent
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    unselectedForeground: trackColor != null
                        ? colors.soft
                        : scheme.onSurfaceVariant,
                    onTap: () => onChanged(segment.value),
                  ),
                ),
              ],
            ],
          );
          // At a large text size the labels may not fit: the segments keep
          // their full labels and the row scrolls sideways.
          if (total <= constraints.maxWidth) return row;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          );
        },
      ),
    );
  }

  static const gap = 4.0;
  static const labelPadding = 8.0;

  /// The touch target rule: no segment narrower than this.
  static const minSegmentWidth = 48.0;

  /// Each segment gets its label width plus padding, and the leftover space
  /// is shared equally, like `flex: 1 1 auto` in the mockups. When the
  /// labels do not fit, each keeps its full width and the row scrolls.
  static List<double> segmentWidths({
    required List<String> labels,
    required double available,
    required double Function(String label) measure,
  }) {
    final n = labels.length;
    if (n == 0) return const [];
    final usable = available - gap * (n - 1);
    final content = [
      for (final l in labels)
        math.max(minSegmentWidth, measure(l) + 2 * labelPadding),
    ];
    final sum = content.fold(0.0, (a, b) => a + b);
    if (sum > usable) return content;
    final share = (usable - sum) / n;
    return [for (final c in content) c + share];
  }

  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.style,
    required this.selected,
    required this.background,
    required this.foreground,
    required this.unselectedForeground,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final bool selected;
  final Color background;
  final Color foreground;
  final Color unselectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? background : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SegmentedControl.labelPadding,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    color: selected ? foreground : unselectedForeground,
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

/// The status segments. With [includeAll] a null selection means "All".
/// [type] limits the choices, e.g. no In progress for a movie, and words
/// them: "Reading" for books.
class StatusSegmentedControl extends StatelessWidget {
  const StatusSegmentedControl({
    super.key,
    required this.selected,
    required this.onChanged,
    this.type,
    this.includeAll = false,
    this.style = SegmentedStyle.neutral,
    this.inset = false,
  });

  final EntryStatus? selected;
  final ValueChanged<EntryStatus?> onChanged;
  final MediaType? type;
  final bool includeAll;
  final SegmentedStyle style;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return SegmentedControl<EntryStatus?>(
      segments: [
        if (includeAll) const SegmentOption(null, 'All'),
        for (final status
            in type == null
                ? EntryStatus.values
                : EntryStatus.optionsFor(type!))
          SegmentOption(status, status.labelFor(type)),
      ],
      selected: selected,
      onChanged: onChanged,
      style: style,
      inset: inset,
    );
  }
}
