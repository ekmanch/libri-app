import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/library.dart';
import '../../data/models/plan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_header.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../settings/settings_screen.dart';
import '../shell/app_shell.dart';
import '../shell/floating_nav_bar.dart';
import '../sync/sync_banner.dart';
import 'plan_builders.dart';
import 'plan_form_screen.dart';
import 'plan_progress.dart';
import 'plan_screen.dart';

/// The plans overview (Plans › Plans overview): active plans as cards with
/// their progress and what is next, then the ones not started and the finished
/// ones as rows.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).value;
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);

    List<Plan> inState(PlanState state) => (library?.plans ?? const [])
        .where((p) => planState(p) == state)
        .toList();
    final active = inState(PlanState.active);
    final notStarted = inState(PlanState.notStarted);
    final finished = inState(PlanState.finished);

    void open(Plan plan) =>
        openPlanScreen(context, plan.id, tab: ShellTab.plans);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.read(librarySyncProvider)?.checkForChanges(),
          child: ListView(
            padding: const EdgeInsets.only(
              bottom: AppShell.contentBottomPadding,
            ),
            children: [
              PageHeader(
                title: 'Plans',
                actions: [
                  SettingsButton(
                    onPressed:
                        onOpenSettings ?? () => openSettingsScreen(context),
                  ),
                ],
              ),
              const SyncBannerCard(),
              if (library != null && library.plans.isEmpty)
                EmptyState(
                  icon: AppIcons.plans,
                  title: 'No plans yet',
                  body: 'A plan is a list for a season, a trip or a mood.',
                  actionLabel: 'New plan',
                  onAction: () => openNewPlanForm(context),
                )
              else if (library != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (active.isNotEmpty) ...[
                        const SectionHeading(
                          'Active',
                          padding: EdgeInsets.fromLTRB(0, 18, 0, 6),
                        ),
                        for (final (i, plan) in active.indexed) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _ActiveCard(
                            plan: plan,
                            library: library,
                            onTap: () => open(plan),
                          ),
                        ],
                      ],
                      if (notStarted.isNotEmpty) ...[
                        const SectionHeading(
                          'Not started',
                          padding: EdgeInsets.fromLTRB(0, 18, 0, 6),
                        ),
                        for (final plan in notStarted)
                          _PlanRow(plan: plan, onTap: () => open(plan)),
                      ],
                      if (finished.isNotEmpty) ...[
                        const SectionHeading(
                          'Finished',
                          padding: EdgeInsets.fromLTRB(0, 18, 0, 6),
                        ),
                        for (final plan in finished)
                          _PlanRow(plan: plan, onTap: () => open(plan)),
                      ],
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Loading…',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({
    required this.plan,
    required this.library,
    required this.onTap,
  });

  final Plan plan;
  final Library library;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final total = plan.items.length;
    final done = doneCount(plan);
    final next = nextUp(plan, library);
    return Semantics(
      button: true,
      label: '${planTitle(plan)}, ${progressLabel(plan)}',
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: colors.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          planTitle(plan),
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        progressLabel(plan),
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      minHeight: 8,
                    ),
                  ),
                  if (next.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Next up: ${next.join(', ')}',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        fontSize: 14,
                        height: 1.3,
                        color: colors.soft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.onTap});

  final Plan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return RowInkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(planTitle(plan), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    planSubtitle(plan),
                    style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            StrokeIcon(AppIcons.chevronRight, size: 18, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
