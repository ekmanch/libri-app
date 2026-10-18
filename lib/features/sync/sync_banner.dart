import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../settings/connection_screen.dart';
import 'conflict_dialog.dart';
import 'sync_state.dart';

/// The sync and error banner under a top-level screen's title (A12).
/// Nothing when there is nothing to say.
class SyncBannerCard extends ConsumerWidget {
  const SyncBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(syncBannerProvider);
    if (banner == null) return const SizedBox.shrink();
    // Not found: say what is gone, then that nothing syncs.
    final missing = banner == SyncBanner.notFound
        ? ref.watch(syncStatusProvider).value?.missing
        : null;
    final body = missing == null
        ? banner.body
        : '${missingDetail(missing, ref.watch(libraryConnectionProvider))} '
              '${banner.body}';
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final dot = switch (banner) {
      SyncBanner.saving => theme.colorScheme.primary,
      SyncBanner.offline => colors.muted,
      _ => colors.dangerText,
    };
    void act() {
      switch (banner) {
        case SyncBanner.couldNotSave:
          // Sends the queue again; the banner follows the real state.
          ref.read(syncBannerProvider.notifier).follow();
          ref.read(librarySyncProvider)?.syncNow();
        case SyncBanner.tokenProblem || SyncBanner.notFound:
          openConnectionScreen(context);
        case SyncBanner.conflict:
          showConflictDialog(context, ref);
        case SyncBanner.saving || SyncBanner.offline:
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: banner.isError
                ? colors.dangerFill
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            // On light the surface is the page color, so the card needs
            // its shadow to show at all.
            boxShadow: banner.isError ? null : colors.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner.title,
                      style: theme.textTheme.titleMedium!.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontSize: 13,
                        height: 1.35,
                        color: colors.soft,
                      ),
                    ),
                  ],
                ),
              ),
              if (banner.actionLabel case final label?) ...[
                const SizedBox(width: 12),
                AppButton(
                  label: label,
                  kind: AppButtonKind.outline,
                  compact: true,
                  horizontalPadding: 12,
                  onPressed: act,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
