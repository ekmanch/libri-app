import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/touch_target.dart';
import '../shell/app_shell.dart';
import 'home_sections.dart';
import 'library_filter.dart';
import 'library_filter_provider.dart';
import 'library_search.dart';

/// What a list being searched shows around its results (Library › Search:
/// Music › Artists and its sibling states): the matching tags above them,
/// the other types that have results under them, and how to add the query
/// as a new entry when nothing matches.
@immutable
class ListSearch {
  const ListSearch({
    required this.query,
    required this.q,
    required this.type,
    required this.tags,
    required this.others,
    required this.onOpenTag,
    required this.onOpenType,
    required this.onAdd,
  });

  /// As typed, trimmed: what the empty state quotes and Add starts with.
  final String query;

  /// As matched ([normalizeQuery]).
  final String q;

  /// The type whose list is searched; null on Home.
  final MediaType? type;

  /// The tags that match, counted over the list searched.
  final List<TagMatch> tags;

  /// The other types that have results, in type order, with how many.
  final Map<MediaType, int> others;
  final void Function(TagMatch tag) onOpenTag;
  final void Function(MediaType type) onOpenType;
  final VoidCallback onAdd;

  /// The search of the page of [type] for [q] (not empty), over [visible],
  /// every entry the library's lists show.
  factory ListSearch.of(
    WidgetRef ref, {
    required Library library,
    required List<Entry> visible,
    required MediaType? type,
    required String q,
    void Function({MediaType? type, String? title})? onAddEntry,
  }) {
    final query = ref.read(librarySearchProvider).trim();
    final counts = matchCounts(visible, q);
    return ListSearch(
      query: query,
      q: q,
      type: type,
      tags: matchingTags(
        library,
        type == null ? visible : visible.where((e) => e.type == type),
        q,
      ),
      others: {
        for (final t in MediaType.values)
          if (t != type && counts[t] != null) t: counts[t]!,
      },
      // The tag's results, within the type searched: the query has done
      // its work and is cleared with the list (see [LibrarySearchNotifier]).
      onOpenTag: (tag) => ref
          .read(libraryFilterProvider.notifier)
          .set(
            LibraryFilter(
              types: {?type},
              tags: {tag.name},
              tagCategories: {
                if (tag.category case final category?) tag.name: {category},
              },
            ),
          ),
      onOpenType: (t) => ref
          .read(librarySearchProvider.notifier)
          .openType(
            t,
            music: t == MediaType.music
                ? musicTabForQuery(visible.where((e) => e.type == t), q)
                : null,
          ),
      onAdd: () => onAddEntry?.call(type: type, title: query),
    );
  }
}

/// "3 results in Music", "1 result in Books".
String resultsInLabel(MediaType type, int count) =>
    '$count ${count == 1 ? 'result' : 'results'} in ${type.label}';

/// The matching tags of a search, one row that scrolls sideways under the
/// word "Tags": "#classic 79" (Library › Search: a tag matches). A chip
/// opens that tag's results.
class SearchTagRow extends StatelessWidget {
  const SearchTagRow({super.key, required this.tags, required this.onTap});

  final List<TagMatch> tags;
  final void Function(TagMatch tag) onTap;

  static const chipHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final style = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w500,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        // The chips' 48 dp touch area.
        height: 48,
        child: Row(
          children: [
            Text('TAGS', style: theme.textTheme.labelSmall),
            for (final tag in tags) ...[
              const SizedBox(width: 8),
              TouchTarget(
                child: Semantics(
                  button: true,
                  label: '${tag.label}, ${tag.count}',
                  excludeSemantics: true,
                  child: Material(
                    color: colors.surfaceHigh,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      onTap: () => onTap(tag),
                      customBorder: const StadiumBorder(),
                      child: Container(
                        height: chipHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        child: Text.rich(
                          TextSpan(
                            text: tag.label,
                            children: [
                              TextSpan(
                                text: '  ${tag.count}',
                                style: TextStyle(color: colors.muted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          style: style,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "In other types" under a type's results: one row per other type that has
/// matches, "3 results in Music ›", which opens it with the query kept
/// (Library › Search: Music › Artists).
class OtherTypesSection extends StatelessWidget {
  const OtherTypesSection({
    super.key,
    required this.others,
    required this.onTap,
  });

  final Map<MediaType, int> others;
  final void Function(MediaType type) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(
          'In other types',
          padding: EdgeInsets.fromLTRB(0, 18, 0, 2),
        ),
        for (final MapEntry(key: type, value: count) in others.entries)
          Semantics(
            button: true,
            child: RowInkWell(
              onTap: () => onTap(type),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    _Dot(colors.forType(type)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        resultsInLabel(type, count),
                        style: theme.textTheme.titleMedium!.copyWith(
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    StrokeIcon(
                      AppIcons.chevronRightBold,
                      size: 16,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A search with no results (Library › Search: nothing here, results in
/// another type; Search: no results anywhere): the magnifier, [title], a
/// line of help, a button per other type that has matches, and Add
/// “query”, which starts a new entry with the query as its title.
class SearchEmpty extends StatelessWidget {
  const SearchEmpty({super.key, required this.title, required this.search});

  /// "No movies match “adele”", "No results for “zelda”".
  final String title;
  final ListSearch search;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 8),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: StrokeIcon(AppIcons.search, size: 26, color: colors.muted),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            search.others.isEmpty
                ? 'Check the spelling, or add it to your library as a new entry.'
                : 'It is in your library under another type.',
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
            textAlign: TextAlign.center,
          ),
          for (final MapEntry(key: type, value: count)
              in search.others.entries) ...[
            const SizedBox(height: 16),
            AppButton(
              label: resultsInLabel(type, count),
              kind: AppButtonKind.outline,
              compact: true,
              icon: Center(widthFactor: 1, child: _Dot(colors.forType(type))),
              onPressed: () => search.onOpenType(type),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            label: 'Add “${search.query}”',
            compact: true,
            onPressed: search.onAdd,
          ),
        ],
      ),
    );
  }
}

/// "No movies match “adele”": [noun] is what the list holds, in the plural
/// ("movies", "artists").
String noMatchTitle(String noun, String query) => 'No $noun match “$query”';

/// Home while it is searched (Library › Search: Home, results by type): the
/// number of results, the matching tags, then one section per type that has
/// results ("Music · 3"), in type order, as Home's rows with or without
/// covers. A heading opens its type with the query kept. Music lists its
/// albums and songs, never artists.
class HomeSearchResults extends StatelessWidget {
  const HomeSearchResults({
    super.key,
    required this.controller,
    required this.top,
    required this.results,
    required this.search,
    required this.covers,
    this.onOpenEntry,
  });

  final ScrollController controller;
  final Widget top;

  /// The matching entries, in the order to list them.
  final List<Entry> results;
  final ListSearch search;
  final bool covers;
  final void Function(Entry entry)? onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byType = <MediaType, List<Entry>>{
      for (final type in MediaType.values)
        if (results.any((e) => e.type == type))
          type: [
            for (final e in results)
              if (e.type == type) e,
          ],
    };
    final tagRow = search.tags.isEmpty
        ? null
        : SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SearchTagRow(tags: search.tags, onTap: search.onOpenTag),
            ),
          );
    if (results.isEmpty) {
      return CustomScrollView(
        controller: controller,
        slivers: [
          top,
          ?tagRow,
          SliverToBoxAdapter(
            child: SearchEmpty(
              title: 'No results for “${search.query}”',
              search: search,
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.only(bottom: AppShell.contentBottomPadding),
          ),
        ],
      );
    }
    return CustomScrollView(
      controller: controller,
      slivers: [
        top,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '${results.length} ${results.length == 1 ? 'result' : 'results'}',
              style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
            ),
          ),
        ),
        ?tagRow,
        for (final MapEntry(key: type, value: entries) in byType.entries)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: SectionHeading(
                    '${type.label} · ${entries.length}',
                    padding: const EdgeInsets.only(top: 10),
                    semanticsLabel:
                        'Show ${resultsInLabel(type, entries.length)}',
                    onTap: () => search.onOpenType(type),
                  ),
                ),
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    return HomeRow(
                      searchRow(entry),
                      key: ValueKey('search-${entry.id}'),
                      leading: covers
                          ? HomeRow.cover(entry, width: HomeRow.homeCoverWidth)
                          : null,
                      padding: covers
                          ? HomeRow.homeCoverPadding
                          : EdgeInsets.zero,
                      onTap: () => onOpenEntry?.call(entry),
                    );
                  },
                ),
              ],
            ),
          ),
        const SliverPadding(
          padding: EdgeInsets.only(bottom: AppShell.contentBottomPadding),
        ),
      ],
    );
  }
}

/// A result on Home: "Movie · Denis Villeneuve" with the year on the right;
/// music says what it is, "Album · Adele", "Song · Henry Purcell".
HomeRowData searchRow(Entry entry) {
  final creator = entry.creator;
  return HomeRowData(
    entry,
    kind: entryKindLabel(entry),
    detail: creator == null || creator.isEmpty ? null : creator,
    right: entry.year?.toString() ?? '',
  );
}
