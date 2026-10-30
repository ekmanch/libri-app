import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/season.dart';
import '../../data/operations/entry_operations.dart';
import '../../data/operations/season_operations.dart';
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
      'New seasons, parts and releases from the shows and series in your '
      'library. Tap one to add it.';
  static const emptyWants = 'Nothing you want is coming up.';
  static const emptyEverything = 'Nothing upcoming in your library.';

  @override
  ConsumerState<ComingSoonScreen> createState() => _ComingSoonScreenState();
}

class _ComingSoonScreenState extends ConsumerState<ComingSoonScreen> {
  late bool _everything = widget.startEverything;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(libraryProvider).value;
    final prefs = ref.watch(displayPreferencesProvider);
    final parts = ref.watch(upcomingPartsProvider).value ?? const [];
    final filter = ref.watch(libraryFilterProvider);
    final today = seasonClock();
    final all = library == null
        ? const <UpcomingItem>[]
        : upcomingItems(
            filter.apply(library.entries),
            parts: parts,
            prefs: prefs,
            today: today,
          );
    final wanted = wantedUpcoming(all);
    final items = _everything ? all : wanted;
    final notInLibrary = all.length - wanted.length;
    final subtitle = _everything
        ? '${all.length} upcoming · $notInLibrary not in your library'
        : '${wanted.length} ${wanted.length == 1 ? 'entry' : 'entries'} '
              'you want';
    final groups = upcomingGroups(items, today: today);

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
                onChanged: (value) => setState(() => _everything = value),
              ),
            ),
            if (_everything)
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
                        _everything
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
                                action: _everything
                                    ? (item.wanted ? 'Want' : 'Add')
                                    : null,
                                actionEmphasized: item.wanted,
                              ),
                              key: ValueKey('upcoming-${item.id}'),
                              minHeight: 60,
                              onTap: () => _open(item),
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

  /// Add to library: a part starts a new entry looked up for its title, as
  /// "+ Add" on the series page does; a season or an entry is set Want.
  Future<void> _add(UpcomingItem item) async {
    final repository = ref.read(libraryRepositoryProvider);
    switch (item.kind) {
      case UpcomingKind.part:
        await openNewEntryScreen(
          context,
          type: item.type,
          title: item.part!.title,
        );
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

  /// Not interested: a part is hidden the way Choose what to show hides it,
  /// so the series page agrees; an entry or a season by its own key.
  void _hide(UpcomingItem item) {
    final prefs = ref.read(displayPreferencesProvider.notifier);
    if (item.kind == UpcomingKind.part) {
      final part = item.part!;
      final key = seriesKey(part.type, part.seriesName);
      final current = ref.read(displayPreferencesProvider);
      prefs.setSeriesParts(
        key,
        hidden: {...current.hiddenPartsOf(key), part.partKey},
        shown: current.shownPartsOf(key),
      );
    } else {
      prefs.hideUpcoming(item.id);
    }
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
