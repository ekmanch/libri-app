import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/library.dart';
import '../../data/models/season.dart';
import '../../data/models/media_type.dart';
import '../../data/models/plan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/chips.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/pinned_sliver.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/segmented_control.dart';
import '../entry/series.dart';
import '../music/music_tab.dart';
import '../music/artist_screen.dart';
import '../music/music_type_body.dart';
import '../plans/plan_progress.dart';
import '../plans/plan_screen.dart';
import '../settings/display_preferences.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_banner.dart';
import 'library_skeleton.dart';
import '../settings/entry_view.dart';
import '../shell/app_shell.dart';
import '../shell/floating_nav_bar.dart';
import 'active_plan_card.dart';
import 'entry_list_body.dart';
import 'entry_list_views.dart';
import 'filter_sheet.dart';
import 'home_return_provider.dart';
import 'home_sections.dart';
import 'home_type_provider.dart';
import 'library_filter.dart';
import 'library_filter_provider.dart';
import 'library_sort.dart';
import 'library_search.dart';
import 'recent_changes.dart';
import 'search_screen.dart';
import 'series_groups.dart';
import 'sort_sheet.dart';
import 'view_menu.dart';

/// The library home (Library › Home). On All it shows the active plan, then
/// Coming soon, In progress and Recently added. With a type chip picked it
/// becomes that type's list in place (Library › Movies, text view; Movies, list
/// with covers; Movies, grid with covers): status segments, count, sort and
/// view; Music gets its artist, album and song tabs instead (Library › Music:
/// artists, text view). Also shows filtered results (Library › Filtered
/// results, one type and several types) and the empty states (Library › Empty
/// states).
///
/// The whole top is part of the one scroll view: the title, the banner,
/// the search box, the type chips and the status segments scroll away with
/// the list, while the count row (count, sort, view) pins at the top as it
/// gets there, so the entries get the rest of the screen. Library in
/// the pill brings the top back (see [_onReturn]).
class LibraryHomeScreen extends ConsumerStatefulWidget {
  const LibraryHomeScreen({
    super.key,
    this.onOpenEntry,
    this.onOpenSettings,
    this.onOpenPlan,
    this.onAddEntry,
  });

  final void Function(Entry entry)? onOpenEntry;
  final VoidCallback? onOpenSettings;

  /// Opens the active plan. The shell switches to the Plans tab (DESIGN.md
  /// section 3); without a shell, e.g. in tests, it opens in place.
  final void Function(Plan plan)? onOpenPlan;

  /// Starts a new entry, for the picked [type] and with a [title] already
  /// typed (from search).
  final void Function({MediaType? type, String? title})? onAddEntry;

  @override
  ConsumerState<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends ConsumerState<LibraryHomeScreen> {
  /// The one scroll position, shared by every body the home shows (All, a
  /// type, results), so a return can scroll back to the top.
  final _scroll = ScrollController();

  /// The chip row's position, so the picked All chip is in view after a
  /// return, even when the row was scrolled to Music or Anime.
  final _chipScroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    _chipScroll.dispose();
    super.dispose();
  }

  /// Library tapped in the pill while this screen is on top. Scrolled
  /// down: back to the top, so the header is in view again. At the top:
  /// back to All, with the filter and the type cleared (the status segment
  /// resets with the type) and the chip row slid back to All.
  void _onReturn() {
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0, duration: AppMotion.slide, curve: Curves.easeOut);
      return;
    }
    ref.read(libraryFilterProvider.notifier).clear();
    ref.read(homeTypeProvider.notifier).set(null);
    // The chip row may be rebuilt this frame (a filter giving way to All),
    // so wait for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chipScroll.hasClients) {
        _chipScroll.animateTo(
          0,
          duration: AppMotion.slide,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _pickType(MediaType? type) {
    ref.read(homeTypeProvider.notifier).set(type);
    ref.read(homeStatusProvider.notifier).set(null);
    ref.read(homeMusicTabProvider.notifier).set(MusicTab.artists);
  }

  /// Opens the filter sheet. With no filter active it starts with what the home
  /// shows: the picked type and its status segment or music tab (Library ›
  /// Filter sheet from Movies (Done picked)).
  Future<void> _openFilters(Library library) async {
    final filter = ref.read(libraryFilterProvider);
    final result = await showFilterSheet(
      context,
      library: library,
      initial: filter.isActive
          ? filter
          : LibraryFilter.ofTypeView(
              ref.read(homeTypeProvider),
              status: ref.read(homeStatusProvider),
              kind: ref.read(homeMusicTabProvider).kind,
            ),
    );
    if (result != null) ref.read(libraryFilterProvider.notifier).set(result);
  }

  void _openSettings() =>
      (widget.onOpenSettings ?? () => openSettingsScreen(context))();

  Future<void> _openSearch() async {
    // The chip row is hidden while a filter is active, so search is scoped
    // to the picked type only when the chip can be seen.
    final type = ref.read(libraryFilterProvider).isActive
        ? null
        : ref.read(homeTypeProvider);
    // Full screen, above the floating navigation (Library › Search has none).
    final tag = await Navigator.of(context, rootNavigator: true).push<TagMatch>(
      MaterialPageRoute(
        builder: (searchContext) => SearchScreen(
          type: type,
          onOpenEntry: widget.onOpenEntry,
          onAddEntry: (title) {
            Navigator.pop(searchContext);
            widget.onAddEntry?.call(type: type, title: title);
          },
        ),
      ),
    );
    if (tag != null && mounted) {
      ref
          .read(libraryFilterProvider.notifier)
          .set(
            LibraryFilter(
              types: {?type},
              tags: {tag.name},
              tagCategories: {
                if (tag.category case final category?) tag.name: {category},
              },
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final filter = ref.watch(libraryFilterProvider);
    final prefs = ref.watch(displayPreferencesProvider);
    final type = ref.watch(homeTypeProvider);
    final libraryAsync = ref.watch(libraryProvider);
    final library = libraryAsync.value;
    ref.listen(homeReturnProvider, (_, _) => _onReturn());

    if (library == null && !libraryAsync.hasError) {
      // The first load (First run › First load).
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Library',
                actions: [SettingsButton(onPressed: _openSettings)],
              ),
              const SyncBannerCard(),
              const Expanded(child: LibrarySkeleton()),
            ],
          ),
        ),
      );
    }

    // The top of the screen, as the first slivers of whichever body shows;
    // all of it scrolls away.
    final showChips = library != null && !filter.isActive;
    final header = <Widget>[
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Library',
              actions: [SettingsButton(onPressed: _openSettings)],
            ),
            const SyncBannerCard(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: _SearchRow(
                hint: searchHint(filter.isActive ? null : type),
                filterCount: filter.count,
                onSearch: _openSearch,
                onFilters: library == null ? null : () => _openFilters(library),
              ),
            ),
          ],
        ),
      ),
      if (showChips)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 44,
              child: ListView(
                // The row is built afresh when the body changes (All to a
                // type); the key keeps its scroll position across that.
                key: const PageStorageKey('type-chips'),
                controller: _chipScroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                children: [
                  PillChip(
                    label: 'All',
                    selected: type == null,
                    onTap: () => _pickType(null),
                  ),
                  for (final t in MediaType.values) ...[
                    const SizedBox(width: 8),
                    PillChip(
                      label: t.label,
                      selected: type == t,
                      dotColor: colors.forType(t),
                      onTap: () => _pickType(t),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
    ];

    final Widget body;
    if (library == null) {
      body = _loadFailed(header, libraryAsync.error);
    } else if (filter.isActive) {
      body = _filtered(header, library, filter, prefs, colors);
    } else if (type == null) {
      body = _home(header, library, filter, colors);
    } else {
      body = _oneType(header, library, type, filter, prefs);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(onRefresh: _refresh, child: body),
      ),
    );
  }

  /// Pull-to-refresh: asks GitHub for changes. A library that failed to
  /// load is loaded again.
  Future<void> _refresh() async {
    if (ref.read(libraryProvider).hasError) ref.invalidate(libraryProvider);
    await ref.read(librarySyncProvider)?.checkForChanges();
  }

  /// A scroll view of the header and [slivers], on the shared position.
  Widget _scrollView(List<Widget> header, List<Widget> slivers) =>
      CustomScrollView(controller: _scroll, slivers: [...header, ...slivers]);

  /// The first download failed (offline, a bad token): say so, and let a
  /// pull or the button try again.
  Widget _loadFailed(List<Widget> header, Object? error) {
    final theme = Theme.of(context);
    return _scrollView(header, [
      SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverList.list(
          children: [
            Text(
              'Could not load the library: $error',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Try again',
              kind: AppButtonKind.outline,
              onPressed: _refresh,
            ),
          ],
        ),
      ),
    ]);
  }

  /// All: the active plan, then Coming soon, In progress and Recently added
  /// (Library › Home), each only when it has something, up to ten rows; the
  /// hint when none has (Library › Home: nothing to show).
  Widget _home(
    List<Widget> header,
    Library library,
    LibraryFilter filter,
    LibraryColors colors,
  ) {
    final plan = activePlan(library);
    final visible = filter.apply(library.entries);
    final sections = homeSections(
      visible,
      today: seasonClock(),
      changes: ref.watch(recentChangesProvider),
    );
    final rows = <Widget>[];
    for (final section in sections) {
      final seeAll = section.kind == HomeSectionKind.inProgress;
      rows.add(
        SectionHeading(
          section.kind.title,
          action: seeAll ? 'See all ${section.total}' : null,
          onAction: seeAll ? _seeAllInProgress : null,
          // The same height as the heading with the See all button (its
          // 48 px, centered), so the three headings line up with their rows
          // alike (the canvas's 44 px heading rows).
          padding: seeAll
              ? const EdgeInsets.only(top: 10)
              : const EdgeInsets.fromLTRB(0, 26, 0, 16),
        ),
      );
      for (final row in section.rows) {
        rows.add(
          HomeRow(
            row,
            key: ValueKey('home-${section.kind.name}-${row.entry.id}'),
            onTap: () => widget.onOpenEntry?.call(row.entry),
          ),
        );
      }
    }

    return _scrollView(header, [
      if (plan != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: ActivePlanCard(
              plan: plan,
              onTap: () => widget.onOpenPlan != null
                  ? widget.onOpenPlan!(plan)
                  : openPlanScreen(context, plan.id, tab: ShellTab.library),
            ),
          ),
        ),
      if (visible.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: AppIcons.library,
            title: 'Your library is empty',
            body: 'Entries you add will show up here.',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            20,
            4,
            20,
            AppShell.contentBottomPadding,
          ),
          sliver: SliverList.list(
            children: rows.isEmpty ? const [HomeNothingToShow()] : rows,
          ),
        ),
    ]);
  }

  /// "See all N" on In progress: the filter result with just that status,
  /// across every type (Library › In progress, all types (See all)).
  void _seeAllInProgress() => ref
      .read(libraryFilterProvider.notifier)
      .set(const LibraryFilter(statuses: {EntryStatus.inProgress}));

  /// One type picked: status segments, count, sort, view and the list in
  /// the remembered view, all in one scroll; the count row pins at the top
  /// once the rest has scrolled away.
  Widget _oneType(
    List<Widget> header,
    Library library,
    MediaType type,
    LibraryFilter filter,
    DisplayPreferences prefs,
  ) {
    final theme = Theme.of(context);
    final visible = filter.apply(library.entriesOfType(type));
    if (visible.isEmpty) {
      return _scrollView(header, [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: AppIcons.library,
            title: 'No ${type.label.toLowerCase()} yet',
            body: type == MediaType.music
                ? 'Albums and songs you add will show up here.'
                : '${type.label} you add will show up here.',
            actionLabel: 'Add ${type.singular.toLowerCase()}',
            onAction: () => widget.onAddEntry?.call(type: type),
          ),
        ),
      ]);
    }
    if (type == MediaType.music) {
      return MusicTypeBody(
        entries: visible,
        controller: _scroll,
        leadingSlivers: header,
        onOpenEntry: (entry) => widget.onOpenEntry?.call(entry),
        onOpenArtist: (artist) =>
            openArtistScreen(context, artist, onOpenEntry: widget.onOpenEntry),
      );
    }
    final status = ref.watch(homeStatusProvider);
    final shown = sortEntries(
      visible.where((e) => status == null || e.status == status),
      prefs.sortFor(type),
    );
    final view = prefs.viewFor(type);

    final segments = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: StatusSegmentedControl(
          selected: status,
          type: type,
          includeAll: true,
          onChanged: ref.read(homeStatusProvider.notifier).set,
        ),
      ),
    );
    final countExtent = countRowExtent(MediaQuery.textScalerOf(context));
    final count = PinnedSliver(
      height: countExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 10, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                countLabel(type, shown.length),
                style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
              ),
            ),
            SortButton(
              current: prefs.sortFor(type),
              onChanged: (sort) => ref
                  .read(displayPreferencesProvider.notifier)
                  .setSort(type, sort),
            ),
            ViewMenuButton(
              current: view,
              onChanged: (v) => ref
                  .read(displayPreferencesProvider.notifier)
                  .setView(type, v),
            ),
          ],
        ),
      ),
    );

    if (shown.isEmpty) {
      return _scrollView(header, [
        segments,
        count,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
            child: Text(
              'Nothing marked ${status!.lowerLabel} yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: LibraryColors.of(context).muted,
              ),
            ),
          ),
        ),
      ]);
    }
    return EntryListBody(
      // A new type starts at the top.
      key: ValueKey(type),
      entries: shown,
      sort: prefs.sortFor(type),
      view: view,
      color: LibraryColors.of(context).forType(type),
      controller: _scroll,
      leadingSlivers: [...header, segments, count],
      pinnedExtent: countExtent,
      groupSeries: groupsSeriesFor(status),
      onTap: (entry) => widget.onOpenEntry?.call(entry),
      onTapSeries: (group) => openSeriesPage(context, group.parts.first.id),
    );
  }

  /// Filtered results (Library › Filtered results, one type and several types):
  /// removable chips, then the count and sort row, which pins, then the rows
  /// grouped by type; a long list gets a rail (Library › Filtered results, one
  /// type and several types).
  Widget _filtered(
    List<Widget> header,
    Library library,
    LibraryFilter filter,
    DisplayPreferences prefs,
    LibraryColors colors,
  ) {
    final theme = Theme.of(context);
    final matching = sortEntries(
      filter.apply(library.entries),
      prefs.filteredSort,
    );

    final chips = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final chip in filter.chips)
              RemovableChip(
                label: chip.label,
                onRemove: () =>
                    ref.read(libraryFilterProvider.notifier).remove(chip),
              ),
            // With no results the empty state's button clears the filters, so
            // the chip row has no link of its own (Library › Empty states).
            if (matching.isNotEmpty)
              TextButton(
                onPressed: () =>
                    ref.read(libraryFilterProvider.notifier).clear(),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: theme.textTheme.labelMedium,
                ),
                child: const Text('Clear all'),
              ),
          ],
        ),
      ),
    );

    if (matching.isEmpty) {
      return _scrollView(header, [
        chips,
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: AppIcons.filters,
            title: 'Nothing matches these filters',
            body: filter.noMatchesText,
            actionLabel: 'Clear filters',
            onAction: () => ref.read(libraryFilterProvider.notifier).clear(),
          ),
        ),
      ]);
    }

    final countExtent = countRowExtent(MediaQuery.textScalerOf(context));
    final count = PinnedSliver(
      height: countExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${matching.length} ${matching.length == 1 ? 'entry' : 'entries'}',
                style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
              ),
            ),
            SortButton(
              current: prefs.filteredSort,
              onChanged: (sort) => ref
                  .read(displayPreferencesProvider.notifier)
                  .setFilteredSort(sort),
            ),
          ],
        ),
      ),
    );
    final types = matching.map((e) => e.type).toSet();
    return EntryListBody(
      key: ValueKey(filter),
      entries: matching,
      sort: prefs.filteredSort,
      view: EntryView.text,
      // One type: sections follow the sort in that type's color (Library ›
      // Filtered results, one type). Several: one section per type with a dot
      // rail (Library › Filtered results, several types).
      color: types.length == 1 ? colors.forType(types.single) : colors.muted,
      typeColors: colors.forType,
      controller: _scroll,
      leadingSlivers: [...header, chips, count],
      pinnedExtent: countExtent,
      groupSeries: groupsSeriesForFilter(filter.statuses),
      onTap: (entry) => widget.onOpenEntry?.call(entry),
      onTapSeries: (group) => openSeriesPage(context, group.parts.first.id),
    );
  }
}

/// The search field button and the filters button with its badge.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.hint,
    required this.filterCount,
    required this.onSearch,
    required this.onFilters,
  });

  final String hint;
  final int filterCount;
  final VoidCallback onSearch;
  final VoidCallback? onFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: theme.colorScheme.outline),
    );
    return Row(
      children: [
        Expanded(
          child: Material(
            color: theme.colorScheme.surface,
            shape: shape,
            child: InkWell(
              onTap: onSearch,
              customBorder: shape,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    StrokeIcon(AppIcons.search, color: colors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Badge(
          isLabelVisible: filterCount > 0,
          label: Text('$filterCount'),
          offset: const Offset(4, -4),
          child: Material(
            color: theme.colorScheme.surface,
            shape: shape,
            child: InkWell(
              onTap: onFilters,
              customBorder: shape,
              child: Tooltip(
                message: 'Filters',
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: StrokeIcon(
                      AppIcons.filters,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
