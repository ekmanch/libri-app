import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'row_ink_well.dart';

/// A row in Settings and the connection screen (Settings › Library connection):
/// a label on the left, a muted value, a hairline under it. With [onTap] the
/// row is a button and ends in a chevron.
///
/// The value is never centered. A single row puts it on the right (Settings).
/// A block of several related details passes [labelWidth]: the label then
/// sits in a fixed column and the value starts right after it, left
/// aligned, so the values of neighboring rows line up (the GitHub rows of
/// Settings › Library connection).
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.value,
    this.detail,
    this.onTap,
    this.minHeight = 52,
    this.labelWidth,
    this.emphasizedValue = false,
  });

  final String label;
  final String? value;

  /// A second line under the label, left-aligned in the secondary color,
  /// for a value too long to sit on the right ("When you open Libri, then
  /// every 5 minutes").
  final String? detail;
  final VoidCallback? onTap;
  final double minHeight;

  /// Width of the label column. Null lets the label take its natural width
  /// and pushes the value to the right edge.
  final double? labelWidth;

  /// The value in the text color rather than the muted one: the counts on
  /// the kind rows of Settings › Upcoming releases, where muted reads as
  /// "nothing followed".
  final bool emphasizedValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final fixedLabel = labelWidth != null;
    final Widget labelText = detail == null
        ? Text(label, style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16))
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 14,
                    height: 1.35,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          );
    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          // In a block of details the label column is [labelWidth] wide
          // whatever its text. A single row with a value gives the label
          // its natural width and the value all the rest, so the value
          // reaches the right edge. A row without a value (the two-line
          // detail rows) lets the text wrap across the width.
          // A two-line label with a short value (the kind rows of Settings ›
          // Upcoming releases, "Shows and anime / New seasons · 119") gives
          // the label the width and the value its natural size.
          if (fixedLabel)
            SizedBox(width: labelWidth, child: labelText)
          else if (value != null && detail == null)
            labelText
          else
            Expanded(child: labelText),
          if (value != null) ...[
            const SizedBox(width: 12),
            if (detail != null && !fixedLabel)
              Text(
                value!,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  height: 1.3,
                  color: emphasizedValue
                      ? theme.colorScheme.onSurface
                      : colors.muted,
                ),
              )
            else
              Expanded(
                child: Text(
                  value!,
                  textAlign: fixedLabel ? TextAlign.start : TextAlign.end,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 14,
                    height: 1.3,
                    color: emphasizedValue
                        ? theme.colorScheme.onSurface
                        : colors.muted,
                  ),
                ),
              ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 6),
            StrokeIcon(AppIcons.chevronRight, size: 18, color: colors.muted),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: RowInkWell(onTap: onTap, child: row),
    );
  }
}
