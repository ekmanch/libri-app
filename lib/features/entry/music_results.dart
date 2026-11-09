import 'package:flutter/material.dart';

import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/music_lookup.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/lookup_notice.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import 'music_lookup_controller.dart';

/// 9800 as "9,800".
String groupedCount(int n) {
  final digits = '$n';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out';
}

/// The music lookup's count line: "412 albums" for a search, "Ghost · 38
/// albums, newest first" in an artist's list, and "Ghost · songs, newest
/// first" until an artist's songs are all listed.
String musicCountLine(MusicLookupController music, MusicScope scope) {
  final list = music.of(scope);
  final shown = list.matches.length;
  final artist = music.artist;
  if (artist == null) {
    final total = (list.total ?? shown) < shown ? shown : (list.total ?? shown);
    return '${groupedCount(total)} ${scope.noun(total)}';
  }
  return switch (list.total) {
    final total? =>
      '${artist.name} · ${groupedCount(total)} ${scope.noun(total)}, '
          'newest first',
    null => '${artist.name} · ${scope.noun(2)}, newest first',
  };
}

/// A music row's label: "Album", "EP" or "Single" as the lookup calls the
/// record, "Song" for a song.
String musicRowKind(LookupMatch match) {
  if (match.album != null) return 'Song';
  return switch (match.recordType) {
    'ep' => 'EP',
    'single' => 'Single',
    _ => 'Album',
  };
}

/// The results of the music lookup (Add / edit entry › Music search:
/// albums, … songs, … an artist's albums, … an artist's songs): the Albums
/// and the Songs list as two pages, so a swipe sideways flips the switch
/// as a tap on it does.
class MusicResults extends StatefulWidget {
  const MusicResults({
    super.key,
    required this.music,
    required this.onPick,
    this.openingSource,
  });

  final MusicLookupController music;

  /// A row was tapped; null while a pick is being fetched.
  final ValueChanged<LookupMatch>? onPick;

  /// The lookup id of the row being fetched in full, which shows a spinner.
  final String? openingSource;

  /// How near its end the list asks for the next page: about three rows.
  static const moreWithin = 3 * MusicRow.minHeight;

  @override
  State<MusicResults> createState() => _MusicResultsState();
}

class _MusicResultsState extends State<MusicResults> {
  late final _pages = PageController(initialPage: widget.music.scope.index);

  @override
  void initState() {
    super.initState();
    widget.music.addListener(_follow);
  }

  @override
  void didUpdateWidget(MusicResults old) {
    super.didUpdateWidget(old);
    if (old.music != widget.music) {
      old.music.removeListener(_follow);
      widget.music.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.music.removeListener(_follow);
    _pages.dispose();
    super.dispose();
  }

  /// The switch was tapped: the pages slide to its list.
  void _follow() {
    if (!_pages.hasClients) return;
    final at = widget.music.scope.index;
    if (_pages.page?.round() == at) return;
    _pages.animateToPage(at, duration: AppMotion.slide, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pages,
      onPageChanged: (page) => widget.music.setScope(MusicScope.values[page]),
      children: [
        for (final scope in MusicScope.values)
          _MusicListPage(
            music: widget.music,
            scope: scope,
            onPick: widget.onPick,
            openingSource: widget.openingSource,
          ),
      ],
    );
  }
}

class _MusicListPage extends StatefulWidget {
  const _MusicListPage({
    required this.music,
    required this.scope,
    required this.onPick,
    required this.openingSource,
  });

  final MusicLookupController music;
  final MusicScope scope;
  final ValueChanged<LookupMatch>? onPick;
  final String? openingSource;

  @override
  State<_MusicListPage> createState() => _MusicListPageState();
}

class _MusicListPageState extends State<_MusicListPage>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();

  /// How many rows the list held when it was last laid out. A page that
  /// was remembered lands at once, before the list has grown on screen,
  /// and a scroll that same frame still reports the old distance to the
  /// end; it must not ask for yet another page.
  int _rowsLaidOut = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Asks the next page when the list is about three rows from its end,
  /// also when what is listed does not fill the screen.
  void _moreWhenNearEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _rowsLaidOut = widget.music.of(widget.scope).matches.length;
    if (_scroll.position.extentAfter < MusicResults.moreWithin) {
      widget.music.more(of: widget.scope);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.music,
      builder: (context, _) => _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final music = widget.music;
    final scope = widget.scope;
    final list = music.of(scope);
    final artist = music.artist;
    final songs = scope == MusicScope.songs;
    WidgetsBinding.instance.addPostFrameCallback((_) => _moreWhenNearEnd());

    final head = <Widget>[
      if (artist != null)
        _BackToResults(query: music.query, onTap: music.closeArtist),
      if (list.failure case final failure?)
        LookupNotice(switch (failure) {
          LookupFailure.notConfigured =>
            'Lookups for music are not set up on this build (no API key).',
          LookupFailure.offline =>
            'Could not reach the lookup. Check your connection and try '
                'again.',
          _ => 'The lookup did not answer. Try again in a moment.',
        }, onRetry: failure == LookupFailure.notConfigured ? null : music.retry)
      else if (!list.loaded && !list.searching)
        // The list not looked at yet: asked when it is first shown.
        const SizedBox.shrink()
      else if (!list.loaded)
        LookupNotice(
          'Looking up ${artist == null ? '"${music.query}"' : artist.name}…',
          spinner: true,
        )
      else ...[
        if (artist == null && music.artists.isNotEmpty) ...[
          const SectionHeading(
            'Artists',
            padding: EdgeInsets.fromLTRB(0, 16, 0, 2),
          ),
          for (final hit in music.artists)
            _ArtistRow(
              artist: hit,
              scope: scope,
              onTap: () => music.openArtist(hit),
            ),
        ],
        if (list.matches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              artist == null
                  ? 'No ${scope.noun(2)} called that.'
                  : 'No ${scope.noun(2)} listed for ${artist.name}.',
              style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 2),
            child: Semantics(
              header: true,
              child: Text(
                musicCountLine(music, scope),
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.muted,
                ),
              ),
            ),
          ),
      ],
    ];
    final rows = list.loaded && list.failure == null
        ? list.matches
        : const <LookupMatch>[];
    final tail = rows.isEmpty
        ? null
        : list.moreFailed
        ? LookupNotice('Could not load more.', onRetry: music.retry)
        : list.loadingMore
        ? const _LoadingMore()
        : null;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            notification.depth == 0 &&
            _rowsLaidOut == list.matches.length &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < MusicResults.moreWithin) {
          music.more(of: scope);
        }
        return false;
      },
      child: ListView.builder(
        // A new list starts at its top.
        key: ValueKey((scope, list.epoch)),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        itemCount: head.length + rows.length + (tail == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index < head.length) return head[index];
          final at = index - head.length;
          if (at >= rows.length) return tail!;
          final match = rows[at];
          return MusicRow(
            match: match,
            year: music.releasedOf(match)?.year,
            detail: [
              if (artist == null) ?match.creator,
              if (songs) ?match.album,
            ].where((s) => s.isNotEmpty).join(' · '),
            opening: widget.openingSource == match.source,
            onTap: switch (widget.onPick) {
              final pick? => () => pick(match),
              null => null,
            },
          );
        },
      ),
    );
  }
}

/// "‹ All results for “ghost”" above an artist's list.
class _BackToResults extends StatelessWidget {
  const _BackToResults({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        child: RowInkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(AppIcons.back, size: 16, color: accent),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    'All results for “$query”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium!.copyWith(
                      fontSize: 14,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A matching artist above a music search's rows: the round photo, the
/// name, "Artist · 38 albums", and "All albums ›" or "All songs ›" by the
/// switch; it opens the artist's list.
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.artist,
    required this.scope,
    required this.onTap,
  });

  final ArtistHit artist;
  final MusicScope scope;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final accent = theme.colorScheme.primary;
    final albums = artist.albums;
    return Semantics(
      button: true,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              CachedImage(
                url: artist.pictureUrl,
                width: 52,
                height: 52,
                shape: BoxShape.circle,
                placeholder: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artist.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      albums == null
                          ? 'Artist'
                          : 'Artist · ${groupedCount(albums)} '
                                '${MusicScope.albums.noun(albums)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'All ${scope.noun(2)}',
                style: theme.textTheme.labelMedium!.copyWith(
                  fontSize: 14,
                  color: accent,
                ),
              ),
              const SizedBox(width: 2),
              StrokeIcon(AppIcons.chevronRightBold, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of the music lookup: the square cover, "Album · 2025" (or EP,
/// Single, Song) in the music color, the title on one line, then [detail]
/// (the artist in a search, the album for a song) when there is any.
class MusicRow extends StatelessWidget {
  const MusicRow({
    super.key,
    required this.match,
    required this.onTap,
    this.year,
    this.detail = '',
    this.opening = false,
  });

  final LookupMatch match;

  /// The album's year; it can come a moment after the row.
  final int? year;
  final String detail;
  final VoidCallback? onTap;

  /// The full details are being fetched for this row.
  final bool opening;

  static const minHeight = 72.0;
  static const coverSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return RowInkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            CachedImage(
              url: match.coverUrl,
              width: coverSize,
              height: coverSize,
              borderRadius: BorderRadius.circular(8),
              placeholder: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    [
                      musicRowKind(match),
                      if (year != null) '$year',
                    ].join(' · ').toUpperCase(),
                    style: theme.textTheme.labelSmall!.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.forType(MediaType.music),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    match.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (opening)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            else
              StrokeIcon(AppIcons.chevronRight, size: 18, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// "Loading more…" at the list's end while the next page is on its way.
class _LoadingMore extends StatelessWidget {
  const _LoadingMore();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.muted,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Loading more…',
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 14,
                color: colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
