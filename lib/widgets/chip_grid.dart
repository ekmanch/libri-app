import 'package:flutter/material.dart';

/// Equal-width chips in rows, like the CSS grids in Library › Filter sheet and
/// Add / edit entry. A last row with fewer chips keeps the column widths.
class ChipGrid extends StatelessWidget {
  const ChipGrid({
    super.key,
    required this.columns,
    required this.children,
    this.gap = 6,
  });

  final int columns;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      final row = children.sublist(
        start,
        (start + columns).clamp(0, children.length),
      );
      rows.add(
        Row(
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: i < row.length ? row[i] : const SizedBox()),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          row,
        ],
      ],
    );
  }
}

/// Chips in one row that share the width by the length of their labels, so
/// "In progress" gets more room than "DNF" and no label is cut. When they
/// do not fit (a large text size), the chips wrap onto more lines instead.
class FitChipRow extends StatelessWidget {
  const FitChipRow({
    super.key,
    required this.labels,
    required this.builder,
    this.gap = 6,
    this.chipPadding = 14,
  });

  final List<String> labels;

  /// Builds the chip for label [index].
  final Widget Function(int index) builder;
  final double gap;

  /// The chip's side padding, counted in its natural width.
  final double chipPadding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium!;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width + 2 * chipPadding + 2;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final natural = [for (final l in labels) measure(l)];
        final total =
            natural.fold(0.0, (a, b) => a + b) + gap * (labels.length - 1);
        if (total > constraints.maxWidth) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (var i = 0; i < labels.length; i++) builder(i)],
          );
        }
        final share = (constraints.maxWidth - total) / labels.length;
        return Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(width: natural[i] + share, child: builder(i)),
            ],
          ],
        );
      },
    );
  }
}
