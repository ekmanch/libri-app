import 'package:flutter/material.dart';

import '../data/models/entry.dart';
import '../data/models/entry_status.dart';
import '../data/models/media_type.dart';
import '../data/models/music_kind.dart';
import '../data/models/season.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'labels.dart';

/// The years a show with seasons ran, from its first season to its last:
/// "2025–2026", or "2025" when they are the same. Null without dated
/// seasons.
String? showYears(Entry entry) {
  final years = [
    for (final s in entry.seasons ?? const <Season>[]) ?s.released?.year,
  ];
  if (years.isEmpty) return null;
  final first = years.first, last = years.last;
  return first == last ? '$first' : '$first–$last';
}

/// "2 seasons", or null for a show with one season or none.
String? seasonCountLabel(Entry entry) {
  final count = entry.seasons?.length ?? 0;
  return count > 1 ? '$count seasons' : null;
}

/// The italic line under a title. The year; for books and music the creator
/// and the year; for a song its album and the year; for a show with more
/// than one season the years it ran and the count ("2025–2026 · 2
/// seasons"). "Not released yet" when the release date is still ahead.
String entrySubtitle(Entry entry, {DateTime? today}) {
  final released = entry.firstSeason?.released ?? entry.released;
  if (released != null && !released.isReleasedOn(today ?? DateTime.now())) {
    return 'Not released yet';
  }
  if (seasonCountLabel(entry) case final count?) {
    return [showYears(entry), count].whereType<String>().join(' · ');
  }
  final year = released?.year.toString();
  final lead = switch (entry.type) {
    MediaType.books => entry.creator,
    MediaType.music when entry.kind == MusicKind.song =>
      entry.album ?? entry.creator,
    MediaType.music => entry.creator,
    _ => null,
  };
  return [
    lead,
    year,
  ].where((part) => part != null && part.isNotEmpty).join(' · ');
}

/// "Movie", "Album", "Song" and so on for one entry.
String entryKindLabel(Entry entry) => switch (entry.kind) {
  MusicKind.album => 'Album',
  MusicKind.song => 'Song',
  null => entry.type.singular,
};

/// A song's subtitle in the Songs tab (A14): the artist and the year the
/// song, or the album it is on, came out. The tab mixes every artist, so
/// the artist is named, unlike on an artist's own screen.
String songSubtitle(Entry songOrAlbum, {DateTime? today}) {
  final released = songOrAlbum.released;
  if (released != null && !released.isReleasedOn(today ?? DateTime.now())) {
    return [
      songOrAlbum.creator,
      'Not released yet',
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
  }
  return [
    songOrAlbum.creator,
    released?.year.toString(),
  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

/// One entry in a list: title, italic subtitle and a status mark. No tags.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onTap,
    this.leading,
    this.typeLabel,
    this.typeColor,
    this.badge,
  });

  /// [showType] adds the type word in its color before the subtitle, as in
  /// search results: "Show · 2021".
  EntryRow.forEntry(
    Entry entry, {
    super.key,
    this.onTap,
    this.leading,
    DateTime? today,
    bool showType = false,
    LibraryColors? colors,
    String? subtitle,
  }) : title = entry.title,
       subtitle = subtitle ?? entrySubtitle(entry, today: today),
       status = entry.status,
       typeLabel = showType ? entryKindLabel(entry) : null,
       typeColor = showType ? colors?.forType(entry.type) : null,
       badge = entry.hasNewSeason ? newSeasonLabel : null;

  static const newSeasonLabel = 'New season';

  final String title;
  final String subtitle;
  final EntryStatus status;
  final VoidCallback? onTap;

  /// A cover or photo before the text. Rows with one are 76 px tall.
  final Widget? leading;
  final String? typeLabel;
  final Color? typeColor;

  /// An outlined label after the subtitle: "New season".
  final String? badge;

  /// The subtitle, then the badge right after it; the subtitle gives way.
  Widget _withBadge(Widget subtitle) {
    if (badge == null) return subtitle;
    return Row(
      children: [
        Flexible(child: subtitle),
        const SizedBox(width: 8),
        OutlineBadge(badge!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.italic,
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: leading == null ? 56 : 76),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty ||
                      typeLabel != null ||
                      badge != null) ...[
                    const SizedBox(height: 2),
                    _withBadge(
                      Text.rich(
                        TextSpan(
                          children: [
                            if (typeLabel != null)
                              TextSpan(
                                text: typeLabel,
                                style: theme.textTheme.bodySmall!.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: typeColor,
                                ),
                              ),
                            if (typeLabel != null && subtitle.isNotEmpty)
                              TextSpan(text: ' · ', style: subtitleStyle),
                            TextSpan(text: subtitle, style: subtitleStyle),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusMark(status),
          ],
        ),
      ),
    );
  }
}

/// A small outlined label in the accent ink: "New season", "New". [large]
/// is the details header's, a step bigger.
class OutlineBadge extends StatelessWidget {
  const OutlineBadge(this.label, {super.key, this.large = false});

  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 8 : 7,
        vertical: large ? 2 : 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(large ? 10 : 9),
        border: Border.all(color: ink),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: theme.textTheme.labelSmall!.copyWith(
          fontSize: large ? 12 : 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.4,
          color: ink,
        ),
      ),
    );
  }
}

/// A check in the accent color for Done; a small pill with the status word
/// otherwise. "In progress" is filled, Want and DNF are outlined.
class StatusMark extends StatelessWidget {
  const StatusMark(this.status, {super.key});

  final EntryStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    if (status == EntryStatus.done) {
      return StrokeIcon(
        AppIcons.check,
        size: 20,
        color: theme.colorScheme.primary,
        semanticLabel: 'Done',
      );
    }
    final filled = status == EntryStatus.inProgress;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? colors.selectedFill : null,
        borderRadius: BorderRadius.circular(12),
        border: filled ? null : Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelMedium!.copyWith(fontSize: 12.5),
      ),
    );
  }
}
