import 'package:flutter/material.dart';

import '../../data/models/library.dart';
import '../../data/models/tag_category.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/create_tag_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/search_field.dart';
import '../entry/similar_tags.dart';
import 'entry_list_views.dart';
import 'entry_sections.dart';
import 'sectioned_list_body.dart';
import 'tag_sort.dart';
import '../../widgets/check_box_mark.dart';

/// What creating a tag from a category's page ended with: [tag] is on the
/// entry now (the new tag, or the similar one used instead), and [listed]
/// says whether it belongs to the page's category, so the page shows it
/// ticked.
typedef TagListCreated = ({String tag, bool listed});

/// Opens the full-screen list of one long tag group (Library › Filter: all
/// Authors) above the sheet that asked for it: a search box, the tags A to Z
/// under letter headers with the index rail when the list is long, and a check
/// per row. Every toggle goes straight to [onToggle], so the sheet underneath
/// is up to date when Done or back closes the list.
///
/// The entry form's tag picker passes [canCreate] and [onCreate] (Library ›
/// Tag picker: all Authors, create a tag); the filter sheet and a plan's
/// hashtags do not, since tags are only created from the entry form.
Future<void> showTagListScreen(
  BuildContext context, {
  required TagCategory category,
  required List<String> tags,
  required Set<String> selected,
  required Library library,
  required ValueChanged<String> onToggle,
  ValueChanged<String>? onLongPress,
  bool Function(String name)? canCreate,
  Future<TagListCreated?> Function(String name)? onCreate,
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
        canCreate: canCreate,
        onCreate: onCreate,
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
    this.canCreate,
    this.onCreate,
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

  /// Whether a normalized name can be created as a tag: it is no tag yet.
  /// Asked only when [onCreate] is given.
  final bool Function(String name)? canCreate;

  /// Creates the tag a search names, given normalized; with it the page
  /// shows the "Create “#tag” in Authors" row above the matches. Null where
  /// tags cannot be created (the filter sheet, a plan's hashtags).
  final Future<TagListCreated?> Function(String name)? onCreate;

  @override
  State<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends State<TagListScreen> {
  late final Set<String> _selected = {...widget.selected};
  late List<String> _sorted = sortedTags(widget.tags);
  late final Map<String, String> _names = {
    for (final tag in _sorted) tag: tagDisplayName(tag, widget.library),
  };

  /// Entries carrying the tag as this category: a person in Directors and
  /// Actors counts their directing here, their acting there.
  late final Map<String, int> _counts = {
    for (final tag in _sorted)
      tag: widget.library.countTagAs(tag, widget.category),
  };

  /// The library's tags; any other tag on the page was created in this
  /// picker and is on no saved entry yet.
  late final Set<String> _known = widget.library.allTags;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Creates [name] through the picker. The tag it ended with, when it
  /// belongs here, is shown ticked: the search becomes its name, so the row
  /// is in view wherever it sorts. A tag that went to another category
  /// just clears the search, as on the picker's first page.
  Future<void> _create(String name) async {
    final made = await widget.onCreate!(name);
    if (!mounted || made == null) return;
    setState(() {
      if (!made.listed) {
        _search.clear();
        return;
      }
      if (!_sorted.contains(made.tag)) {
        _sorted = sortedTags([..._sorted, made.tag]);
        _names[made.tag] = tagDisplayName(made.tag, widget.library);
        _counts[made.tag] = widget.library.countTagAs(
          made.tag,
          widget.category,
        );
      }
      _selected.add(made.tag);
      _search.text = _names[made.tag]!;
    });
  }

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
    final q = _search.text.trim().toLowerCase().replaceFirst('#', '');
    // The name the search would create, normalized as on the picker's
    // first page. A tag that holds it is a match too, so a name typed
    // without its punctuation ("ursula k le guin") finds its tag.
    final name = normalizeTag(_search.text);
    final shown = q.isEmpty
        ? _sorted
        : [
            for (final tag in _sorted)
              if (tagContains(tag, q) ||
                  _names[tag]!.toLowerCase().contains(q) ||
                  (name.isNotEmpty && tag.contains(name)))
                tag,
          ];
    final sections = sectionsByTitle(shown, tagSortKey);
    final plural = tagGroupNoun(widget.category, 2);
    final createRow =
        widget.onCreate != null && (widget.canCreate?.call(name) ?? false)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: CreateTagRow(
              tag: name,
              category: widget.category.label,
              onTap: () => _create(name),
            ),
          )
        : null;

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
                controller: _search,
                hintText: 'Search $plural',
                onChanged: (_) => setState(() {}),
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
                  ? ListView(
                      children: [
                        ?createRow,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Text(
                            'None of your $plural match.',
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontSize: 15,
                              color: colors.muted,
                            ),
                          ),
                        ),
                      ],
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
                      color: colors.muted,
                      bottomPadding: 16,
                      layoutKey: (q, shown.length),
                      leadingSlivers: [
                        if (createRow != null)
                          SliverToBoxAdapter(child: createRow),
                      ],
                      rowBuilder: (context, tag) => _TagRow(
                        name: _names[tag]!,
                        detail: _known.contains(tag)
                            ? '#$tag · ${_counts[tag]} '
                                  '${_counts[tag] == 1 ? 'entry' : 'entries'}'
                            : '#$tag · new',
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
              CheckBoxMark(checked: selected, round: true),
            ],
          ),
        ),
      ),
    );
  }
}
