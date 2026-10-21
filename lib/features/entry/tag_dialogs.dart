import 'package:flutter/material.dart';

import '../../data/models/library.dart';
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

/// "Genres", "Directors and Actors", "Genres, Game genres and Music genres".
String _categoryList(Iterable<TagCategory> categories) {
  final labels = [for (final c in categories) c.label];
  if (labels.length < 2) return labels.join();
  return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
}

/// Confirms a new tag and picks its categories (Add / edit entry › New tag:
/// confirm and pick a category): one, or several of one kind (people:
/// Authors, Directors, Actors; genres: Genres, Game genres, Music genres);
/// tapping a category of another kind starts over with it. Null means
/// cancel.
Future<List<TagCategory>?> showNewTagDialog(
  BuildContext context, {
  required String name,
  TagCategory initial = TagCategory.genre,
}) {
  return showAppDialog<List<TagCategory>>(
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
  late final Set<TagCategory> _picked = {widget.initial};

  void _tap(TagCategory category) {
    setState(() {
      if (_picked.contains(category)) {
        _picked.remove(category);
      } else if (_picked.any((c) => !c.sharesKindWith(category))) {
        // Another kind: start over with it.
        _picked
          ..clear()
          ..add(category);
      } else {
        _picked.add(category);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final picked = [
      for (final c in TagCategory.values)
        if (_picked.contains(c)) c,
    ];
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
          Text('CATEGORIES', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in newTagCategories)
                // A category of another kind than the picked ones is dimmed:
                // tapping it starts over.
                Opacity(
                  opacity:
                      picked.isEmpty ||
                          _picked.contains(category) ||
                          picked.first.sharesKindWith(category)
                      ? 1
                      : 0.4,
                  child: PillChip(
                    label: category.label,
                    selected: _picked.contains(category),
                    style: PillChipStyle.accent,
                    horizontalPadding: 13,
                    onTap: () => _tap(category),
                  ),
                ),
            ],
          ),
        ],
      ),
      note: picked.isEmpty
          ? 'Pick at least one category.'
          : 'People can be in more than one people category, genres in more '
                'than one genre category. It will be added to your tag list '
                'under ${_categoryList(picked)}.',
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: 'Create tag',
          onPressed: picked.isEmpty
              ? null
              : () => Navigator.pop(context, picked),
        ),
      ],
    );
  }
}

/// Edits the categories of an existing tag (Add / edit entry › Tag picker, a
/// long press on a tag): the categories of its kind as chips, at least one
/// picked. [usage] says where the tag is used ("Used on 6 entries: as an
/// actor on 4, as a director on 2."). Null means cancel.
Future<List<TagCategory>?> showTagCategoriesDialog(
  BuildContext context, {
  required String name,
  required List<TagCategory> current,
  required String usage,
}) {
  return showAppDialog<List<TagCategory>>(
    context,
    builder: (context) =>
        _TagCategoriesDialog(name: name, current: current, usage: usage),
  );
}

class _TagCategoriesDialog extends StatefulWidget {
  const _TagCategoriesDialog({
    required this.name,
    required this.current,
    required this.usage,
  });

  final String name;
  final List<TagCategory> current;
  final String usage;

  @override
  State<_TagCategoriesDialog> createState() => _TagCategoriesDialogState();
}

class _TagCategoriesDialogState extends State<_TagCategoriesDialog> {
  late final Set<TagCategory> _picked = {...widget.current};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final family = widget.current.first.family;
    final kind = widget.current.first.kind;
    final picked = [
      for (final c in family)
        if (_picked.contains(c)) c,
    ];
    return AppDialog(
      title: '#${widget.name}',
      body: widget.usage,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CATEGORIES', style: theme.textTheme.labelSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in family)
                PillChip(
                  label: category.label,
                  selected: _picked.contains(category),
                  style: PillChipStyle.accent,
                  horizontalPadding: 13,
                  onTap: () => setState(() {
                    if (!_picked.contains(category)) {
                      _picked.add(category);
                    } else if (_picked.length > 1) {
                      _picked.remove(category);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
      note: switch (kind) {
        TagKind.people =>
          'People can be in Authors, Directors and Actors. At least one '
              'stays picked.',
        TagKind.genres =>
          'Genres can be in Genres, Game genres and Music genres. At least '
              'one stays picked.',
        null => 'This kind of tag has one category.',
      },
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: 'Save',
          onPressed: () => Navigator.pop(context, picked),
        ),
      ],
    );
  }
}

/// "Used on 6 entries: as an actor on 4, as a director on 2." for a tag in
/// more than one category of [library], "Used on 3 entries." otherwise. The
/// roles go by count, largest first.
String tagUsageLabel(String name, Library library) {
  final total = library.entries.where((e) => e.tags.contains(name)).length;
  final head = 'Used on $total ${total == 1 ? 'entry' : 'entries'}';
  final categories = library.categoriesOf(name);
  if (categories.length < 2) return '$head.';
  final counts = [for (final c in categories) (c, library.countTagAs(name, c))]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  final parts = [
    for (final (category, count) in counts)
      if (count > 0) 'as ${_article(category.roleLabel)} on $count',
  ];
  return parts.isEmpty ? '$head.' : '$head: ${parts.join(', ')}.';
}

/// "an actor", "a director", "a game genre".
String _article(String role) {
  final lower = role.toLowerCase();
  return '${'aeiou'.contains(lower[0]) ? 'an' : 'a'} $lower';
}
