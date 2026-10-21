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
/// order; for each tag in more than one category, the categories it is
/// picked in here; the tags that do not exist yet with their categories; and
/// the existing tags whose categories were changed here, with their new
/// categories. The form creates and recategorizes those right before it
/// saves the entry.
@immutable
class TagPick {
  const TagPick({
    required this.selected,
    this.categories = const {},
    this.created = const {},
    this.recategorized = const {},
  });

  final List<String> selected;
  final Map<String, List<TagCategory>> categories;
  final Map<String, List<TagCategory>> created;
  final Map<String, List<TagCategory>> recategorized;
}

/// The entry form's tag picker (Add / edit entry › Tag picker), the only place
/// a tag can be created. The library's categories are folding rows, all folded
/// when the picker opens except the ones that hold a tag already on the entry;
/// "New on this entry" is always open. Game genres show only for games, music
/// genres for music and actors for movies and shows. A search shows the matches
/// from every group, folded or not, and a name that matches nothing exactly can
/// be created, through the similar-tag check (Add / edit entry › New tag: a
/// similar one exists) and the category dialog (Add / edit entry › New tag:
/// confirm and pick a category).
///
/// A tag in more than one category (Add / edit entry › Tag in two
/// categories: tag picker) appears in each of its groups and is ticked per
/// group. A long press on a tag opens its categories; a search for a person
/// or genre that another category of the same kind has offers "+ Add to
/// Actors", which adds the category and ticks it. Resolves with null when
/// dismissed.
Future<TagPick?> showTagPickerSheet(
  BuildContext context, {
  required Library library,
  required List<String> selected,
  required MediaType type,
  Map<String, List<TagCategory>> categories = const {},
  Map<String, List<TagCategory>> created = const {},
  Map<String, List<TagCategory>> recategorized = const {},
}) {
  return showAppSheet<TagPick>(
    context,
    // The form stays in view above the picker, as on Add / edit entry › Tag
    // picker.
    maxHeightFactor: 0.78,
    builder: (context) => TagPickerSheet(
      library: library,
      selected: selected,
      categories: categories,
      created: created,
      recategorized: recategorized,
      type: type,
    ),
  );
}

class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.library,
    required this.selected,
    required this.type,
    this.categories = const {},
    this.created = const {},
    this.recategorized = const {},
  });

  final Library library;
  final List<String> selected;

  /// The categories each selected tag in more than one category is picked
  /// in; a tag missing here is picked in all of them.
  final Map<String, List<TagCategory>> categories;
  final Map<String, List<TagCategory>> created;
  final Map<String, List<TagCategory>> recategorized;

  /// The entry's type: picks the categories shown and the new tag's
  /// starting category.
  final MediaType type;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

/// A search hit from another category of the same kind, offered to [group]
/// ("+ Add to Actors").
typedef _AddRow = ({TagCategory group, String tag});

class _TagPickerSheetState extends State<TagPickerSheet> {
  late final List<String> _selected = [...widget.selected];
  late final Map<String, List<TagCategory>> _created = {...widget.created};
  late final Map<String, List<TagCategory>> _recategorized = {
    ...widget.recategorized,
  };

  /// The categories a selected tag in more than one category is ticked in.
  late final Map<String, Set<TagCategory>> _picks = {
    for (final tag in widget.selected)
      if (_isMulti(tag)) tag: {...widget.categories[tag] ?? _categoriesOf(tag)},
  };
  final _query = TextEditingController();

  /// The groups unfolded right now. Every group starts folded except the ones
  /// that already hold a tag on this entry (Add / edit entry › Tag picker).
  late final Set<TagCategory> _open = {
    for (final category in TagCategory.values)
      if (_tagsIn(category).any((t) => _isOn(t, category))) category,
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

  /// The categories of [tag] as they stand in this picker: as created or
  /// changed here, else as the library has them.
  List<TagCategory> _categoriesOf(String tag) =>
      _created[tag] ?? _recategorized[tag] ?? widget.library.categoriesOf(tag);

  bool _isMulti(String tag) => _categoriesOf(tag).length > 1;

  /// The library's tags in [category], with the changes made here: a tag
  /// given the category joins, one that lost it leaves. Created tags are
  /// listed under "New on this entry" only.
  List<String> _tagsIn(TagCategory category) => [
    for (final tag in widget.library.tags[category] ?? const <String>[])
      if (!_recategorized.containsKey(tag) ||
          _recategorized[tag]!.contains(category))
        tag,
    for (final MapEntry(key: tag, value: categories) in _recategorized.entries)
      if (categories.contains(category) &&
          !(widget.library.tags[category]?.contains(tag) ?? false))
        tag,
  ];

  /// Whether [tag] is ticked in [category] (null: "New on this entry", the
  /// tag as a whole).
  bool _isOn(String tag, TagCategory? category) {
    if (!_selected.contains(tag)) return false;
    if (category == null || !_isMulti(tag)) return true;
    return _picks[tag]?.contains(category) ?? false;
  }

  /// Ticks or unticks [tag], in [category] for a tag in several: the first
  /// category ticked puts the tag on the entry, the last unticked takes it
  /// off. Under "New on this entry" (null) a tag in several categories goes
  /// on in all of them.
  void _toggle(String tag, TagCategory? category) {
    setState(() {
      if (!_isMulti(tag) || category == null) {
        if (_selected.remove(tag)) {
          _picks.remove(tag);
        } else {
          _selected.add(tag);
          if (_isMulti(tag)) _picks[tag] = {..._categoriesOf(tag)};
        }
        return;
      }
      final picks = _picks.putIfAbsent(tag, () => {});
      if (!picks.remove(category)) picks.add(category);
      if (picks.isEmpty) {
        _selected.remove(tag);
        _picks.remove(tag);
      } else if (!_selected.contains(tag)) {
        _selected.add(tag);
      }
    });
  }

  /// Gives [tag] the categories [categories] (a long press, or "+ Add to").
  /// The entry's ticks follow: a tag just turned several-category keeps the
  /// category it had; one back to a single category stays ticked only if
  /// it was ticked in the category that remains; one that loses every
  /// category it was ticked in comes off the entry.
  void _recategorize(String tag, List<TagCategory> categories) {
    final before = _categoriesOf(tag);
    final after = [
      for (final c in TagCategory.values)
        if (categories.contains(c)) c,
    ];
    if (_created.containsKey(tag)) {
      _created[tag] = after;
    } else {
      _recategorized[tag] = after;
    }
    if (!_selected.contains(tag)) {
      _picks.remove(tag);
      return;
    }
    final had = _picks[tag] ?? {...before};
    final kept = {
      for (final c in after)
        if (had.contains(c)) c,
    };
    if (kept.isEmpty) {
      _selected.remove(tag);
      _picks.remove(tag);
    } else if (after.length > 1) {
      _picks[tag] = kept;
    } else {
      _picks.remove(tag);
    }
  }

  Future<void> _editCategories(String tag) async {
    final current = _categoriesOf(tag);
    if (current.isEmpty || current.first.kind == null) return;
    final usage = _created.containsKey(tag)
        ? 'New on this entry.'
        : tagUsageLabel(tag, widget.library);
    final picked = await showTagCategoriesDialog(
      context,
      name: tag,
      current: current,
      usage: usage,
    );
    if (!mounted || picked == null) return;
    setState(() => _recategorize(tag, picked));
  }

  /// "+ Add to Actors": the tag gets the category and is ticked in it.
  void _addTo(_AddRow row) {
    setState(() {
      _recategorize(row.tag, [..._categoriesOf(row.tag), row.group]);
      _picks.putIfAbsent(
        row.tag,
        () => {..._categoriesOf(row.tag)}..removeWhere((c) => c == row.group),
      );
      _picks[row.tag]!.add(row.group);
      if (!_selected.contains(row.tag)) _selected.add(row.tag);
      _query.clear();
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
          if (!_selected.contains(similar)) _toggle(similar, null);
          _query.clear();
        });
        return;
      }
    }
    final categories = await showNewTagDialog(
      context,
      name: name,
      initial: TagCategory.defaultFor(widget.type),
    );
    if (!mounted || categories == null) return;
    setState(() {
      _created[name] = categories;
      _selected.add(name);
      if (categories.length > 1) _picks[name] = {...categories};
      _query.clear();
    });
  }

  void _done() {
    // A tag created and then unpicked again is not worth keeping.
    final created = {
      for (final MapEntry(key: name, value: c) in _created.entries)
        if (_selected.contains(name)) name: c,
    };
    Navigator.pop(
      context,
      TagPick(
        selected: _selected,
        categories: {
          for (final tag in _selected)
            if (_isMulti(tag))
              tag: [
                for (final c in _categoriesOf(tag))
                  if (_picks[tag]?.contains(c) ?? true) c,
              ],
        },
        created: created,
        recategorized: _recategorized,
      ),
    );
  }

  /// The search hits from another category of the same kind, for the
  /// groups none of whose own tags match: a person found under Directors
  /// can be added to Actors (Add / edit entry › Tag picker note).
  List<_AddRow> _addRows(String query) {
    if (query.isEmpty) return const [];
    final rows = <_AddRow>[];
    for (final group in TagCategory.values) {
      if (group.kind == null) continue;
      if (_tagsIn(group).any((t) => t.contains(query))) continue;
      for (final other in group.family) {
        if (other == group) continue;
        for (final tag in _tagsIn(other)) {
          if (!tag.contains(query) ||
              rows.any((r) => r.tag == tag && r.group == group)) {
            continue;
          }
          rows.add((group: group, tag: tag));
        }
      }
    }
    return rows;
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
            sortedTags(_tagsIn(category).where(matches)),
          ),
    ].where((g) => g.$3.isNotEmpty).toList();
    final addRows = _addRows(query);

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
                  tags.where((t) => _isOn(t, category)).length,
                ),
                onTap: () => showTagListScreen(
                  context,
                  category: category,
                  tags: tags,
                  selected: {
                    for (final t in tags)
                      if (_isOn(t, category)) t,
                  },
                  library: widget.library,
                  onToggle: (tag) => _toggle(tag, category),
                  onLongPress: _editCategories,
                ),
              )
            else
              TagGroup(
                label: name,
                tags: tags,
                selected: [
                  for (final t in tags)
                    if (_isOn(t, category)) t,
                ],
                open:
                    category == null ||
                    query.isNotEmpty ||
                    _open.contains(category),
                onToggleOpen: category == null
                    ? null
                    : () => _toggleOpen(category),
                onToggleTag: (tag) => _toggle(tag, category),
                onLongPressTag: category?.kind == null ? null : _editCategories,
                chipStyle: PillChipStyle.neutral,
                checked: true,
                chipHeight: 40,
                chipPadding: 12,
              ),
          for (final row in addRows)
            _AddToRow(row: row, onAdd: () => _addTo(row)),
          if (query.isNotEmpty && groups.isEmpty && addRows.isEmpty)
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

/// A search hit from another category of the same kind under the group it
/// can join: the group's name, the tag with "Not an actor tag yet" and a
/// dashed "+ Add to Actors" (Add / edit entry › Tag picker note).
class _AddToRow extends StatelessWidget {
  const _AddToRow({required this.row, required this.onAdd});

  final _AddRow row;
  final VoidCallback onAdd;

  /// Room the tag keeps however long the chip's label is.
  static const _minTagWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final role = row.group.roleLabel.toLowerCase();
    final article = 'aeiou'.contains(role[0]) ? 'an' : 'a';
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(row.group.label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          // The chip keeps its natural width up to what leaves the tag
          // [_minTagWidth]; a long tag or group name gives way with an
          // ellipsis, as in a long group's row.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${row.tag}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Not $article $role tag yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth - 10 - _minTagWidth).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: DashedChip(
                    label: 'Add to ${row.group.label}',
                    semanticsLabel: 'Add #${row.tag} to ${row.group.label}',
                    onTap: onAdd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
