import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

/// A row in Settings (S6) and the connection screen (D6): a label on the
/// left, a muted value, a hairline under it. With [onTap] the row is a
/// button and ends in a chevron.
///
/// The value is never centered. A single row puts it on the right (S6).
/// A block of several related details passes [labelWidth]: the label then
/// sits in a fixed column and the value starts right after it, left
/// aligned, so the values of neighboring rows line up (the GitHub rows of
/// D6).
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.value,
    this.detail,
    this.onTap,
    this.minHeight = 52,
    this.labelWidth,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final fixedLabel = labelWidth != null;
    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          // The label keeps its natural width and the value gets the rest,
          // so a short value stays on one line where it can; with a fixed
          // [labelWidth] the label column is that wide whatever its text.
          Flexible(
            flex: fixedLabel ? 0 : 1,
            child: SizedBox(
              width: labelWidth,
              child: detail == null
                  ? Text(
                      label,
                      style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodyLarge!.copyWith(
                              fontSize: 16,
                            ),
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
                    ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value!,
                textAlign: fixedLabel ? TextAlign.start : TextAlign.end,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  height: 1.3,
                  color: colors.muted,
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
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
