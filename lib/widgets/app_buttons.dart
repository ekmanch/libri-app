import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppButtonKind {
  /// Accent fill. At most one per screen or dialog.
  primary,

  /// Outline, main text color.
  outline,

  /// Neutral fill, main text color.
  neutral,

  /// No fill, the grey button outline, red text: Delete, Disconnect,
  /// Delete everywhere, Replace… Never a red fill, and never next to an
  /// accent-colored button.
  destructive,

  /// Plain text, 44 px tall: "Cancel" under a stack of choices.
  text,

  /// Raised fill with 14 px corners, main text: Edit on a details sheet
  /// (Library › Entry details; Plans › Entry details (timeline on)) and the
  /// actions under a pool row (Plans › All Halloween: add, edit, remove).
  soft,

  /// The [soft] shape with no fill, the grey outline and red text: Delete next
  /// to Edit on a details sheet (Library › Entry details) and under a pool row
  /// (Plans › All Halloween: add, edit, remove).
  softDestructive,
}

/// A 48 px stadium button. Use the theme's styles; never set colors here.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.compact = false,
    this.horizontalPadding,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;

  /// Shown before the label at 18 px.
  final Widget? icon;

  /// 44 px tall and only as wide as its label, e.g. "Done" on a sheet.
  final bool compact;

  /// Side padding of a [compact] button; 18 by default.
  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    // A label never wraps: "Create tag" beside Cancel at a large text size
    // shrinks a step instead, like a page title.
    final child = icon == null
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, softWrap: false),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: const IconThemeData(size: 18),
                child: icon!,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    final compactStyle = compact
        ? ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: horizontalPadding ?? 18),
            ),
          )
        : null;
    final softShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    ButtonStyle? style(ButtonStyle? kindStyle) => compactStyle == null
        ? kindStyle
        : (kindStyle ?? const ButtonStyle()).merge(compactStyle);
    return switch (kind) {
      AppButtonKind.primary => FilledButton(
        onPressed: onPressed,
        style: style(null),
        child: child,
      ),
      AppButtonKind.outline => OutlinedButton(
        onPressed: onPressed,
        style: style(null),
        child: child,
      ),
      AppButtonKind.neutral => FilledButton(
        onPressed: onPressed,
        style: style(
          FilledButton.styleFrom(
            backgroundColor: colors.neutralFill,
            foregroundColor: scheme.onSurface,
          ),
        ),
        child: child,
      ),
      AppButtonKind.destructive => OutlinedButton(
        onPressed: onPressed,
        style: style(
          OutlinedButton.styleFrom(foregroundColor: colors.dangerText),
        ),
        child: child,
      ),
      AppButtonKind.text => TextButton(
        onPressed: onPressed,
        style: style(null),
        child: child,
      ),
      AppButtonKind.soft => FilledButton(
        onPressed: onPressed,
        style: style(
          FilledButton.styleFrom(
            backgroundColor: colors.surfaceHigh,
            foregroundColor: scheme.onSurface,
            shape: softShape,
          ),
        ),
        child: child,
      ),
      AppButtonKind.softDestructive => OutlinedButton(
        onPressed: onPressed,
        style: style(
          OutlinedButton.styleFrom(
            foregroundColor: colors.dangerText,
            shape: softShape,
          ),
        ),
        child: child,
      ),
    };
  }
}
