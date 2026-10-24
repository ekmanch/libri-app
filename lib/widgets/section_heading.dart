import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'row_ink_well.dart';

/// Uppercase section label, in the type color on the library home, muted
/// elsewhere. Optional [trailing] text on the right, such as a count. With
/// [onTap] the heading is a 44 px button with a chevron after the label.
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.label, {
    super.key,
    this.color,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
    this.padding = const EdgeInsets.fromLTRB(0, 14, 0, 2),
  });

  final String label;

  /// Defaults to the muted label color.
  final Color? color;
  final String? trailing;
  final VoidCallback? onTap;

  /// Screen reader label for the button, e.g. "Show all movies".
  final String? semanticsLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final style = theme.textTheme.labelSmall!.copyWith(color: color);
    final text = Text(
      label.toUpperCase(),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final row = Row(
      children: [
        Expanded(
          child: onTap == null
              ? text
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: text),
                    const SizedBox(width: 4),
                    StrokeIcon(
                      AppIcons.chevronRightBold,
                      size: 16,
                      color: color ?? colors.muted,
                    ),
                  ],
                ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
          ),
      ],
    );
    if (onTap == null) return Padding(padding: padding, child: row);
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: semanticsLabel != null,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: padding,
          alignment: Alignment.centerLeft,
          child: row,
        ),
      ),
    );
  }
}
