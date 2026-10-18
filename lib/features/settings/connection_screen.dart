import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/sync/sync_status.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/warning_note.dart';
import '../first_run/first_run_flow.dart';
import '../sync/conflict_dialog.dart';
import '../sync/relative_time.dart';
import '../sync/sync_state.dart';

/// Opens D6 above everything, like Settings.
Future<void> openConnectionScreen(BuildContext context) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => const ConnectionScreen()));
}

/// Settings: library connection (D6). Status, the GitHub details (repo,
/// branch, file, token), how often the app checks for changes, and the
/// buttons to replace the token or disconnect.
class ConnectionScreen extends ConsumerWidget {
  const ConnectionScreen({super.key});

  static const _sectionPadding = EdgeInsets.fromLTRB(0, 20, 0, 2);

  /// Disconnect is two steps: D15 confirms, D16 asks what to do with the
  /// library on this phone. Cancel on either leaves everything as it was.
  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(libraryConnectionProvider).repository;
    final pending = ref.read(syncStatusProvider).value?.pendingCount ?? 0;
    final confirmed = await confirmDisconnect(
      context,
      repository: repository,
      pending: pending,
    );
    if (!confirmed || !context.mounted) return;
    final choice = await askAboutLocalLibrary(context);
    if (choice == null || !context.mounted) return;
    // Back to the Library: with the library kept it stays, deleted it
    // gives way to the first run (F2). The screens stacked above go first.
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(
      ref
          .read(libraryConnectionProvider.notifier)
          .disconnect(
            keepLibrary: choice == LocalLibraryChoice.keep,
            sync: ref.read(librarySyncProvider),
          ),
    );
  }

  /// Connect a repo again while the library is kept on the phone: F3 to
  /// F8 above everything, like Replace token.
  Future<void> _reconnect(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => const FirstRunFlow.reconnect()),
    );
  }

  /// The status card's first line.
  static String statusTitle(SyncStatus status) => switch (status.phase) {
    SyncPhase.idle => 'Connected',
    SyncPhase.checking => 'Checking for changes…',
    SyncPhase.saving => 'Saving…',
    SyncPhase.offline => 'Offline',
    SyncPhase.failed => 'Could not save to GitHub',
    SyncPhase.tokenProblem => 'GitHub refused the token',
    SyncPhase.conflict => 'Changed here and on GitHub',
    SyncPhase.notFound => 'Library not found on GitHub',
  };

  /// The status card's second line: what is gone (with the [connection]
  /// to name it), what is waiting, else when the phone last matched
  /// GitHub.
  static String statusDetail(
    SyncStatus status, {
    DateTime? now,
    LibraryConnection? connection,
  }) =>
      status.phase == SyncPhase.notFound &&
          status.missing != null &&
          connection != null
      ? missingDetail(status.missing!, connection)
      : status.phase == SyncPhase.conflict
      ? 'Pick which copy to keep'
      : status.pendingCount > 0
      ? '${status.pendingCount} '
            '${status.pendingCount == 1 ? 'change' : 'changes'} waiting to '
            'be saved'
      : lastSyncedLabel(status.lastSynced, now: now);

  /// "Last synced 3 minutes ago", or "Not synced yet".
  static String lastSyncedLabel(DateTime? lastSynced, {DateTime? now}) =>
      lastSynced == null
      ? 'Not synced yet'
      : 'Last synced ${relativeTime(lastSynced, now: now ?? DateTime.now())}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final connection = ref.watch(libraryConnectionProvider);
    final local = connection.keptLocally;
    final status = ref.watch(syncStatusProvider).value ?? SyncStatus.idle;
    final dot = local
        ? colors.muted
        : switch (status.phase) {
            SyncPhase.idle => colors.success,
            SyncPhase.checking || SyncPhase.saving => theme.colorScheme.primary,
            SyncPhase.offline => colors.muted,
            SyncPhase.failed ||
            SyncPhase.tokenProblem ||
            SyncPhase.conflict ||
            SyncPhase.notFound => colors.dangerText,
          };
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Library connection',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: colors.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                local ? 'Not connected' : statusTitle(status),
                                style: theme.textTheme.titleMedium!.copyWith(
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                local
                                    ? 'Your library is kept on this phone'
                                    : statusDetail(
                                        status,
                                        connection: connection,
                                      ),
                                style: theme.textTheme.bodySmall!.copyWith(
                                  fontSize: 13,
                                  fontStyle: FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!local) ...[
                          const SizedBox(width: 8),
                          if (status.phase == SyncPhase.conflict)
                            AppButton(
                              label: 'Choose',
                              kind: AppButtonKind.outline,
                              compact: true,
                              horizontalPadding: 14,
                              onPressed: () => showConflictDialog(context, ref),
                            )
                          else
                            AppButton(
                              label: 'Sync now',
                              kind: AppButtonKind.outline,
                              compact: true,
                              horizontalPadding: 14,
                              onPressed: () =>
                                  ref.read(librarySyncProvider)?.syncNow(),
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (!local) ...[
                    const SectionHeading('GitHub', padding: _sectionPadding),
                    SettingRow(
                      label: 'Repository',
                      value: connection.repository,
                      minHeight: 56,
                    ),
                    SettingRow(
                      label: 'Branch',
                      value: connection.branch,
                      minHeight: 56,
                    ),
                    SettingRow(
                      label: 'Data file',
                      value: connection.file,
                      minHeight: 56,
                    ),
                    const SettingRow(
                      label: 'Access token',
                      value: 'Saved on this phone',
                      minHeight: 56,
                    ),
                    const SectionHeading('Syncing', padding: _sectionPadding),
                    const SettingRow(
                      label: 'Check for changes',
                      detail: 'When you open Libri, then every 5 minutes',
                      minHeight: 56,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (local)
                    AppButton(
                      label: 'Connect to GitHub',
                      kind: AppButtonKind.outline,
                      onPressed: () => _reconnect(context),
                    )
                  else ...[
                    AppButton(
                      label: 'Replace token',
                      kind: AppButtonKind.outline,
                      onPressed: () => openReplaceTokenScreen(context),
                    ),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'Disconnect',
                      kind: AppButtonKind.destructive,
                      onPressed: () => _disconnect(context, ref),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What to do with the library on this phone when disconnecting (D16).
enum LocalLibraryChoice { keep, delete }

/// The first Disconnect step (D15). Resolves true when the user confirms.
/// With [pending] changes not yet on GitHub the dialog says they are lost
/// unless the library is kept, and the button reads "Disconnect anyway".
Future<bool> confirmDisconnect(
  BuildContext context, {
  required String repository,
  required int pending,
}) async {
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: 'Disconnect from GitHub?',
      body: 'Libri stops syncing with $repository.',
      note: pending > 0
          ? '$pending ${pending == 1 ? 'change has' : 'changes have'} not '
                'been saved to GitHub yet. They are lost unless you keep '
                'the library on this phone. Nothing on GitHub changes.'
          : 'Nothing on GitHub changes.',
      // "Disconnect anyway" does not fit half a row, so that variant
      // stacks its buttons like D4.
      actionsLayout: pending > 0
          ? DialogActionsLayout.column
          : DialogActionsLayout.row,
      actions: [
        if (pending > 0) ...[
          AppButton(
            label: 'Disconnect anyway',
            kind: AppButtonKind.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
          AppButton(
            label: 'Cancel',
            kind: AppButtonKind.text,
            onPressed: () => Navigator.pop(context, false),
          ),
        ] else ...[
          AppButton(
            label: 'Cancel',
            kind: AppButtonKind.outline,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(
            label: 'Disconnect',
            kind: AppButtonKind.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ],
    ),
  );
  return confirmed ?? false;
}

/// The second Disconnect step (D16): keep the library on the phone, delete
/// it, or cancel (null). Nothing is disconnected before this choice.
Future<LocalLibraryChoice?> askAboutLocalLibrary(BuildContext context) {
  return showAppDialog<LocalLibraryChoice>(
    context,
    builder: (context) => AppDialog(
      title: 'Keep your library on this phone?',
      body:
          'You can keep browsing and editing it. Changes stay on this phone '
          'until you connect a repo again.',
      content: const WarningNote(
        'If you delete it, Libri is empty until you connect a GitHub repo '
        'again. Your library on GitHub is not affected.',
      ),
      actionsLayout: DialogActionsLayout.column,
      actions: [
        AppButton(
          label: 'Keep it on this phone',
          kind: AppButtonKind.neutral,
          onPressed: () => Navigator.pop(context, LocalLibraryChoice.keep),
        ),
        AppButton(
          label: 'Delete it from this phone',
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, LocalLibraryChoice.delete),
        ),
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
