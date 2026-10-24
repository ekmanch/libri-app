import 'package:flutter/material.dart';

import '../../data/models/library.dart';
import '../../data/models/tag_category.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/search_field.dart';
import 'entry_list_views.dart';
import 'entry_sections.dart';
import 'sectioned_list_body.dart';
import 'tag_sort.dart';

/// Opens the full-screen list of one long tag group (Library › Filter: all
/// Authors) above the sheet that asked for it: a search box, the tags A to Z
/// under letter headers with the index rail when the list is long, and a check
/// per row. Every toggle goes straight to [onToggle], so the sheet underneath
/// is up to date when Done or back closes the list.
Future<void> showTagListScreen(
  BuildContext context, {
  required TagCategory category,
  required List<String> tags,
  required Set<String> selected,
  required Library library,
  required ValueChanged<String> onToggle,
  ValueChanged<String>? onLongPress,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (_) => TagListScreen(
        category: category,
        tags: tags,
        selected: selected,
        library: library,
        onToggle: onToggle,
        onLongPress: onLongPress,
      ),
    ),
  );
}

class TagListScreen extends StatefulWidget {
  const TagListScreen({
    super.key,
    required this.category,
    required this.tags,
    required this.selected,
    required this.library,
    required this.onToggle,
    this.onLongPress,
  });

  final TagCategory category;
  final List<String> tags;

  /// The tags on when the list opens; the screen keeps its own copy.
  final Set<String> selected;
  final Library library;
  final ValueChanged<String> onToggle;

  /// A long press on a row, where it does something: the tag picker opens
  /// the tag's categories (Add / edit entry › Tag picker).
  final ValueChanged<String>? onLongPress;

  @override
  State<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends State<TagListScreen> {
  late final Set<String> _selected = {...widget.selected};
  late final List<String> _sorted = sortedTags(widget.tags);
  late final Map<String, String> _names = {
    for (final tag in _sorted) tag: tagDisplayName(tag, widget.library),
  };

  /// Entries carrying the tag as this category: a person in Directors and
  /// Actors counts their directing here, their acting there.
  late final Map<String, int> _counts = {
    for (final tag in _sorted)
      tag: widget.library.countTagAs(tag, widget.category),
  };
  String _query = '';

  void _toggle(String tag) {
    setState(() {
      if (!_selected.remove(tag)) _selected.add(tag);
    });
    widget.onToggle(tag);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final q = _query.trim().toLowerCase().replaceFirst('#', '');
    final shown = q.isEmpty
        ? _sorted
        : [
            for (final tag in _sorted)
              if (tag.contains(q) || _names[tag]!.toLowerCase().contains(q))
                tag,
          ];
    final sections = sectionsByTitle(shown, tagSortKey);
    final plural = tagGroupNoun(widget.category, 2);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: widget.category.label,
              onBack: () => Navigator.pop(context),
              actions: [
                AppButton(
                  label: 'Done',
                  compact: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SearchField(
                hintText: 'Search $plural',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
              child: Text(
                tagGroupCountLabel(
                  widget.category,
                  shown.length,
                  _selected.where(_sorted.contains).length,
                ),
                style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text(
                        'No ${tagGroupNoun(widget.category, 1)} matches '
                        '"${_query.trim()}".',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontSize: 15,
                          color: colors.muted,
                        ),
                      ),
                    )
                  : SectionedListBody<String>(
                      itemCount: shown.length,
                      sections: sections,
                      // Letter headers whatever the length: this is an
                      // index of names.
                      plainSections: sections,
                      grid: false,
                      rowExtent:
                          56 +
                          EntryListMetrics.textGrowth(
                            MediaQuery.textScalerOf(context),
                          ),
                      gridRowExtent: (_) => 0,
                      color: colors.muted,
                      bottomPadding: 16,
                      layoutKey: (q, shown.length),
                      rowBuilder: (context, tag) => _TagRow(
                        name: _names[tag]!,
                        detail:
                            '#$tag · ${_counts[tag]} '
                            '${_counts[tag] == 1 ? 'entry' : 'entries'}',
                        selected: _selected.contains(tag),
                        onTap: () => _toggle(tag),
                        onLongPress: widget.onLongPress == null
                            ? null
                            : () => widget.onLongPress!(tag),
                      ),
                      flatSlivers: const [],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tag in Library › Filter: all Authors: the name, "#tag · 3 entries" and a
/// round check.
class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.name,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String name;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      checked: selected,
      label: name,
      excludeSemantics: true,
      child: RowInkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
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
                    Text(
                      name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? scheme.primaryContainer : null,
                  border: Border.all(
                    color: selected
                        ? scheme.primaryContainer
                        : colors.placeholder,
                    width: 2,
                  ),
                ),
                child: selected
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
