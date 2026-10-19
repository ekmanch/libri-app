import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/sync/sync_status.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/labels.dart';
import '../../widgets/warning_note.dart';
import 'sync_state.dart';

/// The conflict question (Library › Conflict: keep which copy?), from the
/// banner (Library › Sync conflict banner; Plans › Plans with the sync conflict
/// banner) and from Settings › Library connection: keep this phone's copy or
/// GitHub's. "Decide later" closes it and the banner stays. The choice goes to
/// [LibrarySync.resolveConflict].
Future<void> showConflictDialog(BuildContext context, WidgetRef ref) async {
  final status = ref.read(syncStatusProvider).value ?? SyncStatus.idle;
  final keepMine = await showAppDialog<bool>(
    context,
    builder: (context) => ConflictDialog(status: status),
  );
  if (keepMine == null) return;
  // The banner follows the real state again.
  ref.read(syncBannerProvider.notifier).follow();
  await ref.read(librarySyncProvider)?.resolveConflict(keepMine: keepMine);
}

class ConflictDialog extends StatelessWidget {
  const ConflictDialog({super.key, required this.status});

  final SyncStatus status;

  /// "This phone: 3 changes", or just that it was edited when the edits
  /// were made without a queue (a library kept on the phone).
  static String phoneLine(SyncStatus status) => switch (status.pendingCount) {
    0 => 'This phone: edited here',
    1 => 'This phone: 1 change',
    final n => 'This phone: $n changes',
  };

  /// "GitHub: last commit Oct 13, 20:12".
  static String gitHubLine(SyncStatus status) {
    final at = status.remoteChangedAt?.toLocal();
    if (at == null) return 'GitHub: changed since';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return 'GitHub: last commit ${monthAbbreviations[at.month - 1]} '
        '${at.day}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AppDialog(
      title: 'Keep which copy?',
      body:
          'The library changed on GitHub and on this phone since they last '
          'matched.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(phoneLine(status), style: muted),
          const SizedBox(height: 4),
          Text(gitHubLine(status), style: muted),
          const SizedBox(height: 12),
          const WarningNote(
            "Whichever you keep, the other copy's changes are gone. Earlier "
            "versions stay in the repo's history.",
          ),
        ],
      ),
      actionsLayout: DialogActionsLayout.column,
      actions: [
        AppButton(
          label: 'Keep mine',
          kind: AppButtonKind.neutral,
          onPressed: () => Navigator.pop(context, true),
        ),
        AppButton(
          label: "Keep GitHub's",
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: 'Decide later',
          kind: AppButtonKind.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
