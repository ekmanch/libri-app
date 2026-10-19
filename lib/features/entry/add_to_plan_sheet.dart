import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/plan.dart';
import '../../data/models/plan_item.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/sheet_frame.dart';
import '../plans/plan_form_screen.dart';
import '../plans/plan_progress.dart';

/// Add to plan (Library › Add to plan): one row per plan with a check. Toggling
/// applies at once; Done just closes. An entry that is already Done when it is
/// added is marked as a repeat (a rewatch or re-read).
Future<void> showAddToPlanSheet(BuildContext context, String entryId) {
  return showAppSheet<void>(
    context,
    builder: (context) => AddToPlanSheet(entryId: entryId),
  );
}

class AddToPlanSheet extends ConsumerWidget {
  const AddToPlanSheet({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final library = ref.watch(libraryProvider).value;
    final entry = library?.entryById(entryId);
    if (library == null || entry == null) return const SizedBox.shrink();
    final repository = ref.read(libraryRepositoryProvider);

    void toggle(Plan plan, bool on) {
      repository.apply(
        on
            ? SetPlanItem(
                plan.id,
                PlanItem(
                  entry: entry.id,
                  repeat: entry.status == EntryStatus.done,
                ),
              )
            : RemovePlanItem(plan.id, entry.id),
      );
    }

    return SheetFrame(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add to plan', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      entry.title,
                      style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Done',
                compact: true,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (library.plans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No plans yet. Make one on the Plans tab.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.muted,
                ),
              ),
            ),
          for (final plan in library.plans)
            _PlanRow(
              plan: plan,
              on: plan.itemFor(entry.id) != null,
              onToggle: (on) => toggle(plan, on),
            ),
          TextButton(
            onPressed: () => openNewPlanForm(context),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              alignment: Alignment.centerLeft,
              foregroundColor: theme.colorScheme.primary,
              padding: EdgeInsets.zero,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(
                  AppIcons.plus,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('New plan'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.on,
    required this.onToggle,
  });

  final Plan plan;
  final bool on;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final state = switch (planState(plan)) {
      PlanState.active => 'Active',
      PlanState.notStarted => 'Not started',
      PlanState.finished => 'Finished',
    };
    return Semantics(
      button: true,
      checked: on,
      label: planTitle(plan),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onToggle(!on),
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
                      state,
                      style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: on ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: on ? scheme.primaryContainer : colors.placeholder,
                    width: 2,
                  ),
                ),
                child: on
                    ? StrokeIcon(
                        AppIcons.check,
                        size: 14,
                        color: scheme.onPrimaryContainer,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
