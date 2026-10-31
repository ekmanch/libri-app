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
import '../../data/models/season.dart';
import '../../data/operations/entry_operations.dart';
import '../../data/operations/season_operations.dart';
import '../../data/operations/settings_operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/segmented_control.dart';
import '../../widgets/sheet_frame.dart';
import '../entry/entry_details_sheet.dart';
import '../entry/entry_form_screen.dart';
import '../entry/new_entry_screen.dart';
import '../entry/series.dart';
import '../settings/display_preferences.dart';
import '../shell/app_shell.dart';
import 'home_sections.dart';
import 'library_filter_provider.dart';
import 'upcoming.dart';

/// Opens the Coming soon screen (Library › Coming soon: your wants), from
/// "See all" on the home's Coming soon heading.
Future<void> openComingSoon(BuildContext context, {bool everything = false}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ComingSoonScreen(startEverything: everything),
      ),
    );

/// Everything coming, full screen (Library › Coming soon: your wants;
/// Coming soon: everything upcoming): "Coming soon" with a back arrow and a
/// count under it, then two segments. Your wants lists what the home's
/// Coming soon lists, with no cap, plus Want entries without a date under
/// "Date not set". Everything upcoming adds the coming seasons the owner
/// has not set, the parts of followed series not in the library, and every
/// other entry with a release ahead, each row saying "Want" or "Add" under
/// its date; tapping an "Add" row opens [UpcomingAddSheet]. Rows are
/// grouped by month, then year-only dates under their year, then "Date not
/// set"; a wanted row opens the entry's details.
class ComingSoonScreen extends ConsumerStatefulWidget {
  const ComingSoonScreen({super.key, this.startEverything = false});

  /// Open on Everything upcoming instead of Your wants.
  final bool startEverything;

  static const hint =
      'New seasons, parts and releases from the shows, series, authors and '
      'artists in your library. Tap one to add it.';
  static const emptyWants = 'Nothing you want is coming up.';
  static const emptyEverything = 'Nothing upcoming in your library.';

  @override
  ConsumerState<ComingSoonScreen> createState() => _ComingSoonScreenState();
}

class _ComingSoonScreenState extends ConsumerState<ComingSoonScreen> {
  late bool _everything = widget.startEverything;

  /// The two segments are pages, so a swipe moves between them as a tap on
  /// a segment does.
  late final PageController _pages = PageController(
    initialPage: widget.startEverything ? 1 : 0,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(bool everything) {
    if (everything == _everything) return;
    setState(() => _everything = everything);
    _pages.animateToPage(
      everything ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).value;
    final prefs = ref.watch(displayPreferencesProvider);
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
            releases: releases,
            prefs: prefs,
            settings: settings,
            today: today,
          );
    final wanted = wantedUpcoming(all);
    final notInLibrary = all.length - wanted.length;
    final subtitle = _everything
        ? '${all.length} upcoming · $notInLibrary not in your library'
        : '${wanted.length} ${wanted.length == 1 ? 'entry' : 'entries'} '
              'you want';

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Coming soon',
              subtitle: subtitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: SegmentedControl<bool>(
                segments: const [
                  SegmentOption(false, 'Your wants'),
                  SegmentOption(true, 'Everything upcoming'),
                ],
                selected: _everything,
                onChanged: _show,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (page) =>
                    setState(() => _everything = page == 1),
                children: [
                  _UpcomingPage(
                    wanted,
                    everything: false,
                    today: today,
                    onOpen: _open,
                  ),
                  _UpcomingPage(
                    all,
                    everything: true,
                    today: today,
                    onOpen: _open,
                  ),
                ],
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
    final result = await showAppSheet<UpcomingAddResult>(
      context,
      builder: (_) => UpcomingAddSheet(item, today: seasonClock()),
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
  /// the record knows, filled in by the source's details (the director, the
  /// genres, a game's platforms) when it answers; the record alone when it
  /// does not. Null for a part without a lookup id.
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
      );
    } else {
      return null;
    }
    final source = ref.read(lookupServiceProvider).sourceOf(known.source);
    if (source == null || !source.isConfigured) return known;
    try {
      return await source.details(known);
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

/// One segment's page: on Everything upcoming the hint, then the rows under
/// their month headings, or the empty text.
class _UpcomingPage extends StatelessWidget {
  const _UpcomingPage(
    this.items, {
    required this.everything,
    required this.today,
    required this.onOpen,
  });

  final List<UpcomingItem> items;
  final bool everything;
  final DateTime today;
  final ValueChanged<UpcomingItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = upcomingGroups(items, today: today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (everything)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              ComingSoonScreen.hint,
              style: theme.textTheme.bodySmall!.copyWith(height: 1.4),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                  child: Text(
                    everything
                        ? ComingSoonScreen.emptyEverything
                        : ComingSoonScreen.emptyWants,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    AppShell.contentBottomPadding,
                  ),
                  children: [
                    for (final group in groups) ...[
                      SectionHeading(
                        group.name,
                        padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
                      ),
                      for (final item in group.items)
                        HomeRow(
                          HomeRowData.text(
                            id: item.id,
                            title: item.title,
                            type: item.type,
                            detail: item.detail,
                            right: item.rightLabel(today),
                            emphasized: item.emphasized,
                            action: everything
                                ? (item.wanted ? 'Want' : 'Add')
                                : null,
                            actionEmphasized: item.wanted,
                          ),
                          key: ValueKey('upcoming-${item.id}'),
                          minHeight: 60,
                          onTap: () => onOpen(item),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// What the add sheet was closed with.
enum UpcomingAddResult { add, notInterested }

/// Library › Coming soon: add an upcoming entry: a sheet with the cover
/// spot, the type and date in the type's color, the title and creator, the
/// description when the source has one, "Why it's here", then Not
/// interested and Add to library, with "Added as Want. Not interested hides
/// it from this list." under them. Pops with an [UpcomingAddResult].
class UpcomingAddSheet extends StatelessWidget {
  const UpcomingAddSheet(this.item, {super.key, required this.today});

  final UpcomingItem item;
  final DateTime today;

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
                CoverPlaceholder(entry: _standIn(item), width: 72, fontSize: 9),
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
