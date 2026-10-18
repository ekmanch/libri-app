import 'package:flutter/material.dart';

import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/warning_note.dart';
import 'first_run_flow.dart';

/// The answer to D18.
enum WhichLibrary { phone, gitHub }

/// D18: "Use this file" (F7) while a library is kept on the phone and the
/// chosen file is another one. This phone's replaces the file on GitHub;
/// the one on GitHub replaces the phone's library. Null for Cancel.
Future<WhichLibrary?> askWhichLibrary(
  BuildContext context, {
  required int phoneEntries,
  required RepoFile file,
}) {
  final n = file.entries ?? 0;
  return showAppDialog<WhichLibrary>(
    context,
    builder: (context) {
      final theme = Theme.of(context);
      final muted = theme.textTheme.bodyMedium!.copyWith(
        fontSize: 14,
        color: theme.colorScheme.onSurfaceVariant,
      );
      return AppDialog(
        title: 'Which library do you want to keep?',
        body:
            'This phone still has a library, and you picked a different '
            'file on GitHub.',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This phone · $phoneEntries '
              '${phoneEntries == 1 ? 'entry' : 'entries'}',
              style: muted,
            ),
            const SizedBox(height: 4),
            Text(
              'GitHub · ${file.path} · $n ${n == 1 ? 'entry' : 'entries'}',
              style: muted,
            ),
            const SizedBox(height: 12),
            const WarningNote(
              "This phone's replaces the file on GitHub. The one on GitHub "
              'replaces the library on this phone.',
            ),
          ],
        ),
        actionsLayout: DialogActionsLayout.column,
        actions: [
          AppButton(
            label: "This phone's",
            kind: AppButtonKind.neutral,
            onPressed: () => Navigator.pop(context, WhichLibrary.phone),
          ),
          AppButton(
            label: 'The one on GitHub',
            kind: AppButtonKind.destructive,
            onPressed: () => Navigator.pop(context, WhichLibrary.gitHub),
          ),
          AppButton(
            label: 'Cancel',
            kind: AppButtonKind.text,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    },
  );
}
