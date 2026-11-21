import 'package:flutter/material.dart';

import '../data/models/entry.dart';
import '../data/models/entry_status.dart';
import '../data/models/media_type.dart';
import '../data/models/entry_kind.dart';
import '../data/models/season.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'labels.dart';
import 'row_ink_well.dart';
import 'type_kicker.dart';

/// The years a show ran, from its first season out to its last one out:
/// "2025–2026", or "2025" when they are the same. Null when no season is
/// out yet.
String? showYears(Entry entry, {DateTime? today}) {
  final day = today ?? DateTime.now();
  final years = [
    for (final s in entry.seasons ?? const <Season>[])
      if (s.isReleasedOn(day)) ?s.released?.year,
  ];
  if (years.isEmpty) return null;
  final first = years.first, last = years.last;
  return first == last ? '$first' : '$first–$last';
}

/// What stands in the year's place for a title that is not out.
const notReleasedYet = 'Not released yet';

/// The second line under a cover in the grid (the Library "Grid cells"
/// note): the year; for a show or an anime with seasons the years it ran
/// ("2011–2019", one year when they are the same), without the season
/// count, which would wrap there. "Not released yet" as in [entrySubtitle].
String gridYears(Entry entry, {DateTime? today}) {
  if (entry.seasons?.isNotEmpty ?? false) {
    return showYears(entry, today: today) ?? notReleasedYet;
  }
  final released = entry.released;
  if (released != null && !released.isReleasedOn(today ?? DateTime.now())) {
    return notReleasedYet;
  }
  return released?.year.toString() ?? '';
}

/// "2 seasons", or null for a show with one season or none.
String? seasonCountLabel(Entry entry) {
  final count = entry.seasons?.length ?? 0;
  return count > 1 ? '$count seasons' : null;
}

/// The italic line under a title. The year; for books and music the creator
/// and the year; for a song its album and the year; for a show or an anime
/// with seasons the years it ran, and the count when there is more than
/// one ("2025–2026 · 2 seasons"). "Not released yet" when the release date
/// is still ahead, or no season is out or dated.
String entrySubtitle(Entry entry, {DateTime? today}) {
  if (entry.seasons?.isNotEmpty ?? false) {
    final years = showYears(entry, today: today);
    if (years == null) return notReleasedYet;
    return [years, ?seasonCountLabel(entry)].join(' · ');
  }
  final released = entry.released;
  if (released != null && !released.isReleasedOn(today ?? DateTime.now())) {
    return notReleasedYet;
  }
  final year = released?.year.toString();
  final lead = switch (entry.type) {
    MediaType.books => entry.creator,
    MediaType.music when entry.kind == EntryKind.song =>
      entry.album ?? entry.creator,
    MediaType.music => entry.creator,
    _ => null,
  };
  return [
    lead,
    year,
  ].where((part) => part != null && part.isNotEmpty).join(' · ');
}

/// "Movie", "Album", "Song" and so on for one entry. An anime is "Anime"
/// whether a series or a movie.
String entryKindLabel(Entry entry) => switch (entry.kind) {
  EntryKind.album => 'Album',
  EntryKind.song => 'Song',
  _ => entry.type.singular,
};

/// A song's subtitle in the Songs tab (Library › Music: artists, text view):
/// the artist and the year the song, or the album it is on, came out. The tab
/// mixes every artist, so the artist is named, unlike on an artist's own
/// screen.
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
/// A series grouped as one row (Library › Series page (from a series row)
/// note) uses [subtitleIcon] for the stack before its subtitle and
/// [trailing] for "2 of 4 done" in the status mark's place.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.status,
    this.type,
    this.onTap,
    this.onLongPress,
    this.leading,
    this.typeLabel,
    this.typeColor,
    this.badge,
    this.subtitleIcon,
    this.trailing,
  }) : assert(status != null || trailing != null);

  /// [showType] adds the type word in its color before the subtitle, as in
  /// search results: "Show · 2021".
  EntryRow.forEntry(
    Entry entry, {
    super.key,
    this.onTap,
    this.onLongPress,
    this.leading,
    DateTime? today,
    bool showType = false,
    LibraryColors? colors,
    String? subtitle,
  }) : title = entry.title,
       subtitle = subtitle ?? entrySubtitle(entry, today: today),
       status = entry.status,
       type = entry.type,
       typeLabel = showType ? entryKindLabel(entry) : null,
       typeColor = showType ? colors?.forType(entry.type) : null,
       badge = entry.hasNewSeasonOn(today ?? DateTime.now())
           ? newSeasonLabel
           : null,
       subtitleIcon = null,
       trailing = null;

  static const newSeasonLabel = 'New season';

  final String title;
  final String subtitle;

  /// Drawn as a [StatusMark] at the end, unless [trailing] is given.
  final EntryStatus? status;

  /// Words the status mark: "Reading" for a book.
  final MediaType? type;
  final VoidCallback? onTap;

  /// A long press: the row's cover, larger (Library › Cover, larger).
  final VoidCallback? onLongPress;

  /// A small icon before the subtitle: the stack of a series row.
  final StrokeIconData? subtitleIcon;

  /// What ends the row instead of the status mark.
  final Widget? trailing;

  /// A cover or photo before the text. Rows with one are 76 px tall.
  final Widget? leading;
  final String? typeLabel;
  final Color? typeColor;

  /// An outlined label after the subtitle: "New season".
  final String? badge;

  /// The badge when the row is too tight for [badge] beside the whole
  /// subtitle: "New" for "New season".
  static const shortBadge = 'New';

  /// The subtitle, then the badge right after it. The badge reads "New season"
  /// as drawn (Library › Home); when the whole subtitle and it do not fit side
  /// by side, it shortens to "New", and only then does the subtitle give way.
  Widget _withBadge(TextSpan span) {
    final subtitle = Text.rich(
      span,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final badge = this.badge;
    if (badge == null) return subtitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          text: span,
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final needed = painter.width + 8 + OutlineBadge.widthOf(context, badge);
        painter.dispose();
        final label = needed <= constraints.maxWidth ? badge : shortBadge;
        return Row(
          children: [
            Flexible(child: subtitle),
            const SizedBox(width: 8),
            OutlineBadge(label),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.italic,
    );
    return RowInkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                      TextSpan(
                        children: [
                          if (subtitleIcon case final icon?) ...[
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: StrokeIcon(
                                icon,
                                size: 13,
                                color: colors.muted,
                              ),
                            ),
                            const TextSpan(text: ' '),
                          ],
                          // The type word in its color; on light, where a
                          // type color is only a fill, a dot and the word
                          // in the subtitle's gray.
                          if (typeLabel != null &&
                              typeColor != null &&
                              colors.typeColorsAreFills) ...[
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: TypeDot(typeColor!),
                            ),
                            const TextSpan(text: ' '),
                          ],
                          if (typeLabel != null)
                            TextSpan(
                              text: typeLabel,
                              style: theme.textTheme.bodySmall!.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.typeColorsAreFills
                                    ? null
                                    : typeColor,
                              ),
                            ),
                          if (typeLabel != null && subtitle.isNotEmpty)
                            TextSpan(text: ' · ', style: subtitleStyle),
                          TextSpan(text: subtitle, style: subtitleStyle),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? StatusMark(status!, type: type),
          ],
        ),
      ),
    );
  }
}

/// A small outlined label in the accent (dark gray on light): "New season",
/// "New". [large]
/// is the details header's, a step bigger.
class OutlineBadge extends StatelessWidget {
  const OutlineBadge(this.label, {super.key, this.large = false});

  final String label;
  final bool large;

  static TextStyle _style(BuildContext context, bool large) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      fontSize: large ? 12 : 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.4,
      color: AccentColors.of(context).link,
    );
  }

  static double _padding(bool large) => large ? 8 : 7;

  /// How wide the badge with [label] is drawn, border included.
  static double widthOf(
    BuildContext context,
    String label, {
    bool large = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _style(context, large)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width + 2 * _padding(large) + 2;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final ink = AccentColors.of(context).link;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _padding(large),
        vertical: large ? 2 : 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(large ? 10 : 9),
        border: Border.all(color: ink),
      ),
      child: Text(label, maxLines: 1, style: _style(context, large)),
    );
  }
}

/// A check in the accent color (dark gray on light) for Done; a small pill
/// with the status word otherwise. In progress is filled, Want and DNF are outlined. [type]
/// words it: "Reading" for a book.
class StatusMark extends StatelessWidget {
  const StatusMark(this.status, {super.key, this.type});

  final EntryStatus status;
  final MediaType? type;

  @override
  Widget build(BuildContext context) {
    if (status == EntryStatus.done) {
      return StrokeIcon(
        AppIcons.check,
        size: 20,
        color: AccentColors.of(context).link,
        semanticLabel: 'Done',
      );
    }
    return StatusPill(
      status.labelFor(type),
      filled: status == EntryStatus.inProgress,
    );
  }
}

/// The small pill of a [StatusMark]: filled for In progress, outlined for
/// Want and DNF. A series row's "2 of 4 done" is a filled one.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.filled = false});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? colors.selectedFill : null,
        borderRadius: BorderRadius.circular(12),
        border: filled ? null : Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium!.copyWith(fontSize: 12.5),
      ),
    );
  }
}
