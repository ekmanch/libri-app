import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/episode_info.dart';
import '../../data/lookup/episode_service.dart';
import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/models/released.dart';
import '../../data/models/season.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/labels.dart';
import '../../widgets/section_heading.dart';
import 'seasons.dart';

/// Opens a season's episodes (Show & seasons › Season episodes (all out) and
/// Season episodes (airing weekly)).
Future<void> openSeason(BuildContext context, String showId, int season) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeasonScreen(showId: showId, season: season),
      ),
    );

/// One season of a show, for viewing (Show & seasons › Season episodes (all
/// out) and Season episodes (airing weekly)): the show and the season with its
/// date and episode count, the season's status pill (the Show & seasons › All
/// seasons, just added: catch up sheet), then every episode with its number,
/// title, air date and runtime. Episodes not out yet are dimmed. Nothing here
/// is ticked or edited; the episodes come from the lookup and stay on the
/// phone.
class SeasonScreen extends ConsumerWidget {
  const SeasonScreen({super.key, required this.showId, required this.season});

  final String showId;
  final int season;

  /// "1 episode", "10 episodes".
  static String episodesCount(int count) =>
      count == 1 ? '1 episode' : '$count episodes';

  /// The header's line: "Oct 9, 2026 · 10 episodes" once all are out,
  /// "Started Sep 24, 2026 · 4 of 6 episodes out" while airing, "Coming
  /// Oct 30, 2026 · 8 episodes" before. Without episodes, the season's
  /// date as its row has it. The date is the first episode's, else the
  /// season's.
  static String headerLine(
    Season season,
    List<EpisodeInfo>? episodes,
    DateTime today,
  ) {
    if (episodes == null || episodes.isEmpty) {
      return seasonDateLabel(season, today);
    }
    final start = episodes.first.aired ?? season.released;
    final date = start == null ? null : releasedLabel(start);
    final out = episodes.where((e) => isOut(e, today)).length;
    final count = episodes.length;
    if (out == 0) {
      return [
        ?date == null ? null : 'Coming $date',
        episodesCount(count),
      ].join(' · ');
    }
    if (out < count) {
      return [
        ?date == null ? null : 'Started $date',
        '$out of $count episodes out',
      ].join(' · ');
    }
    return [?date, episodesCount(count)].join(' · ');
  }

  /// Out on [today]. An episode without an air date is not out yet.
  static bool isOut(EpisodeInfo episode, DateTime today) =>
      episode.aired?.isReleasedOn(today) ?? false;

  /// Every episode out, all on one day: the date is then in the header
  /// only (Show & seasons › Season episodes (all out)).
  static bool sameDay(List<EpisodeInfo> episodes, DateTime today) =>
      episodes.isNotEmpty &&
      episodes.every(
        (e) =>
            isOut(e, today) &&
            e.aired?.day != null &&
            e.aired == episodes.first.aired,
      );

  /// "Oct 22" in [year], "Jan 5, 2027" outside it; a partial date as the
  /// Released field shows it.
  static String shortDate(Released date, int year) {
    if (date.day == null || date.year != year) return releasedLabel(date);
    return '${monthAbbreviations[date.month! - 1]} ${date.day}';
  }

  /// The line under an episode's title: "Oct 1 · 22 min", "24 min" on a
  /// season out in one day, "Airs Oct 22" before it is out.
  static String episodeLine(
    EpisodeInfo episode, {
    required bool sameDay,
    required int year,
    required DateTime today,
  }) {
    final aired = episode.aired;
    if (!isOut(episode, today)) {
      return aired == null
          ? 'Air date not set'
          : 'Airs ${shortDate(aired, year)}';
    }
    return [
      if (!sameDay && aired != null) shortDate(aired, year),
      if (episode.runtime case final minutes?) '$minutes min',
    ].join(' · ');
  }

  /// "Title TBA" until the lookup has one; "Episode 5" for an episode out
  /// without a title.
  static String episodeTitle(EpisodeInfo episode, DateTime today) =>
      episode.title ??
      (isOut(episode, today) ? 'Episode ${episode.number}' : 'Title TBA');

  /// Why no episodes are listed.
  static String reason(AsyncValue<SeasonEpisodes?> value) {
    if (value.isLoading) return 'Loading episodes…';
    return switch (value.error) {
      LookupException(failure: LookupFailure.offline) =>
        'The episodes need a connection.',
      LookupException(failure: LookupFailure.notConfigured) =>
        'The episode lookup is not set up on this build.',
      LookupException(failure: LookupFailure.rateLimited) =>
        'The episode lookup is busy. Try again in a minute.',
      _ => 'No episodes were found for this season.',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final show = ref.watch(libraryProvider).value?.entryById(showId);
    final current = show?.seasons?.where((s) => s.season == season).firstOrNull;
    final value = ref.watch(
      seasonEpisodesProvider((showId: showId, season: season)),
    );
    final episodes = value.value?.episodes;
    final today = seasonClock();
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      color: colors.muted,
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    // A 48 dp target whose icon lines up with the margin,
                    // as in the page header.
                    offset: const Offset(-14, 0),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                      color: theme.colorScheme.onSurface,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const StrokeIcon(AppIcons.back, size: 22),
                    ),
                  ),
                  Expanded(
                    child: Transform.translate(
                      offset: const Offset(-10, 0),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (show != null)
                              Text(
                                show.title.toUpperCase(),
                                style: theme.textTheme.labelSmall!.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colors.forType(show.type),
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              'Season $season',
                              style: theme.textTheme.headlineMedium,
                            ),
                            if (current != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                headerLine(current, episodes, today),
                                style: muted,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (show != null && current != null)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Status',
                        style: muted.copyWith(fontSize: 15),
                      ),
                    ),
                    SeasonStatusPill(
                      season: current,
                      onTap: () => showSavedSeasonStatusSheet(
                        context,
                        ref,
                        show: show,
                        season: season,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  const SectionHeading(
                    'Episodes',
                    padding: EdgeInsets.only(top: 14, bottom: 2),
                  ),
                  if (episodes == null || episodes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        reason(value),
                        style: muted.copyWith(fontSize: 13.5),
                      ),
                    )
                  else ...[
                    for (final episode in episodes)
                      _EpisodeRow(
                        episode: episode,
                        sameDay: sameDay(episodes, today),
                        year:
                            (episodes.first.aired ?? current?.released)?.year ??
                            today.year,
                        today: today,
                      ),
                    const SizedBox(height: 14),
                    Text(
                      'Episode details from ${value.value?.provider ?? 'TMDB'}.',
                      style: muted.copyWith(fontSize: 13, height: 1.4),
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
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.sameDay,
    required this.year,
    required this.today,
  });

  final EpisodeInfo episode;
  final bool sameDay;
  final int year;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final title = SeasonScreen.episodeTitle(episode, today);
    final line = SeasonScreen.episodeLine(
      episode,
      sameDay: sameDay,
      year: year,
      today: today,
    );
    return Semantics(
      label: [
        'Episode ${episode.number}',
        title,
        if (line.isNotEmpty) line,
      ].join(', '),
      excludeSemantics: true,
      child: Opacity(
        opacity: SeasonScreen.isOut(episode, today) ? 1 : 0.55,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '${episode.number}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontSize: 15,
                    color: colors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        line,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
