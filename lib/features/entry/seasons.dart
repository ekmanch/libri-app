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
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/touch_target.dart';

/// "1 season", "29 seasons".
String seasonsCount(int count) => count == 1 ? '1 season' : '$count seasons';

/// The Seasons section of a show's details (A29, A30, A31). Up to
/// [listedAll] seasons are all listed; with more, the latest three and a
/// row that opens every season (A32).
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
        for (final season in shown) SeasonRow(show: show, season: season),
        if (many)
          Semantics(
            button: true,
            label: more,
            excludeSemantics: true,
            child: InkWell(
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

/// One season: its name, "New" while it is, its release date, and the
/// status pill that opens the status sheet (A33).
class SeasonRow extends StatelessWidget {
  const SeasonRow({super.key, required this.show, required this.season});

  final Entry show;
  final Season season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final released = season.released;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
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
                      if (season.isNew) const OutlineBadge('New'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    released == null
                        ? 'Release date not set'
                        : releasedLabel(released),
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontStyle: FontStyle.normal,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SeasonStatusPill(
            season: season,
            onTap: () => showSeasonStatusSheet(
              context,
              showId: show.id,
              season: season.season,
            ),
          ),
        ],
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
  });

  final Season season;
  final VoidCallback onTap;

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

/// The season status sheet (A33): Not set, Want, In progress, Done, DNF.
/// A pick applies at once and closes the sheet. While an earlier season
/// is not Done, "Mark seasons 1–N Done" marks them all Done and keeps the
/// sheet open. Neither touches later seasons or the show's own status.
Future<void> showSeasonStatusSheet(
  BuildContext context, {
  required String showId,
  required int season,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => SeasonStatusSheet(showId: showId, season: season),
  );
}

class SeasonStatusSheet extends ConsumerWidget {
  const SeasonStatusSheet({
    super.key,
    required this.showId,
    required this.season,
  });

  final String showId;
  final int season;

  /// "Mark season 1 Done", "Mark seasons 1–28 Done".
  static String catchUpLabel(int season) =>
      season == 2 ? 'Mark season 1 Done' : 'Mark seasons 1–${season - 1} Done';

  /// "Released Oct 9, 2026. …", "Comes out Oct 30, 2026. …".
  static String subtitle(Season season, DateTime today) {
    const tail = "The show's own status stays as it is.";
    final released = season.released;
    if (released == null) return 'Release date not set. $tail';
    final verb = released.isReleasedOn(today) ? 'Released' : 'Comes out';
    return '$verb ${releasedLabel(released)}. $tail';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final show = ref.watch(libraryProvider).value?.entryById(showId);
    final seasons = show?.seasons ?? const <Season>[];
    final current = seasons.where((s) => s.season == season).firstOrNull;
    if (show == null || current == null) return const SizedBox(height: 120);
    final repository = ref.read(libraryRepositoryProvider);
    final behind = seasons.any(
      (s) => s.season < season && s.status != EntryStatus.done,
    );
    return SheetFrame(
      title: 'Season $season',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            subtitle(current, DateTime.now()),
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
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  if (status != current.status) {
                    repository.apply(SetSeasonStatus(showId, season, status));
                  }
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
              label: catchUpLabel(season),
              kind: AppButtonKind.outline,
              icon: const StrokeIcon(AppIcons.checkBold, size: 16),
              onPressed: () =>
                  repository.apply(MarkSeasonsDone(showId, season)),
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

/// Opens every season of the show (A32).
Future<void> openAllSeasons(BuildContext context, String showId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AllSeasonsScreen(showId: showId)),
    );

/// Every season of a show, oldest first (A32), opened scrolled to the
/// season being watched: the one In progress, else the first not Done.
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
