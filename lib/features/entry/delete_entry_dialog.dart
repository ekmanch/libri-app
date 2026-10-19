import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/plan.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icons.dart';
import '../plans/plan_progress.dart';

/// Delete confirmation (Library › Delete confirmation). [plans] are the plans
/// the entry is in, which the body names. Resolves true when the user confirms.
Future<bool> confirmDeleteEntry(
  BuildContext context, {
  required Entry entry,
  required List<Plan> plans,
}) async {
  final names = plans.map(planTitle).toList();
  final where = switch (names.length) {
    0 => '',
    1 => ' and from the plan ${names.single}',
    _ =>
      ' and from the plans '
          '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: 'Delete ${entry.title}?',
      body: 'It will be removed from your library$where.',
      note:
          'The change is saved to your GitHub repo, where earlier versions '
          'stay in the history.',
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: 'Delete',
          kind: AppButtonKind.destructive,
          icon: const StrokeIcon(AppIcons.trash),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
