import 'package:flutter/material.dart';

import '../../data/models/tag_category.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/chips.dart';
import '../../widgets/labels.dart';

enum SimilarTagChoice { useExisting, createAnyway }

/// The typed tag is close to one that exists (Add / edit entry › New tag: a
/// similar one exists). Null means cancel.
Future<SimilarTagChoice?> showSimilarTagDialog(
  BuildContext context, {
  required String typed,
  required String existing,
  required int usedBy,
}) {
  return showAppDialog<SimilarTagChoice>(
    context,
    builder: (context) {
      final theme = Theme.of(context);
      final colors = LibraryColors.of(context);
      final strong = theme.textTheme.bodyMedium!.copyWith(
        fontWeight: FontWeight.w700,
      );
      return AppDialog(
        title: 'A similar tag exists',
        content: Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.soft),
            children: [
              const TextSpan(text: 'You typed '),
              TextSpan(text: '#$typed', style: strong),
              const TextSpan(text: '. Your library already has '),
              TextSpan(text: '#$existing', style: strong),
              TextSpan(
                text: ', used on $usedBy ${usedBy == 1 ? 'entry' : 'entries'}.',
              ),
            ],
          ),
        ),
        note: 'Using the existing tag keeps your filters in one place.',
        actionsLayout: DialogActionsLayout.column,
        actions: [
          AppButton(
            label: 'Use #$existing',
            onPressed: () =>
                Navigator.pop(context, SimilarTagChoice.useExisting),
          ),
          AppButton(
            label: 'Create #$typed anyway',
            kind: AppButtonKind.outline,
            onPressed: () =>
                Navigator.pop(context, SimilarTagChoice.createAnyway),
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

/// The order of the category chips in Add / edit entry › New tag: confirm and
/// pick a category.
const newTagCategories = TagCategory.values;

/// Confirms a new tag and picks its category (Add / edit entry › New tag:
/// confirm and pick a category). Null means cancel.
Future<TagCategory?> showNewTagDialog(
  BuildContext context, {
  required String name,
  TagCategory initial = TagCategory.genre,
}) {
  return showAppDialog<TagCategory>(
    context,
    builder: (context) => _NewTagDialog(name: name, initial: initial),
  );
}

class _NewTagDialog extends StatefulWidget {
  const _NewTagDialog({required this.name, required this.initial});

  final String name;
  final TagCategory initial;

  @override
  State<_NewTagDialog> createState() => _NewTagDialogState();
}

class _NewTagDialogState extends State<_NewTagDialog> {
  late TagCategory _category = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return AppDialog(
      title: 'Create a new tag?',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodyMedium!.copyWith(color: colors.soft),
              children: [
                TextSpan(
                  text: '#${widget.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' is not in your tag list yet.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('CATEGORY', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in newTagCategories)
                PillChip(
                  label: category.label,
                  selected: category == _category,
                  style: PillChipStyle.accent,
                  horizontalPadding: 13,
                  onTap: () => setState(() => _category = category),
                ),
            ],
          ),
        ],
      ),
      note: 'It will be added to your tag list under ${_category.label}.',
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: 'Create tag',
          onPressed: () => Navigator.pop(context, _category),
        ),
      ],
    );
  }
}
