import 'package:flutter/material.dart';

import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/tag_category.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/chips.dart';
import '../../widgets/labels.dart';
import '../../widgets/search_field.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/tag_group.dart';
import '../library/tag_list_screen.dart';
import '../library/tag_sort.dart';
import 'similar_tags.dart';
import 'tag_dialogs.dart';

/// What the tag picker was closed with: the tags now on the entry, in
/// order, and the tags that do not exist yet with their categories. The
/// form creates those right before it saves the entry.
@immutable
class TagPick {
  const TagPick({required this.selected, required this.created});

  final List<String> selected;
  final Map<String, TagCategory> created;
}

/// The entry form's tag picker (Add / edit entry › Tag picker), the only place
/// a tag can be created. The library's categories are folding rows, all folded
/// when the picker opens except the ones that hold a tag already on the entry;
/// "New on this entry" is always open. Game genres show only for games, music
/// genres for music and actors for movies and shows. A search shows the matches
/// from every group, folded or not, and a name that matches nothing exactly can
/// be created, through the similar-tag check (Add / edit entry › New tag: a
/// similar one exists) and the category dialog (Add / edit entry › New tag:
/// confirm and pick a category). Resolves with null when dismissed.
Future<TagPick?> showTagPickerSheet(
  BuildContext context, {
  required Library library,
  required List<String> selected,
  required MediaType type,
  Map<String, TagCategory> created = const {},
}) {
  return showAppSheet<TagPick>(
    context,
    // The form stays in view above the picker, as on Add / edit entry › Tag
    // picker.
    maxHeightFactor: 0.78,
    builder: (context) => TagPickerSheet(
      library: library,
      selected: selected,
      created: created,
      type: type,
    ),
  );
}

class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.library,
    required this.selected,
    required this.created,
    required this.type,
  });

  final Library library;
  final List<String> selected;
  final Map<String, TagCategory> created;

  /// The entry's type: picks the categories shown and the new tag's
  /// starting category.
  final MediaType type;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  late final List<String> _selected = [...widget.selected];
  late final Map<String, TagCategory> _created = {...widget.created};
  final _query = TextEditingController();

  /// The groups unfolded right now. Every group starts folded except the ones
  /// that already hold a tag on this entry (Add / edit entry › Tag picker).
  late final Set<TagCategory> _open = {
    for (final MapEntry(key: category, value: names)
        in widget.library.tags.entries)
      if (names.any(widget.selected.contains)) category,
  };

  void _toggleOpen(TagCategory category) {
    setState(() {
      if (!_open.remove(category)) _open.add(category);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Set<String> get _allNames => {...widget.library.allTags, ..._created.keys};

  void _toggle(String tag) {
    setState(() {
      if (!_selected.remove(tag)) _selected.add(tag);
    });
  }

  Future<void> _create(String name) async {
    final similar = findSimilarTag(name, _allNames);
    if (similar != null) {
      final usedBy = widget.library.entries
          .where((e) => e.tags.contains(similar))
          .length;
      final choice = await showSimilarTagDialog(
        context,
        typed: name,
        existing: similar,
        usedBy: usedBy,
      );
      if (!mounted || choice == null) return;
      if (choice == SimilarTagChoice.useExisting) {
        setState(() {
          if (!_selected.contains(similar)) _selected.add(similar);
          _query.clear();
        });
        return;
      }
    }
    final category = await showNewTagDialog(
      context,
      name: name,
      initial: TagCategory.defaultFor(widget.type),
    );
    if (!mounted || category == null) return;
    setState(() {
      _created[name] = category;
      _selected.add(name);
      _query.clear();
    });
  }

  void _done() {
    // A tag created and then unpicked again is not worth keeping.
    final created = {
      for (final MapEntry(key: name, value: c) in _created.entries)
        if (_selected.contains(name)) name: c,
    };
    Navigator.pop(context, TagPick(selected: _selected, created: created));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final query = normalizeTag(_query.text);
    final canCreate = query.isNotEmpty && !_allNames.contains(query);
    bool matches(String tag) => query.isEmpty || tag.contains(query);

    // "New on this entry" first, then the library's categories, each A to Z. A
    // long group is a row that opens Library › Filter: all Authors
    // (Add / edit entry › Tag picker note), unless a search narrows it; while a
    // search is typed every group with a match is open.
    final groups = <(TagCategory?, String, List<String>)>[
      if (_created.isNotEmpty)
        (null, 'New on this entry', _created.keys.where(matches).toList()),
      for (final category in TagCategory.values)
        if (query.isNotEmpty || category.offeredFor(widget.type))
          (
            category,
            category.label,
            sortedTags(
              (widget.library.tags[category] ?? const []).where(matches),
            ),
          ),
    ].where((g) => g.$3.isNotEmpty).toList();

    return SheetFrame(
      scrollable: true,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Add tags', style: theme.textTheme.titleLarge),
              ),
              AppButton(label: 'Done', compact: true, onPressed: _done),
            ],
          ),
          const SizedBox(height: 12),
          // No autofocus: most of the time a tag is tapped, not typed, so
          // the keyboard waits for a tap on the search box.
          SearchField(
            controller: _query,
            hintText: 'Search or create a tag',
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canCreate) _create(query);
            },
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canCreate)
            Semantics(
              button: true,
              label: 'Create #$query',
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _create(query),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        StrokeIcon(
                          AppIcons.plus,
                          size: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Create “#$query”',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (canCreate) const SizedBox(height: 8),
          for (final (category, name, tags) in groups)
            if (category != null && query.isEmpty && tags.length > longTagGroup)
              TagGroupRow(
                label: name,
                detail: tagGroupCountLabel(
                  category,
                  tags.length,
                  tags.where(_selected.contains).length,
                ),
                onTap: () => showTagListScreen(
                  context,
                  category: category,
                  tags: tags,
                  selected: _selected.toSet(),
                  library: widget.library,
                  onToggle: _toggle,
                ),
              )
            else
              TagGroup(
                label: name,
                tags: tags,
                selected: _selected,
                open:
                    category == null ||
                    query.isNotEmpty ||
                    _open.contains(category),
                onToggleOpen: category == null
                    ? null
                    : () => _toggleOpen(category),
                onToggleTag: _toggle,
                chipStyle: PillChipStyle.neutral,
                checked: true,
                chipHeight: 40,
                chipPadding: 12,
              ),
          if (query.isNotEmpty && groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'None of your tags match.',
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  color: colors.muted,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
