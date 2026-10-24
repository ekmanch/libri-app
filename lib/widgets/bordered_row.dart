import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'row_ink_well.dart';

/// A tappable row between two hairlines: the rating, "When" and plans rows of
/// the details sheets (Library › Entry details; Plans › Entry details (timeline
/// on)).
class BorderedRow extends StatelessWidget {
  const BorderedRow({
    super.key,
    required this.onTap,
    required this.leading,
    required this.trailing,
    this.minHeight = 48,
    this.semanticsLabel,
    this.topBorder = true,
  });

  final VoidCallback onTap;
  final Widget leading;
  final Widget trailing;
  final double minHeight;
  final String? semanticsLabel;

  /// False for a row right under another, so the hairline is not doubled.
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final side = BorderSide(color: colors.surfaceHigh);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: topBorder ? side : BorderSide.none,
              bottom: side,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: leading),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// "Rating" on the left, "8 / 10" on the right, in the details rows' type.
class RowLabel extends StatelessWidget {
  const RowLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium!.copyWith(
        fontSize: 15,
        color: LibraryColors.of(context).muted,
      ),
    );
  }
}

class RowValue extends StatelessWidget {
  const RowValue(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium!.copyWith(fontSize: 15),
    );
  }
}
