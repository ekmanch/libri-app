import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/release_dates.dart';
import '../../data/models/season.dart';
import '../../data/operations/entry_operations.dart';
import '../../data/operations/season_operations.dart';
import '../../data/operations/settings_operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/underline_tabs.dart';
import '../entry/entry_details_sheet.dart';
import '../entry/entry_form_screen.dart';
import '../entry/new_entry_screen.dart';
import '../entry/series.dart';
import '../settings/display_preferences.dart';
import '../settings/entry_view.dart';
import '../shell/app_shell.dart';
import 'coming_soon_tab.dart';
import 'home_sections.dart';
import 'library_filter_provider.dart';
import 'upcoming.dart';
import 'view_menu.dart';

/// Opens the Coming soon screen (Library › Coming soon: Library tab), from
/// "See all" on the home's Coming soon heading, on the tab last picked.
Future<void> openComingSoon(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (_) => const ComingSoonScreen()));

/// Everything coming, full screen (Library › Coming soon: Library tab,
/// Coming soon: Discover tab, Coming soon: All tab): "Coming soon" with a
/// back arrow, then three underline tabs across the width, each with its
/// count ("Library 29"). Library lists what the home's Coming soon lists,
/// with no cap, plus Want entries without a date under "Date not set", each
/// row with its date alone. Discover lists what the owner has not asked for:
/// the coming seasons not set, the parts of followed series not in the
/// library and every other entry with a release ahead, each row saying
/// "Add" under its date; tapping one opens [UpcomingAddSheet]. All lists
/// both, each row saying "Want" or "Add". Rows are grouped by month, then
/// year-only dates under their year, then "Date not set"; a wanted row
/// opens the entry's details. A swipe moves between the tabs as a tap does,
/// and the tab last picked is remembered, like the view. The view button at
/// the top right offers Text and List with covers (Coming soon: view menu;
/// no grid), remembered for this page on its own and used by all three tabs
/// (Coming soon: list with covers).
class ComingSoonScreen extends ConsumerStatefulWidget {
  const ComingSoonScreen({super.key});

  static const emptyLibrary = 'Nothing you want is coming up.';
  static const emptyDiscover = 'Nothing new is coming up.';
  static const emptyAll = 'Nothing upcoming in your library.';

  static String emptyText(ComingSoonTab tab) => switch (tab) {
    ComingSoonTab.library => emptyLibrary,
    ComingSoonTab.discover => emptyDiscover,
    ComingSoonTab.all => emptyAll,
  };

  @override
  ConsumerState<ComingSoonScreen> createState() => _ComingSoonScreenState();
}

class _ComingSoonScreenState extends ConsumerState<ComingSoonScreen> {
  late final ComingSoonTab _opened = ref
      .read(displayPreferencesProvider)
      .comingSoonTab;

  /// The tabs are pages, so a swipe moves between them as a tap on a tab
  /// does. Opens on the tab last picked.
  late final PageController _pages = PageController(initialPage: _opened.index)
    ..addListener(_scrolled);

  /// The tab shown as selected: the page nearest the middle of the screen,
  /// or during a tap's animation the tab tapped. Only the tab row listens.
  late final ValueNotifier<ComingSoonTab> _tab = ValueNotifier(_opened);

  /// How far the pages are scrolled, in pages, for the accent line.
  late final ValueNotifier<double> _position = ValueNotifier(
    _opened.index.toDouble(),
  );

  /// The tab a tap is animating to. Library to All passes Discover, which
  /// is not shown as selected on the way.
  ComingSoonTab? _target;

  @override
  void dispose() {
    _pages.dispose();
    _tab.dispose();
    _position.dispose();
    super.dispose();
  }

  ComingSoonTab get _nearest {
    final last = ComingSoonTab.values.length - 1;
    return ComingSoonTab.values[(_pages.page ?? 0).round().clamp(0, last)];
  }

  /// Every frame of a swipe. Nothing here rebuilds the screen or touches
  /// the preferences: a swipe that does either stutters.
  void _scrolled() {
    final page = _pages.page;
    if (page == null) return;
    _position.value = page.clamp(0, ComingSoonTab.values.length - 1);
    if (_target == null) _tab.value = _nearest;
  }

  void _show(ComingSoonTab tab) {
    if (tab == _tab.value) return;
    _target = tab;
    _tab.value = tab;
    _pages
        .animateToPage(
          tab.index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (_target == tab) _target = null;
        });
  }

  /// The pages came to rest, after a swipe or a tap: the tab they rest on
  /// is the one remembered. Written now and not on the way, since a changed
  /// preference rebuilds the home under this page and saves a file.
  bool _settled(ScrollEndNotification notification) {
    if (notification.depth == 0 && _pages.hasClients) {
      final tab = _nearest;
      _tab.value = tab;
      ref.read(displayPreferencesProvider.notifier).setComingSoonTab(tab);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).value;
    // Every preference but the tab: picking a tab must not build this
    // screen, and its lists, again.
    final prefs = ref.watch(
      displayPreferencesProvider.select(
        (p) => p.copyWith(comingSoonTab: ComingSoonTab.library),
      ),
    );
    final parts = ref.watch(upcomingPartsProvider).value ?? const [];
    final releases = ref.watch(foundReleasesProvider).value ?? const [];
    final settings =
        ref.watch(appSettingsProvider).value ?? AppSettings.defaults;
    final filter = ref.watch(libraryFilterProvider);
    final today = seasonClock();
    final all = library == null
        ? const <UpcomingItem>[]
        : upcomingItems(
            filter.apply(library.entries),
            parts: parts,
            comingParts: ref.watch(comingPartsProvider).value ?? const [],
            releases: releases,
            prefs: prefs,
            settings: settings,
            movieDates: ref.watch(movieDatesProvider).value ?? const {},
            today: today,
          );
    final items = {
      ComingSoonTab.library: wantedUpcoming(all),
      ComingSoonTab.discover: [
        for (final item in all)
          if (!item.wanted) item,
      ],
      ComingSoonTab.all: all,
    };
    final view = prefs.comingSoonView;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Coming soon',
              onBack: () => Navigator.of(context).pop(),
              actions: [
                ViewMenuButton(
                  current: view,
                  views: const [EntryView.text, EntryView.listWithPhotos],
                  onChanged: ref
                      .read(displayPreferencesProvider.notifier)
                      .setComingSoonView,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: ValueListenableBuilder(
                valueListenable: _tab,
                builder: (context, selected, _) => UnderlineTabs<ComingSoonTab>(
                  tabs: [
                    for (final tab in ComingSoonTab.values)
                      UnderlineTab(tab, tab.label, count: items[tab]!.length),
                  ],
                  selected: selected,
                  position: _position,
                  onChanged: _show,
                ),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollEndNotification>(
                onNotification: _settled,
                child: PageView(
                  controller: _pages,
                  // The tabs beside the one shown are built before they are
                  // swiped to, so a swipe starts with nothing to build.
                  allowImplicitScrolling: true,
                  children: [
                    for (final tab in ComingSoonTab.values)
                      _UpcomingPage(
                        items[tab]!,
                        tab: tab,
                        view: view,
                        today: today,
                        onOpen: _open,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A wanted row opens the entry's details; one that is not opens the add
  /// sheet (Library › Coming soon: add an upcoming entry).
  Future<void> _open(UpcomingItem item) async {
    if (item.wanted) {
      await showEntryDetailsSheet(context, item.entry!.id);
      return;
    }
    final releaseDates =
        (ref.read(appSettingsProvider).value ?? AppSettings.defaults)
            .releaseDates;
    final result = await showAppSheet<UpcomingAddResult>(
      context,
      builder: (_) => UpcomingAddSheet(
        item,
        today: seasonClock(),
        releaseDates: releaseDates,
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case UpcomingAddResult.add:
        await _add(item);
      case UpcomingAddResult.notInterested:
        _hide(item);
    }
  }

  /// Add to library: a part or a found release opens the entry form
  /// prefilled from its lookup id with status Want (the match is known, so
  /// nothing is asked twice); a part without an id starts a new entry looked
  /// up for its title, as "+ Add" on the series page does; a season or an
  /// entry is set Want.
  Future<void> _add(UpcomingItem item) async {
    final repository = ref.read(libraryRepositoryProvider);
    switch (item.kind) {
      case UpcomingKind.part:
      case UpcomingKind.release:
        final match = await _matchFor(item);
        if (!mounted) return;
        if (match == null) {
          await openNewEntryScreen(
            context,
            type: item.type,
            title: item.part?.title ?? item.title,
          );
        } else {
          await openNewEntryForm(context, match: match);
        }
      case UpcomingKind.season:
        await repository.apply(
          SetSeasonStatus(
            item.entry!.id,
            item.season!.season,
            EntryStatus.want,
          ),
        );
      case UpcomingKind.entry:
        await repository.apply(SetStatus(item.entry!.id, EntryStatus.want));
    }
  }

  /// The row as a match the form can start from: the lookup id with what
  /// the record knows, the cover the sheet showed among it, filled in by
  /// the source's details (the director, the genres, a game's platforms)
  /// when it answers; the record alone when it does not. Null for a part
  /// without a lookup id.
  Future<LookupMatch?> _matchFor(UpcomingItem item) async {
    final LookupMatch known;
    if (item.release case final release?) {
      known = release.match;
    } else if (item.part case final part? when part.source != null) {
      known = LookupMatch(
        type: part.type,
        title: part.title,
        source: part.source!,
        released: part.released,
        coverUrl: part.cover,
      );
    } else {
      return null;
    }
    final source = ref.read(lookupServiceProvider).sourceOf(known.source);
    if (source == null || !source.isConfigured) return known;
    try {
      final full = await source.details(known);
      // The details may not carry a cover (the fake's do not); the one the
      // sheet showed, already on the device, stays with the form then.
      if (full.cacheCoverUrl == null && known.cacheCoverUrl != null) {
        return full.copyWith(
          coverUrl: known.coverUrl,
          largeCoverUrl: known.largeCoverUrl,
        );
      }
      return full;
    } on LookupException {
      return known;
    }
  }

  /// Not interested: a part is hidden the way Choose what to show hides it,
  /// so the series page agrees; an entry, a season or a found release by its
  /// own key in the settings (`settings.json`, so a desktop agrees).
  void _hide(UpcomingItem item) {
    if (item.kind == UpcomingKind.part) {
      final prefs = ref.read(displayPreferencesProvider.notifier);
      final part = item.part!;
      final key = seriesKey(part.type, part.seriesName);
      final current = ref.read(displayPreferencesProvider);
      prefs.setSeriesParts(
        key,
        hidden: {...current.hiddenPartsOf(key), part.partKey},
        shown: current.shownPartsOf(key),
      );
    } else {
      unawaited(
        ref
            .read(libraryRepositoryProvider)
            .applySettings(SetNotInterested(item.id, title: item.sheetTitle)),
      );
    }
  }
}

/// One tab's page: the rows under their month headings, or the empty text.
/// In [EntryView.listWithPhotos] each row has a small cover on the left (Library › Coming soon: list with
/// covers): the entry's own, or for a part or a found release the one the
/// daily check recorded, fetched and cached only for the rows on screen
/// (the list builds lazily); a title without art yet gets a plain tile
/// tinted in the type's color. A page stays alive once built, so coming
/// back to a tab finds it as it was left, scrolled where it was.
class _UpcomingPage extends StatefulWidget {
  const _UpcomingPage(
    this.items, {
    required this.tab,
    required this.view,
    required this.today,
    required this.onOpen,
  });

  final List<UpcomingItem> items;
  final ComingSoonTab tab;
  final EntryView view;
  final DateTime today;
  final ValueChanged<UpcomingItem> onOpen;

  /// The cover's width in the list with covers, as the canvas draws it
  /// (44 × 66 for a poster).
  static const coverWidth = 44.0;

  /// Room above and below a cover.
  static const coverRowPadding = EdgeInsets.symmetric(vertical: 10);

  @override
  State<_UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<_UpcomingPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget? _cover(UpcomingItem item) {
    if (widget.view != EntryView.listWithPhotos) return null;
    if (item.entry case final entry?) {
      return HomeRow.cover(entry, width: _UpcomingPage.coverWidth);
    }
    return CachedImage(
      url: item.coverUrl,
      width: _UpcomingPage.coverWidth,
      height:
          _UpcomingPage.coverWidth / CoverPlaceholder.aspectRatio(item.type),
      placeholder: CoverTint(type: item.type, width: _UpcomingPage.coverWidth),
      borderRadius: BorderRadius.circular(8),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final _UpcomingPage(:items, :tab, :view, :today, :onOpen) = widget;
    final theme = Theme.of(context);
    final groups = upcomingGroups(items, today: today);
    // Headings and rows as one flat list, so the list can build lazily.
    final lines = <Object>[
      for (final group in groups) ...[group, ...group.items],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                  child: Text(
                    ComingSoonScreen.emptyText(tab),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    AppShell.contentBottomPadding,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, i) => switch (lines[i]) {
                    final UpcomingItem item => HomeRow(
                      HomeRowData.text(
                        id: item.id,
                        title: item.title,
                        type: item.type,
                        detail: item.detail,
                        right: item.rightLabel(today),
                        emphasized: item.emphasized,
                        // The Library tab's rows are all wanted: the date
                        // alone.
                        action: tab == ComingSoonTab.library
                            ? null
                            : (item.wanted ? 'Want' : 'Add'),
                        actionEmphasized: item.wanted,
                      ),
                      key: ValueKey('upcoming-${item.id}'),
                      minHeight: 60,
                      leading: _cover(item),
                      padding: view == EntryView.listWithPhotos
                          ? _UpcomingPage.coverRowPadding
                          : EdgeInsets.zero,
                      onTap: () => onOpen(item),
                    ),
                    final UpcomingGroup group => SectionHeading(
                      group.name,
                      padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
      ],
    );
  }
}

/// What the add sheet was closed with.
enum UpcomingAddResult { add, notInterested }

/// Library › Coming soon: add an upcoming entry: a sheet with the cover
/// (the entry's for an entry or a season; for a part or a found release
/// the cover the daily check recorded, fetched and cached when the sheet
/// opens, the placeholder while the title has no art yet), the type and
/// date in the type's color, the title and creator, for a movie with
/// Release dates set to Both its two dates ("In cinemas Dec 18 · Digital
/// Feb 2027"), the description when the source has one, "Why it's here",
/// then Not interested and Add to library, with "Added as Want. Not
/// interested hides it from this list." under them. Pops with an
/// [UpcomingAddResult].
class UpcomingAddSheet extends StatelessWidget {
  const UpcomingAddSheet(
    this.item, {
    super.key,
    required this.today,
    this.releaseDates = ReleaseDates.both,
  });

  final UpcomingItem item;
  final DateTime today;
  final ReleaseDates releaseDates;

  static const note = 'Added as Want. Not interested hides it from this list.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14.5,
      height: 1.2,
      color: colors.muted,
    );
    final entry = item.entry;
    final both = releaseDates == ReleaseDates.both
        ? bothDatesLabel(item.dates, today: today)
        : null;
    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry != null)
                CoverImage(entry: entry, width: 72, fontSize: 9, labeled: true)
              else
                CachedImage(
                  url: item.coverUrl,
                  width: 72,
                  height: 72 / CoverPlaceholder.aspectRatio(item.type),
                  placeholder: CoverPlaceholder(
                    entry: _standIn(item),
                    width: 72,
                    fontSize: 9,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  semanticLabel: item.sheetTitle,
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.type.singular} · ${item.rightLabel(today)}'
                            .toUpperCase(),
                        style: theme.textTheme.labelSmall!.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.forType(item.type),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(item.sheetTitle, style: theme.textTheme.titleLarge),
                      if (item.creator case final creator?) ...[
                        const SizedBox(height: 6),
                        Text(creator, style: muted),
                      ],
                      if (both != null) ...[
                        const SizedBox(height: 6),
                        Text(both, style: muted),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              item.description,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 14.5,
                color: colors.soft,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Why it’s here: ${item.reason}',
            style: theme.textTheme.bodySmall!.copyWith(height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Not interested',
                  kind: AppButtonKind.outline,
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(UpcomingAddResult.notInterested),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Add to library',
                  onPressed: () =>
                      Navigator.of(context).pop(UpcomingAddResult.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            note,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// A part has no entry yet; the placeholder only needs a title and type.
  static Entry _standIn(UpcomingItem item) => Entry(
    id: item.id,
    type: item.type,
    title: item.title,
    status: EntryStatus.want,
    added: DateTime(2000),
  );
}
