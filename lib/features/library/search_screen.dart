import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/search_field.dart';
import '../../widgets/section_heading.dart';
import 'library_search.dart';

/// Search over titles and tags (Library › Search). Pops with a [TagMatch] when a
/// tag row is tapped, so the home can show that tag's results. With [type] set
/// the search covers only that type, as the hint says ("Search movies").
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.type, this.onOpenEntry, this.onAddEntry});

  final MediaType? type;
  final void Function(Entry entry)? onOpenEntry;
  final void Function(String title)? onAddEntry;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final library = ref.watch(libraryProvider).value;
    final query = _controller.text;
    final results = library == null
        ? SearchResults.empty
        : searchLibrary(library, query, type: widget.type);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _controller,
                      hintText: searchHint(widget.type),
                      autofocus: true,
                      clearTooltip: 'Clear search',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.only(left: 10),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: query.trim().isEmpty
                  ? const SizedBox.shrink()
                  : results.isEmpty
                  ? EmptyState(
                      icon: AppIcons.search,
                      title: 'No results for "${query.trim()}"',
                      body: 'Check the spelling, or add it to your library as a new entry.',
                      actionLabel: 'Add "${query.trim()}"',
                      onAction: () => widget.onAddEntry?.call(query.trim()),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        if (results.titles.isNotEmpty) ...[
                          const SectionHeading(
                            'Titles',
                            padding: EdgeInsets.fromLTRB(0, 16, 0, 2),
                          ),
                          for (final entry in results.titles)
                            EntryRow.forEntry(
                              entry,
                              showType: widget.type == null,
                              colors: colors,
                              onTap: () => widget.onOpenEntry?.call(entry),
                            ),
                        ],
                        if (results.tags.isNotEmpty) ...[
                          const SectionHeading(
                            'Tags',
                            padding: EdgeInsets.fromLTRB(0, 16, 0, 2),
                          ),
                          for (final tag in results.tags)
                            _TagRow(
                              tag: tag,
                              onTap: () => Navigator.pop(context, tag),
                            ),
                        ],
                        for (final tag in results.tags) ...[
                          SectionHeading(
                            'Tagged ${tag.label}',
                            padding: const EdgeInsets.fromLTRB(0, 16, 0, 2),
                          ),
                          for (final entry in results.tagged[tag.key]!)
                            EntryRow.forEntry(
                              entry,
                              showType: widget.type == null,
                              colors: colors,
                              onTap: () => widget.onOpenEntry?.call(entry),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, required this.onTap});

  final TagMatch tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return RowInkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(tag.label, style: theme.textTheme.titleMedium),
            ),
            Text(
              '${tag.count} ${tag.count == 1 ? 'entry' : 'entries'}',
              style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
            ),
            const SizedBox(width: 6),
            StrokeIcon(AppIcons.chevronRight, size: 16, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// "Search titles and tags" on All, "Search movies" with a type picked.
String searchHint(MediaType? type) => type == null
    ? 'Search titles and tags'
    : 'Search ${type.label.toLowerCase()}';
