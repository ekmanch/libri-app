import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/touch_target.dart';
import '../../widgets/type_kicker.dart';
import '../shell/app_shell.dart';
import 'home_sections.dart';
import 'larger_cover.dart';
import 'library_filter.dart';
import 'library_filter_provider.dart';
import 'library_search.dart';

/// What a list being searched shows around its results (Library › Search:
/// Music › Artists and its sibling states): the matching tags above them,
/// the other types that have results under them, and how to add the query
/// as a new entry when nothing matches. A list narrowed to a tag is
/// searched too, with or without a query.
@immutable
class ListSearch {
  const ListSearch({
    required this.query,
    required this.q,
    required this.type,
    required this.tags,
    required this.others,
    required this.onPickTag,
    required this.onOpenType,
    required this.onAdd,
    this.picked = LibraryFilter.none,
  });

  /// As typed, trimmed: what the empty state quotes and Add starts with.
  final String query;

  /// As matched ([normalizeQuery]); empty when only a tag is picked.
  final String q;

  /// The type whose list is searched; null on Home.
  final MediaType? type;

  /// The Tags row: the picked tags, then those that match, counted over the
  /// list searched.
  final List<TagMatch> tags;

  /// The tags the list is narrowed to, as a filter of tags alone.
  final LibraryFilter picked;

  /// The other types that have results, in type order, with how many.
  final Map<MediaType, int> others;

  /// A chip of the Tags row tapped: the list is narrowed to that tag, or
  /// the tag is lifted. It never opens the results screen.
  final void Function(TagMatch tag) onPickTag;
  final void Function(MediaType type) onOpenType;
  final VoidCallback onAdd;

  /// What nothing matched, as the empty state quotes it: “adele”.
  String get what => '“$query”';

  /// Whether [entry] is a result: it matches the query and carries the
  /// picked tags.
  bool matches(Entry entry) =>
      picked.hasTagsOf(entry) && (q.isEmpty || matchesQuery(entry, q));

  /// The entries of [entries] that are results, in their order.
  List<Entry> apply(Iterable<Entry> entries) => [
    for (final entry in entries)
      if (matches(entry)) entry,
  ];

  /// The search of the page of [type] for [q] and the [picked] tags (one of
  /// them not empty), over [visible], every entry the library's lists show.
  /// [pool] is the list searched, which the tags are counted over: [visible]
  /// on Home, the type's own list otherwise.
  factory ListSearch.of(
    WidgetRef ref, {
    required Library library,
    required List<Entry> visible,
    required MediaType? type,
    required String q,
    LibraryFilter picked = LibraryFilter.none,
    Iterable<Entry>? pool,
    void Function({MediaType? type, String? title})? onAddEntry,
  }) {
    final query = q.isEmpty ? '' : ref.read(librarySearchProvider).trim();
    final tagged = visible.where(picked.hasTagsOf).toList();
    final counts = q.isEmpty
        ? {
            for (final t in MediaType.values)
              if (tagged.any((e) => e.type == t))
                t: tagged.where((e) => e.type == t).length,
          }
        : matchCounts(tagged, q);
    return ListSearch(
      query: query,
      q: q,
      type: type,
      picked: picked,
      tags: matchingTags(
        library,
        pool ?? (type == null ? visible : visible.where((e) => e.type == type)),
        q,
        picked: picked,
      ),
      others: {
        for (final t in MediaType.values)
          if (t != type && counts[t] != null) t: counts[t]!,
      },
      // The same list, narrowed to the tag: on a type's page the tag joins
      // that type's filter, on Home it is Home's own pick. The query stays.
      onPickTag: (tag) => type == null
          ? ref.read(homeTagsProvider.notifier).pick(tag)
          : ref
                .read(libraryFilterProvider.notifier)
                .narrow(
                  ref
                      .read(libraryFilterProvider)
                      .copyWith(types: {type})
                      .withTagPicked(tag.name, tag.category),
                ),
      onOpenType: (t) => ref
          .read(librarySearchProvider.notifier)
          .openType(
            t,
            music: t == MediaType.music
                ? musicTabForQuery(tagged.where((e) => e.type == t), q)
                : null,
            tags: picked,
          ),
      onAdd: () =>
          onAddEntry?.call(type: type, title: query.isEmpty ? null : query),
    );
  }
}

/// "3 results in Music", "1 result in Books".
String resultsInLabel(MediaType type, int count) =>
    '$count ${count == 1 ? 'result' : 'results'} in ${type.label}';

/// The matching tags of a search, one row that scrolls sideways under the
/// word "Tags": "#classic 79" (Library › Search: a tag matches; Search: a
/// tag finds artists). A chip narrows the list to that tag; the picked one
/// is filled, with a cross, and a tap lifts it. The tags of a filter that
/// narrows a type's list in place show here the same way.
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
                  selected: tag.picked,
                  label: tag.picked
                      ? 'Remove ${tag.label}'
                      : '${tag.label}, ${tag.count}',
                  excludeSemantics: true,
                  child: Material(
                    color: tag.picked
                        ? AccentColors.of(context).selection
                        : colors.surfaceHigh,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      onTap: () => onTap(tag),
                      customBorder: const StadiumBorder(),
                      child: Container(
                        height: chipHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  tagLabelSpan(context, tag.label),
                                  TextSpan(
                                    text: '  ${tag.count}',
                                    style: TextStyle(
                                      color: colors.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              style: tag.picked
                                  ? style.copyWith(fontWeight: FontWeight.w600)
                                  : style,
                            ),
                            if (tag.picked) ...[
                              const SizedBox(width: 6),
                              StrokeIcon(
                                AppIcons.closeBold,
                                size: 14,
                                color: theme.colorScheme.onSurface,
                              ),
                            ],
                          ],
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
/// line that says where the matches are, a button per other type that has
/// some, and Add “query”, which starts a new entry with the query as its
/// title.
class SearchEmpty extends StatelessWidget {
  const SearchEmpty({
    super.key,
    required this.title,
    required this.search,
    this.tabs = const [],
  });

  /// "No movies match “adele”", "No results for “zelda”".
  final String title;
  final ListSearch search;

  /// The other tabs of this list that have matches, as they are labeled
  /// ("Albums", "Songs"): music's, when the tab shown has none.
  final List<String> tabs;

  /// "There are matches under Albums.", "… under Albums and Songs.", "…
  /// under another type.", or the hint to check the spelling when there are
  /// none anywhere.
  static String whereText(List<String> tabs, {required bool otherTypes}) =>
      tabs.isNotEmpty
      ? 'There are matches under ${tabs.join(' and ')}.'
      : otherTypes
      ? 'There are matches under another type.'
      : 'Check the spelling, or add it to your library as a new entry.';

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
            whereText(tabs, otherTypes: search.others.isNotEmpty),
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
/// ("movies", "artists"), [what] the query in its quotes.
String noMatchTitle(String noun, String what) => 'No $noun match $what';

/// A filter that leaves nothing of the list it narrows (Library › Empty
/// states): the reason spelled out and a button that clears it.
class FilterEmpty extends ConsumerWidget {
  const FilterEmpty({super.key, required this.filter});

  final LibraryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
    icon: AppIcons.filters,
    title: 'Nothing matches these filters',
    body: filter.noMatchesText,
    actionLabel: 'Clear filters',
    onAction: () => ref.read(libraryFilterProvider.notifier).clear(),
  );
}

/// Home while it is searched or narrowed to a tag (Library › Search: Home,
/// results by type): the
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
              child: SearchTagRow(tags: search.tags, onTap: search.onPickTag),
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
              title: 'No results for ${search.what}',
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
                      onLongPress: () => showLargerCover(context, entry),
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
