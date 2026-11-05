import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/library.dart';
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
import '../entry/series.dart';
import '../music/music_tab.dart';
import '../settings/display_preferences.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_banner.dart';
import 'library_skeleton.dart';
import '../settings/entry_view.dart';
import 'entry_list_body.dart';
import 'entry_list_views.dart';
import 'filter_sheet.dart';
import 'home_pages.dart';
import 'home_return_provider.dart';
import 'home_type_provider.dart';
import 'library_filter.dart';
import 'library_filter_provider.dart';
import 'library_sort.dart';
import 'library_search.dart';
import 'search_screen.dart';
import 'series_groups.dart';
import 'sort_sheet.dart';
import 'view_menu.dart';

/// The library home (Library › Home). On Home it shows the active plan, then
/// Coming soon, In progress and Recently added. With a type chip picked it
/// is that type's list (Library › Movies, text view; Movies, list with
/// covers; Movies, grid with covers): status segments, count, sort and view;
/// Music gets its artist, album and song tabs instead (Library › Music:
/// artists, text view). Also shows filtered results (Library › Filtered
/// results, one type and several types) and the empty states (Library ›
/// Empty states).
///
/// Home and the types are pages side by side, in chip order: a swipe left or
/// right on the content moves to the next or the previous one, as a tap on
/// its chip does, with no wrap-around at the ends. Each page keeps its own
/// scroll position, and each type its view, sort and status segment. Swipes
/// that start at a screen edge are left to Android's back gesture, and
/// filtered results, which have no single type, do not swipe.
///
/// The whole top scrolls with the list: the title, the banner, the search
/// box, the type chips and the status segments scroll away, while the count
/// row (count, sort, view) pins at the top as it gets there, so the entries
/// get the rest of the screen. The header (down to the chips) is one piece
/// laid over the pages, so it stays put sideways during a swipe; it follows
/// the scroll of the page shown, and between two pages it moves from where
/// the one has it to where the other has it. Library in the pill brings the
/// top back (see [_onReturn]).
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

  /// The pages in chip order: Home (null), then one per type.
  static const pages = <MediaType?>[null, ...MediaType.values];

  /// How far from a screen edge a swipe has to start to move the pages,
  /// at least: Android's back gesture owns the edges. The system's own
  /// width is used where it is wider.
  static const edgeWidth = 24.0;

  @override
  ConsumerState<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends ConsumerState<LibraryHomeScreen> {
  static const _tabs = LibraryHomeScreen.pages;

  /// The scroll position of the bodies that are not pages: filtered results
  /// and the load that failed.
  final _scroll = ScrollController();

  /// One scroll position per page, so each is where it was left.
  late final List<ScrollController> _scrolls = [
    for (final _ in _tabs) _PageScrollController(_positionsChanged),
  ];

  /// The chip row's position and its chips, so the picked chip can be
  /// brought into view.
  final _chipScroll = ScrollController();
  final _chipKeys = [for (final _ in _tabs) GlobalKey()];

  late PageController _pages;

  /// The type whose chip is shown as picked: the page nearest the middle of
  /// the screen. Only the header listens, so a swipe builds nothing else;
  /// [homeTypeProvider] follows when the pages come to rest.
  late final ValueNotifier<MediaType?> _shown;

  /// The header's height, measured, for the room the pages leave for it.
  final _headerHeight = ValueNotifier<double>(0);

  /// How far up the header has scrolled, from 0 to its height.
  final _shift = ValueNotifier<double>(0);
  late final _headerMoves = Listenable.merge([_shift, _headerHeight]);

  @override
  void initState() {
    super.initState();
    final type = ref.read(homeTypeProvider);
    _shown = ValueNotifier(type)..addListener(_revealChip);
    _pages = _newPages(type);
    for (final scroll in _scrolls) {
      scroll.addListener(_updateShift);
    }
    _headerHeight.addListener(_updateShift);
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    _chipScroll.dispose();
    _pages.dispose();
    _shown.dispose();
    _headerHeight.dispose();
    _shift.dispose();
    super.dispose();
  }

  PageController _newPages(MediaType? type) =>
      PageController(initialPage: _tabs.indexOf(type))
        ..addListener(_onPageScroll);

  /// How far the pages are scrolled, in pages.
  double get _page {
    if (_pages.hasClients) {
      final position = _pages.position;
      if (position.hasPixels && position.hasContentDimensions) {
        return _pages.page!.clamp(0, _tabs.length - 1).toDouble();
      }
    }
    return _tabs.indexOf(_shown.value).toDouble();
  }

  /// The position of the list a controller drives, or null before it has
  /// one. While a page swaps one list for another (a status with nothing in
  /// it) both are attached for a moment; the new one is the last.
  static ScrollPosition? _positionOf(ScrollController controller) {
    final positions = controller.positions;
    if (positions.isEmpty) return null;
    final position = positions.last;
    return position.hasPixels ? position : null;
  }

  /// Every frame of a swipe. Nothing here rebuilds the pages or writes a
  /// provider: a swipe that does either stutters.
  void _onPageScroll() {
    _shown.value = _tabs[_page.round()];
    _updateShift();
  }

  /// The header follows the scroll of the page shown; between two pages it
  /// is as far up as the swipe is between them.
  void _updateShift() {
    final height = _headerHeight.value;
    double at(int i) =>
        (_positionOf(_scrolls[i])?.pixels ?? 0).clamp(0, height).toDouble();
    final page = _page;
    final from = page.floor();
    final to = math.min(from + 1, _tabs.length - 1);
    _shift.value = lerpDouble(at(from), at(to), page - from)!;
  }

  /// A page got a new list (a view or a status changed): the header may
  /// have to move, once the frame that attached it is over.
  void _positionsChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateShift();
    });
  }

  /// The pages came to rest, after a swipe: the type they rest on is the
  /// one picked. Written now and not on the way, since the shell's "+"
  /// button follows it.
  bool _settled(ScrollEndNotification notification) {
    if (notification.depth != 0 || !_pages.hasClients) return false;
    final type = _tabs[_page.round()];
    _shown.value = type;
    if (ref.read(homeTypeProvider) != type) {
      ref.read(homeTypeProvider.notifier).set(type);
    }
    return false;
  }

  /// Shows the page of [type], at once: a chip tapped, or the type changed
  /// from outside (the filter sheet, a return to the home).
  void _showPage(MediaType? type) {
    final index = _tabs.indexOf(type);
    if (_pages.hasClients) {
      if (_page.round() != index) _pages.jumpToPage(index);
    } else if (_pages.initialPage != index) {
      // No pages yet (the library is still loading): they open on this one.
      _pages.dispose();
      _pages = _newPages(type);
    }
    _shown.value = type;
  }

  /// The chip row follows the pages: the picked chip slides to the middle
  /// of the row, or as near as the row's ends allow.
  void _revealChip() {
    final chip = _chipKeys[_tabs.indexOf(_shown.value)].currentContext;
    if (chip == null) return;
    Scrollable.ensureVisible(
      chip,
      alignment: 0.5,
      duration: AppMotion.slide,
      curve: Curves.easeOut,
    );
  }

  /// Library tapped in the pill while this screen is on top. Scrolled
  /// down: back to the top, so the header is in view again. At the top:
  /// back to Home, with the filter and the type cleared, every type's
  /// status segment (and the music tab) reset and its list at the top, and
  /// the chip row slid back to Home.
  void _onReturn() {
    final paged =
        ref.read(libraryProvider).hasValue &&
        !ref.read(libraryFilterProvider).isActive;
    final position = _positionOf(paged ? _scrolls[_page.round()] : _scroll);
    if (position != null && position.pixels > 0) {
      position.animateTo(0, duration: AppMotion.slide, curve: Curves.easeOut);
      return;
    }
    ref.read(libraryFilterProvider.notifier).clear();
    ref.read(homeTypeProvider.notifier).set(null);
    ref.read(homeStatusProvider.notifier).clear();
    ref.read(homeMusicTabProvider.notifier).set(MusicTab.artists);
    _showPage(null);
    for (final scroll in _scrolls) {
      _positionOf(scroll)?.jumpTo(0);
    }
    // Home may have been the page all along (a filter over it), with the
    // chip row left scrolled to the type the filter was opened from.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealChip();
    });
  }

  void _pickType(MediaType? type) {
    ref.read(homeTypeProvider.notifier).set(type);
    _showPage(type);
  }

  /// Opens the filter sheet. With no filter active it starts with what the home
  /// shows: the picked type and its status segment or music tab (Library ›
  /// Filter sheet from Movies (Done picked)).
  Future<void> _openFilters(Library library) async {
    final filter = ref.read(libraryFilterProvider);
    final type = ref.read(homeTypeProvider);
    final result = await showFilterSheet(
      context,
      library: library,
      initial: filter.isActive
          ? filter
          : LibraryFilter.ofTypeView(
              type,
              status: ref.read(homeStatusProvider)[type],
              kind: type == MediaType.music
                  ? ref.read(homeMusicTabProvider).kind
                  : null,
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
    final libraryAsync = ref.watch(libraryProvider);
    final library = libraryAsync.value;
    ref.listen(homeReturnProvider, (_, _) => _onReturn());
    ref.listen(homeTypeProvider, (_, type) => _showPage(type));

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

    // What stands in for the pages: the load that failed, or the results of
    // a filter, which have no single type and so do not swipe.
    final Widget? instead;
    if (library == null) {
      instead = _loadFailed(libraryAsync.error);
    } else if (filter.isActive) {
      instead = _filtered(library, filter, prefs, colors);
    } else {
      instead = null;
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The pages stay as they are under the results of a filter, so
            // clearing it finds each type where it was left.
            if (library != null)
              Offstage(
                offstage: instead != null,
                child: _pager(library, prefs),
              ),
            if (instead != null)
              RefreshIndicator(onRefresh: _refresh, child: instead),
          ],
        ),
      ),
    );
  }

  /// The title, the banner and the search row, and for the pages the type
  /// chips with [type] picked.
  Widget _header({
    required Library? library,
    required DisplayPreferences prefs,
    required bool chips,
    MediaType? type,
  }) {
    final colors = LibraryColors.of(context);
    final filter = ref.read(libraryFilterProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Library',
          actions: [
            // The home's own view button sits beside the gear, on Home only
            // (Library › Home: view menu); a type's is in its count row.
            if (chips && type == null)
              ViewMenuButton(
                current: prefs.homeView,
                views: DisplayPreferences.homeViews,
                muted: true,
                onChanged: ref
                    .read(displayPreferencesProvider.notifier)
                    .setHomeView,
              ),
            SettingsButton(onPressed: _openSettings),
          ],
        ),
        const SyncBannerCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: _SearchRow(
            hint: searchHint(chips ? type : null),
            filterCount: filter.count,
            onSearch: _openSearch,
            onFilters: library == null ? null : () => _openFilters(library),
          ),
        ),
        if (chips)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 44,
              child: ListView(
                controller: _chipScroll,
                scrollDirection: Axis.horizontal,
                // Every chip is built, wherever the row is scrolled, so the
                // picked one can be brought into view.
                scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                children: [
                  for (final (i, t) in _tabs.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    PillChip(
                      key: _chipKeys[i],
                      // The first chip reads "Home" (canvas revision of
                      // 2026-10-28); the state it stands for is still All
                      // here.
                      label: t?.label ?? 'Home',
                      selected: type == t,
                      animated: true,
                      dotColor: t == null ? null : colors.forType(t),
                      onTap: () => _pickType(t),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The header as the first sliver of a body that is not paged.
  Widget _headerSliver(Library? library, DisplayPreferences prefs) =>
      SliverToBoxAdapter(
        child: _header(library: library, prefs: prefs, chips: false),
      );

  /// Home and the types as pages, the header laid over them.
  Widget _pager(Library library, DisplayPreferences prefs) {
    final gestures = MediaQuery.systemGestureInsetsOf(context);
    final top = _HeaderSpace(_headerHeight);
    return RefreshIndicator(
      onRefresh: _refresh,
      // The lists are one scroll view further in, inside the pages.
      notificationPredicate: (notification) => notification.depth == 1,
      // The header leaves through the top as it scrolls away.
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            NotificationListener<ScrollEndNotification>(
              onNotification: _settled,
              child: PageView(
                controller: _pages,
                // The pages beside the one shown are built before they are
                // swiped to, so a swipe starts with nothing to build.
                allowImplicitScrolling: true,
                children: [
                  for (final (i, type) in _tabs.indexed)
                    HomePageKeeper(
                      child: type == null
                          ? HomeSectionsPage(
                              controller: _scrolls[i],
                              top: top,
                              onOpenEntry: widget.onOpenEntry,
                              onOpenPlan: widget.onOpenPlan,
                            )
                          : HomeTypePage(
                              type: type,
                              controller: _scrolls[i],
                              top: top,
                              onOpenEntry: widget.onOpenEntry,
                              onAddEntry: widget.onAddEntry,
                            ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // A drag that starts on the header scrolls the page under it,
              // as it did when the header was part of the list.
              child: _HitTestPassThrough(
                child: AnimatedBuilder(
                  animation: _headerMoves,
                  builder: (context, header) => Offstage(
                    // Scrolled away: out of the tree's sight too.
                    offstage:
                        _shift.value > 0 && _shift.value >= _headerHeight.value,
                    child: Transform.translate(
                      offset: Offset(0, -_shift.value),
                      child: header,
                    ),
                  ),
                  child: _MeasuredSize(
                    onChanged: (size) {
                      if (mounted) _headerHeight.value = size.height;
                    },
                    // Opaque: between two pages it passes over their lists.
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: ValueListenableBuilder<MediaType?>(
                        valueListenable: _shown,
                        builder: (context, type, _) => _header(
                          library: library,
                          prefs: prefs,
                          chips: true,
                          type: type,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // A swipe that starts at a screen edge is Android's back
            // gesture: these take it before the pages can, and do nothing
            // with it. Taps and vertical drags pass through.
            for (final left in const [true, false])
              Positioned(
                top: 0,
                bottom: 0,
                left: left ? 0 : null,
                right: left ? null : 0,
                width: math.max(
                  LibraryHomeScreen.edgeWidth,
                  left ? gestures.left : gestures.right,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  excludeFromSemantics: true,
                  onHorizontalDragStart: (_) {},
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pull-to-refresh: asks GitHub for changes. A library that failed to
  /// load is loaded again.
  Future<void> _refresh() async {
    if (ref.read(libraryProvider).hasError) ref.invalidate(libraryProvider);
    await ref.read(librarySyncProvider)?.checkForChanges();
  }

  /// A scroll view of [slivers], on the position of the bodies that are
  /// not pages.
  Widget _scrollView(List<Widget> slivers) =>
      CustomScrollView(controller: _scroll, slivers: slivers);

  /// The first download failed (offline, a bad token): say so, and let a
  /// pull or the button try again.
  Widget _loadFailed(Object? error) {
    final theme = Theme.of(context);
    return _scrollView([
      _headerSliver(null, ref.read(displayPreferencesProvider)),
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

  /// Filtered results (Library › Filtered results, one type and several types):
  /// removable chips, then the count and sort row, which pins, then the rows
  /// grouped by type; a long list gets a rail (Library › Filtered results, one
  /// type and several types).
  Widget _filtered(
    Library library,
    LibraryFilter filter,
    DisplayPreferences prefs,
    LibraryColors colors,
  ) {
    final theme = Theme.of(context);
    final header = _headerSliver(library, prefs);
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
      return _scrollView([
        header,
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
      leadingSlivers: [header, chips, count],
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

/// The room a page leaves at its top for the home's header, which lies over
/// the pages: as tall as the header is.
class _HeaderSpace extends StatelessWidget {
  const _HeaderSpace(this.height);

  final ValueListenable<double> height;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: height,
    builder: (context, height, _) =>
        SliverToBoxAdapter(child: SizedBox(height: height)),
  );
}

/// A page's scroll controller that says when a list is attached or let go:
/// a new list starts at the top without a scroll to tell of it.
class _PageScrollController extends ScrollController {
  _PageScrollController(this.onPositionsChanged);

  final VoidCallback onPositionsChanged;

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    onPositionsChanged();
  }

  @override
  void detach(ScrollPosition position) {
    super.detach(position);
    onPositionsChanged();
  }
}

/// Reports its child's size after each layout that changes it.
class _MeasuredSize extends SingleChildRenderObjectWidget {
  const _MeasuredSize({required this.onChanged, super.child});

  final ValueChanged<Size> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredSize(onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredSize renderObject,
  ) => renderObject.onChanged = onChanged;
}

class _RenderMeasuredSize extends RenderProxyBox {
  _RenderMeasuredSize(this.onChanged);

  ValueChanged<Size> onChanged;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    final measured = _reported = size;
    // Not during layout: the listeners build.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(measured));
  }
}

/// Lets what lies under its child be hit as well: the child's buttons get
/// their taps, and a drag that starts on the child still reaches the
/// scroll views beneath it.
class _HitTestPassThrough extends SingleChildRenderObjectWidget {
  const _HitTestPassThrough({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitTestPassThrough();
}

class _RenderHitTestPassThrough extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) hitTestChildren(result, position: position);
    return false;
  }
}
