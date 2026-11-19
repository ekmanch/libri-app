import 'package:flutter/material.dart';

import '../data/models/media_type.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'row_ink_well.dart';
import 'type_kicker.dart';

/// Uppercase section label, muted. With a [type] it heads that type's
/// group (a plan's Movies, Shows…): in the type's color on dark; on light,
/// where a type color is only a fill, the type's dot and the name in the
/// text color. Optional [trailing] text on the right, such as a count, or an
/// [action] link there in the accent with a chevron ("See all 7" on Library ›
/// Home), a 44 px button of its own. With [onTap] the heading is a 44 px
/// button with a chevron after the label.
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.label, {
    super.key,
    this.color,
    this.type,
    this.trailing,
    this.action,
    this.onAction,
    this.onTap,
    this.semanticsLabel,
    this.padding = const EdgeInsets.fromLTRB(0, 14, 0, 2),
  }) : assert(trailing == null || action == null);

  final String label;

  /// Defaults to the muted label color.
  final Color? color;

  /// The type this heading groups by.
  final MediaType? type;
  final String? trailing;

  /// A link at the end of the row, in the accent, with a chevron after it.
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  /// Screen reader label for the button, e.g. "Show all movies".
  final String? semanticsLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final type = this.type;
    final dotted = type != null && colors.typeColorsAreFills;
    final color = dotted
        ? theme.colorScheme.onSurface
        : type != null
        ? colors.forType(type)
        : this.color;
    final style = theme.textTheme.labelSmall!.copyWith(color: color);
    final words = Text(
      label.toUpperCase(),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final Widget text = !dotted
        ? words
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TypeDot(colors.forType(type)),
              const SizedBox(width: 7),
              Flexible(child: words),
            ],
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
        if (action case final action?)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AccentColors.of(context).link,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              textStyle: theme.textTheme.labelMedium,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action),
                const SizedBox(width: 2),
                const StrokeIcon(AppIcons.chevronRightBold, size: 16),
              ],
            ),
          ),
      ],
    );
    if (onTap == null) {
      return Padding(
        // The action is a 48 px button that the label centers on, so the
        // row gives up some top padding to end up where a plain heading does.
        padding: action == null
            ? padding
            : padding.copyWith(top: padding.top - 4, bottom: 0),
        child: row,
      );
    }
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
