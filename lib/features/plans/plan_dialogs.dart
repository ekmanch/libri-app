import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/plan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import 'plan_builders.dart';
import 'plan_progress.dart';

enum RemoveChoice { fromPlan, everywhere }

/// Removes an entry from this plan, or deletes it everywhere (Plans › Remove
/// from plan, or everywhere). [plan] is
/// the one open; [otherPlans] are the other plans it is in. Null means
/// cancel.
Future<RemoveChoice?> showRemoveFromPlanDialog(
  BuildContext context, {
  required Entry entry,
  required Plan plan,
  required List<Plan> otherPlans,
}) {
  final names = [plan, ...otherPlans].map(planTitle).toList();
  final where = names.length == 1
      ? 'the plan ${names.single}'
      : 'the plans ${names.sublist(0, names.length - 1).join(', ')} '
            'and ${names.last}';
  return showAppDialog<RemoveChoice>(
    context,
    inheritTheme: true,
    builder: (context) => AppDialog(
      title: 'Remove ${entry.title}?',
      body: 'It is in $where and in your library.',
      actionsLayout: DialogActionsLayout.column,
      actions: [
        AppButton(
          label: 'Remove from this plan',
          kind: AppButtonKind.neutral,
          onPressed: () => Navigator.pop(context, RemoveChoice.fromPlan),
        ),
        AppButton(
          label: 'Delete everywhere',
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, RemoveChoice.everywhere),
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

/// Deletes a plan (Plans › Delete plan). Its entries stay. Resolves true when
/// confirmed.
Future<bool> confirmDeletePlan(BuildContext context, Plan plan) async {
  final n = plan.items.length;
  final ok = await showAppDialog<bool>(
    context,
    inheritTheme: true,
    builder: (context) => AppDialog(
      title: 'Delete ${planTitle(plan)}?',
      body: 'The plan and its checkmarks are removed.',
      note: n == 0
          ? 'It has no entries yet.'
          : 'Its ${n == 1 ? 'entry stays' : '$n entries stay'} in your library.',
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: 'Delete plan',
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return ok ?? false;
}

enum PlanMenuAction { edit, copy, delete }

/// The plan menu (Plans › Plan menu) under the "⋮" button, anchored to
/// [anchor].
Future<PlanMenuAction?> showPlanMenu(
  BuildContext context,
  BuildContext anchor, {
  required Plan plan,
}) {
  // The anchor sits inside the plan's theme, so a seasonal accent applies.
  final theme = Theme.of(anchor);
  final colors = LibraryColors.of(anchor);
  final button = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
  final position = RelativeRect.fromLTRB(
    overlay.size.width - 16 - 230,
    origin.dy + button.size.height - 4,
    16,
    0,
  );
  PopupMenuItem<PlanMenuAction> item(
    PlanMenuAction action,
    String label, {
    Color? color,
  }) => PopupMenuItem(
    value: action,
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: Text(
      label,
      style: theme.textTheme.titleMedium!.copyWith(color: color),
    ),
  );
  return showMenu<PlanMenuAction>(
    context: context,
    useRootNavigator: true,
    position: position,
    constraints: const BoxConstraints(minWidth: 230, maxWidth: 230),
    popUpAnimationStyle: AppMotion.menu,
    items: [
      item(PlanMenuAction.edit, 'Edit plan'),
      item(PlanMenuAction.copy, 'Copy to a new year'),
      PopupMenuDivider(height: 9, color: colors.navBorder),
      item(
        PlanMenuAction.delete,
        'Delete plan',
        color: theme.colorScheme.error,
      ),
    ],
  );
}

/// "Halloween 2026", for the labels around a plan.
String planLabel(Plan plan) => planTitle(plan);

/// Keeps [progressLabel] reachable from the dialogs' importers.
String planProgress(Plan plan) => progressLabel(plan);
