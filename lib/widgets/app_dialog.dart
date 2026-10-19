import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How the dialog's buttons are laid out.
enum DialogActionsLayout {
  /// Two buttons side by side: Cancel on the left, the action on the right.
  row,

  /// A vertical stack of choices, usually ending in a text "Cancel".
  column,
}

/// A centered dialog: title, body, optional note, buttons.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.leading,
    this.body,
    this.content,
    this.note,
    required this.actions,
    this.actionsLayout = DialogActionsLayout.row,
  });

  /// Above the title: the key in its amber circle (Library › Token expires
  /// soon).
  final Widget? leading;

  final String title;
  final String? body;

  /// Anything between the body and the note: a rich-text body
  /// (Add / edit entry › New tag: a similar one exists) or the category chips
  /// of Add / edit entry › New tag: confirm and pick a category.
  final Widget? content;

  /// A quieter second paragraph, e.g. what happens in the GitHub history.
  final String? note;
  final List<Widget> actions;
  final DialogActionsLayout actionsLayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Dialog(
      // Scrolls only when the content is taller than the screen, e.g. the
      // category chips of Add / edit entry › New tag: confirm and pick a
      // category at a large text size.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (leading != null) ...[
              Align(alignment: Alignment.centerLeft, child: leading),
              const SizedBox(height: 12),
            ],
            Text(title, style: theme.textTheme.titleLarge),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(
                body!,
                style: theme.textTheme.bodyMedium!.copyWith(color: colors.soft),
              ),
            ],
            if (content != null) ...[const SizedBox(height: 12), content!],
            if (note != null) ...[
              const SizedBox(height: 12),
              Text(
                note!,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  color: colors.muted,
                ),
              ),
            ],
            const SizedBox(height: 20),
            switch (actionsLayout) {
              DialogActionsLayout.row => Row(
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: action),
                  ],
                ],
              ),
              DialogActionsLayout.column => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    action,
                  ],
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Opens a dialog styled by the theme, on the root navigator so it covers
/// the floating navigation.
///
/// A text field behind the dialog gives up its focus first, so it does not
/// take it back, keyboard and all, when the dialog closes.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool inheritTheme = false,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final theme = Theme.of(context);
  return showDialog<T>(
    context: context,
    useRootNavigator: true,
    builder: (context) => inheritTheme
        ? Theme(data: theme, child: builder(context))
        : builder(context),
  );
}
