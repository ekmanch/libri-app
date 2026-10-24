import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/season.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/chips.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/radio_mark.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/touch_target.dart';
import 'season_screen.dart';

/// A season's date in its row: "Sep 19, 2025"; "Coming 2027" or "Coming
/// Oct 30, 2026" while it is not out; "Release date not set".
String seasonDateLabel(Season season, DateTime today) {
  final released = season.released;
  if (released == null) return 'Release date not set';
  final date = releasedLabel(released);
  return released.isReleasedOn(today) ? date : 'Coming $date';
}

/// The show's status as its seasons give it, in place of the status control
/// (Show & seasons › Show with seasons (Haunted Hotel)): "Status · In
/// progress · from seasons", above Rating.
class ShowStatusRow extends StatelessWidget {
  const ShowStatusRow({super.key, required this.status});

  final EntryStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 15,
      color: colors.muted,
    );
    return Semantics(
      label: 'Status, ${status.label}, from seasons',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Text('Status', style: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: status.label,
                      style: theme.textTheme.titleMedium!.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    TextSpan(text: ' · from seasons', style: muted),
                  ],
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status of a show with one season (Show & seasons › One season (Carrie)):
/// "Status" and the pill of Season 1, whose status is the show's. The pill
/// opens the status sheet titled with the show.
class SingleSeasonStatusRow extends ConsumerWidget {
  const SingleSeasonStatusRow({super.key, required this.show});

  final Entry show;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final season = show.seasons!.single;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Status',
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 15,
                color: colors.muted,
              ),
            ),
          ),
          SeasonStatusPill(
            season: season,
            semanticsLabel:
                'Status: ${season.status?.lowerLabel ?? 'not set'}. Change',
            onTap: () => showSavedSeasonStatusSheet(
              context,
              ref,
              show: show,
              season: season.season,
              title: show.title,
            ),
          ),
        ],
      ),
    );
  }
}

/// The form's status for a show with several seasons (Add / edit entry › Edit a
/// show): a quiet field with the status they give and "Set by the seasons".
class DerivedStatusField extends StatelessWidget {
  const DerivedStatusField({super.key, required this.status});

  final EntryStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      label: 'Status, ${status.label}, set by the seasons',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                status.label,
                style: theme.textTheme.titleMedium!.copyWith(fontSize: 15.5),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Set by the seasons',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall!.copyWith(
                  fontStyle: FontStyle.normal,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1 season", "29 seasons".
String seasonsCount(int count) => count == 1 ? '1 season' : '$count seasons';

/// The Seasons section of a show's details (Show & seasons › Show with seasons
/// (Haunted Hotel); New season just out; Many seasons (South Park); One season
/// (Carrie)). Up to [listedAll] seasons are all listed; with more, the latest
/// three and a row that opens every season (Show & seasons › All seasons).
class SeasonsSection extends StatelessWidget {
  const SeasonsSection({super.key, required this.show});

  final Entry show;

  static const listedAll = 5;
  static const latestShown = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final seasons = show.seasons ?? const <Season>[];
    final many = seasons.length > listedAll;
    final shown = many
        ? seasons.sublist(seasons.length - latestShown)
        : seasons;
    final more = 'All ${seasons.length} seasons';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          'Seasons',
          padding: EdgeInsets.zero,
          trailing: seasonsCount(seasons.length),
        ),
        for (final season in shown)
          SeasonRow(
            show: show,
            season: season,
            // One season: its status is the Status row's pill (Show & seasons ›
            // One season (Carrie)).
            showPill: seasons.length > 1,
          ),
        if (many)
          Semantics(
            button: true,
            label: more,
            excludeSemantics: true,
            // No press highlight: the seasons list opening is the feedback.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openAllSeasons(context, show.id),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        more,
                        style: theme.textTheme.titleMedium!.copyWith(
                          fontSize: 15,
                        ),
                      ),
                    ),
                    StrokeIcon(
                      AppIcons.chevronRight,
                      size: 18,
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

/// One season: its name, "New" while it is, its release date, the status pill
/// that opens the status sheet (Show & seasons › All seasons, just added: catch
/// up) unless [showPill] is false (the one season of Show & seasons › One
/// season (Carrie)), and a chevron. The rest of the row opens the season's
/// episodes (Show & seasons › Season episodes (all out), Season episodes
/// (airing weekly) and Episodes of a one-season show).
class SeasonRow extends ConsumerWidget {
  const SeasonRow({
    super.key,
    required this.show,
    required this.season,
    this.showPill = true,
  });

  final Entry show;
  final Season season;
  final bool showPill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final today = DateTime.now();
    final isNew = season.isNewOn(today);
    final date = seasonDateLabel(season, today);
    void open() => openSeason(context, show.id, season.season);
    // No press highlight: the episodes opening is the feedback.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: open,
      excludeFromSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label:
                    'Season ${season.season}${isNew ? ', new' : ''}, $date. '
                    'Episodes',
                onTap: open,
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Season ${season.season}',
                            style: theme.textTheme.titleMedium,
                          ),
                          if (isNew) const OutlineBadge('New'),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (showPill) ...[
              const SizedBox(width: 12),
              SeasonStatusPill(
                season: season,
                onTap: () => showSavedSeasonStatusSheet(
                  context,
                  ref,
                  show: show,
                  season: season.season,
                ),
              ),
            ],
            // The chevron runs into the margin, as drawn.
            const SizedBox(width: 4),
            ExcludeSemantics(
              child: StrokeIcon(
                AppIcons.chevronRight,
                size: 18,
                color: colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A season's status as a small pill with a chevron: dashed while not set,
/// filled for In progress, outlined otherwise, with a check for Done.
class SeasonStatusPill extends StatelessWidget {
  const SeasonStatusPill({
    super.key,
    required this.season,
    required this.onTap,
    this.semanticsLabel,
  });

  final Season season;
  final VoidCallback onTap;

  /// In place of "Season 2 status: done. Change".
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final status = season.status;
    final label = status?.label ?? 'Not set';
    final color = status == null ? colors.muted : theme.colorScheme.onSurface;
    final content = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: switch (status) {
        null => null,
        EntryStatus.inProgress => BoxDecoration(
          color: colors.selectedFill,
          borderRadius: BorderRadius.circular(15),
        ),
        _ => BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: theme.colorScheme.outline),
        ),
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == EntryStatus.done) ...[
            StrokeIcon(AppIcons.checkBold, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium!.copyWith(
              fontSize: 12.5,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          StrokeIcon(
            AppIcons.chevronDown,
            size: 14,
            color: color.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
    return TouchTarget(
      child: Semantics(
        button: true,
        label:
            semanticsLabel ??
            'Season ${season.season} status: '
                '${status?.lowerLabel ?? 'not set'}. Change',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: status == null
              ? CustomPaint(
                  painter: DashedStadiumPainter(theme.colorScheme.outline),
                  child: content,
                )
              : content,
        ),
      ),
    );
  }
}

/// The season status sheet (Show & seasons › All seasons, just added: catch
/// up): Not set, Want, In progress, Done, DNF. A pick goes to [onPick] and
/// closes the sheet. While an earlier season is not Done, "Mark seasons 1–N
/// Done" calls [onCatchUp] and keeps the sheet open. Details save both at once;
/// the form keeps them until Save. [title] replaces "Season N" (the show's name
/// for a show with one season, Show & seasons › One season (Carrie)).
Future<void> showSeasonStatusSheet(
  BuildContext context, {
  required List<Season> seasons,
  required int season,
  required ValueChanged<EntryStatus?> onPick,
  required VoidCallback onCatchUp,
  String? title,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => SeasonStatusSheet(
      seasons: seasons,
      season: season,
      onPick: onPick,
      onCatchUp: onCatchUp,
      title: title,
    ),
  );
}

/// [showSeasonStatusSheet] for a show in the library: picks and catch-up
/// are saved at once.
Future<void> showSavedSeasonStatusSheet(
  BuildContext context,
  WidgetRef ref, {
  required Entry show,
  required int season,
  String? title,
}) {
  final repository = ref.read(libraryRepositoryProvider);
  return showSeasonStatusSheet(
    context,
    seasons: show.seasons ?? const [],
    season: season,
    title: title,
    onPick: (status) =>
        repository.apply(SetSeasonStatus(show.id, season, status)),
    onCatchUp: () => repository.apply(MarkSeasonsDone(show.id, season)),
  );
}

class SeasonStatusSheet extends StatefulWidget {
  const SeasonStatusSheet({
    super.key,
    required this.seasons,
    required this.season,
    required this.onPick,
    required this.onCatchUp,
    this.title,
  });

  final List<Season> seasons;
  final int season;
  final ValueChanged<EntryStatus?> onPick;
  final VoidCallback onCatchUp;
  final String? title;

  /// "Mark season 1 Done", "Mark seasons 1–28 Done".
  static String catchUpLabel(int season) =>
      season == 2 ? 'Mark season 1 Done' : 'Mark seasons 1–${season - 1} Done';

  /// "Released Oct 9, 2026.", "Comes out Oct 30, 2026.", or "Release date
  /// not set.".
  static String subtitle(Season season, DateTime today) {
    final released = season.released;
    if (released == null) return 'Release date not set.';
    final verb = released.isReleasedOn(today) ? 'Released' : 'Comes out';
    return '$verb ${releasedLabel(released)}.';
  }

  @override
  State<SeasonStatusSheet> createState() => _SeasonStatusSheetState();
}

class _SeasonStatusSheetState extends State<SeasonStatusSheet> {
  late List<Season> _seasons = widget.seasons;

  void _catchUp() {
    widget.onCatchUp();
    setState(() {
      _seasons = [
        for (final s in _seasons)
          s.season < widget.season
              ? s.copyWith(status: EntryStatus.done, fresh: null)
              : s,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final season = widget.season;
    final current = _seasons.where((s) => s.season == season).firstOrNull;
    if (current == null) return const SizedBox(height: 120);
    final behind = _seasons.any(
      (s) => s.season < season && s.status != EntryStatus.done,
    );
    return SheetFrame(
      title: widget.title ?? 'Season $season',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            SeasonStatusSheet.subtitle(current, DateTime.now()),
            style: theme.textTheme.bodyMedium!.copyWith(
              fontSize: 14,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 8),
          for (final status in <EntryStatus?>[null, ...EntryStatus.values])
            Semantics(
              button: true,
              selected: status == current.status,
              child: RowInkWell(
                onTap: () {
                  Navigator.pop(context);
                  if (status != current.status) widget.onPick(status);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.divider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          status?.label ?? 'Not set',
                          style: theme.textTheme.bodyMedium!.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      RadioMark(selected: status == current.status),
                    ],
                  ),
                ),
              ),
            ),
          if (behind) ...[
            const SizedBox(height: 16),
            AppButton(
              label: SeasonStatusSheet.catchUpLabel(season),
              kind: AppButtonKind.outline,
              icon: const StrokeIcon(AppIcons.checkBold, size: 16),
              onPressed: _catchUp,
            ),
            const SizedBox(height: 8),
            Text(
              "For catching up when you add a show you're partway through.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall!.copyWith(
                fontStyle: FontStyle.normal,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens every season of the show (Show & seasons › All seasons).
Future<void> openAllSeasons(BuildContext context, String showId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AllSeasonsScreen(showId: showId)),
    );

/// Every season of a show, oldest first (Show & seasons › All seasons), opened
/// scrolled to the season being watched: the one In progress, else the first
/// not Done.
class AllSeasonsScreen extends ConsumerStatefulWidget {
  const AllSeasonsScreen({super.key, required this.showId});

  final String showId;

  /// The index of the season to open at.
  static int currentIndex(List<Season> seasons) {
    final watching = seasons.indexWhere(
      (s) => s.status == EntryStatus.inProgress,
    );
    if (watching >= 0) return watching;
    final next = seasons.indexWhere((s) => s.status != EntryStatus.done);
    return next >= 0 ? next : math.max(0, seasons.length - 1);
  }

  @override
  ConsumerState<AllSeasonsScreen> createState() => _AllSeasonsScreenState();
}

class _AllSeasonsScreenState extends ConsumerState<AllSeasonsScreen> {
  final _current = GlobalKey();
  bool _scrolled = false;

  void _scrollToCurrent() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _current.currentContext;
      if (target == null || !target.mounted) return;
      // A few seasons above it stay in view.
      Scrollable.ensureVisible(target, alignment: 0.35);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final show = ref.watch(libraryProvider).value?.entryById(widget.showId);
    final seasons = show?.seasons ?? const <Season>[];
    if (seasons.isNotEmpty) _scrollToCurrent();
    final current = AllSeasonsScreen.currentIndex(seasons);
    final years = show == null ? null : showYears(show);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: show?.title ?? 'Seasons',
              onBack: () => Navigator.pop(context),
            ),
            // Under the title, past the back arrow (Show & seasons › All
            // seasons).
            Padding(
              padding: const EdgeInsets.fromLTRB(68, 0, 20, 8),
              child: Text(
                [seasonsCount(seasons.length), ?years].join(' · '),
                style: theme.textTheme.bodySmall!.copyWith(
                  fontStyle: FontStyle.normal,
                  fontSize: 13.5,
                  color: colors.muted,
                ),
              ),
            ),
            Expanded(
              child: show == null
                  ? const SizedBox()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, season) in seasons.indexed)
                            SeasonRow(
                              key: i == current ? _current : null,
                              show: show,
                              season: season,
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
}
