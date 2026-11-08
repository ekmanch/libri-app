import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../data/models/plan.dart';
import '../../data/models/season.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/labels.dart';
import '../../widgets/pinned_sliver.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/chips.dart';
import '../entry/series.dart';
import '../music/artist_screen.dart';
import '../music/music_type_body.dart';
import '../plans/plan_progress.dart';
import '../plans/plan_screen.dart';
import '../settings/display_preferences.dart';
import '../settings/entry_view.dart';
import '../shell/app_shell.dart';
import '../shell/floating_nav_bar.dart';
import 'active_plan_card.dart';
import 'coming_soon_screen.dart';
import 'entry_list_body.dart';
import 'entry_list_views.dart';
import 'home_sections.dart';
import 'home_type_provider.dart';
import 'library_filter.dart';
import 'library_filter_provider.dart';
import 'library_sort.dart';
import 'recent_changes.dart';
import 'series_groups.dart';
import 'sort_sheet.dart';
import 'view_menu.dart';

/// One page of the library home, kept once built: swiping away and back
/// finds it as it was left, scrolled where it was.
class HomePageKeeper extends StatefulWidget {
  const HomePageKeeper({super.key, required this.child});

  final Widget child;

  @override
  State<HomePageKeeper> createState() => _HomePageKeeperState();
}

class _HomePageKeeperState extends State<HomePageKeeper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// The Home chip's page: the active plan, then Coming soon, In progress and
/// Recently added (Library › Home), each only when it has something, up to
/// ten rows; the hint when none has (Library › Home: nothing to show). In
/// List with covers every row of the three sections has a small cover on
/// the left (Library › Home), in Text none (Library › Home: text view).
///
/// [top] is the room for the home's header, which lies over the pages and
/// follows this page's scroll ([controller]).
class HomeSectionsPage extends ConsumerWidget {
  const HomeSectionsPage({
    super.key,
    required this.controller,
    required this.top,
    this.onOpenEntry,
    this.onOpenPlan,
  });

  final ScrollController controller;
  final Widget top;
  final void Function(Entry entry)? onOpenEntry;
  final void Function(Plan plan)? onOpenPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).value;
    if (library == null) return const SizedBox.shrink();
    final covers =
        ref.watch(displayPreferencesProvider.select((p) => p.homeView)) ==
        EntryView.listWithPhotos;
    final plan = activePlan(library);
    final visible = LibraryFilter.none.apply(library.entries);
    final sections = homeSections(
      visible,
      today: seasonClock(),
      changes: ref.watch(recentChangesProvider),
      movieDates: ref.watch(movieDatesProvider).value ?? const {},
      releaseDates:
          (ref.watch(appSettingsProvider).value ?? AppSettings.defaults)
              .releaseDates,
      comingParts: ref.watch(comingPartsProvider).value ?? const [],
    );
    final rows = <Widget>[];
    for (final section in sections) {
      final seeAll = switch (section.kind) {
        // "See all" on Coming soon: the Coming soon screen on the tab last
        // picked, Library at first (Library › Coming soon: Library tab).
        HomeSectionKind.comingSoon => (
          'See all',
          () => openComingSoon(context),
        ),
        // "See all N" on In progress: the filter result with just that
        // status, across every type (Library › In progress, all types (See
        // all)).
        HomeSectionKind.inProgress => (
          'See all ${section.total}',
          () => ref
              .read(libraryFilterProvider.notifier)
              .set(const LibraryFilter(statuses: {EntryStatus.inProgress})),
        ),
        HomeSectionKind.recentlyAdded => null,
      };
      rows.add(
        SectionHeading(
          section.kind.title,
          action: seeAll?.$1,
          onAction: seeAll?.$2,
          // The same height as the heading with the See all button (its
          // 48 px, centered), so the three headings line up with their rows
          // alike (the canvas's 44 px heading rows).
          padding: seeAll != null
              ? const EdgeInsets.only(top: 10)
              : const EdgeInsets.fromLTRB(0, 26, 0, 16),
        ),
      );
      for (final row in section.rows) {
        rows.add(
          HomeRow(
            row,
            key: ValueKey('home-${section.kind.name}-${row.id}'),
            leading: covers
                ? HomeRow.cover(row.entry!, width: HomeRow.homeCoverWidth)
                : null,
            padding: covers ? HomeRow.homeCoverPadding : EdgeInsets.zero,
            onTap: () => onOpenEntry?.call(row.entry!),
          ),
        );
      }
    }

    return CustomScrollView(
      controller: controller,
      slivers: [
        top,
        if (plan != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ActivePlanCard(
                plan: plan,
                onTap: () => onOpenPlan != null
                    ? onOpenPlan!(plan)
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
      ],
    );
  }
}

/// A type chip's page: status segments, count, sort, view and the list in
/// the remembered view, all in one scroll; the count row pins at the top
/// once the rest has scrolled away (Library › Movies, text view; Movies,
/// list with covers; Movies, grid with covers). Music gets its artist, album
/// and song tabs instead (Library › Music: artists, text view). The status
/// segment is the type's own ([homeStatusProvider]).
///
/// [top] is the room for the home's header, which lies over the pages and
/// follows this page's scroll ([controller]).
class HomeTypePage extends ConsumerWidget {
  const HomeTypePage({
    super.key,
    required this.type,
    required this.controller,
    required this.top,
    this.onOpenEntry,
    this.onAddEntry,
  });

  final MediaType type;
  final ScrollController controller;
  final Widget top;
  final void Function(Entry entry)? onOpenEntry;
  final void Function({MediaType? type, String? title})? onAddEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).value;
    if (library == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final visible = LibraryFilter.none.apply(library.entriesOfType(type));
    if (visible.isEmpty) {
      return CustomScrollView(
        controller: controller,
        slivers: [
          top,
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: AppIcons.library,
              title: 'No ${type.label.toLowerCase()} yet',
              body: type == MediaType.music
                  ? 'Albums and songs you add will show up here.'
                  : '${type.label} you add will show up here.',
              actionLabel: 'Add ${type.singular.toLowerCase()}',
              onAction: () => onAddEntry?.call(type: type),
            ),
          ),
        ],
      );
    }
    if (type == MediaType.music) {
      return MusicTypeBody(
        entries: visible,
        controller: controller,
        leadingSlivers: [top],
        onOpenEntry: (entry) => onOpenEntry?.call(entry),
        onOpenArtist: (artist) =>
            openArtistScreen(context, artist, onOpenEntry: onOpenEntry),
      );
    }
    final prefs = ref.watch(displayPreferencesProvider);
    final status = ref.watch(homeStatusProvider.select((s) => s[type]));
    final shown = sortEntries(
      visible.where((e) => status == null || e.status == status),
      prefs.sortFor(type),
    );
    final view = prefs.viewFor(type);

    final segments = SliverToBoxAdapter(
      child: Padding(
        // The chips' 48 dp row holds their touch area: 8 dp above a 32 dp
        // chip, so 4 here gives the mockup's 12.
        padding: const EdgeInsets.only(top: 4),
        child: StatusChips(
          selected: status,
          type: type,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          onChanged: (status) =>
              ref.read(homeStatusProvider.notifier).set(type, status),
        ),
      ),
    );
    final countExtent = countRowExtent(
      MediaQuery.textScalerOf(context),
      top: 0,
    );
    final count = PinnedSliver(
      height: countExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
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
      return CustomScrollView(
        controller: controller,
        slivers: [
          top,
          segments,
          count,
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
              child: Text(
                'Nothing marked ${status!.lowerLabelFor(type)} yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: LibraryColors.of(context).muted,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return EntryListBody(
      entries: shown,
      sort: prefs.sortFor(type),
      view: view,
      color: LibraryColors.of(context).forType(type),
      controller: controller,
      leadingSlivers: [top, segments, count],
      pinnedExtent: countExtent,
      groupSeries: groupsSeriesFor(status),
      onTap: (entry) => onOpenEntry?.call(entry),
      onTapSeries: (group) => openSeriesPage(context, group.parts.first.id),
    );
  }
}
