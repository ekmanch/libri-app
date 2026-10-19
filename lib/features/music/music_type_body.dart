import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/music_kind.dart';
import '../../data/models/track.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/pinned_sliver.dart';
import '../../widgets/segmented_control.dart';
import '../library/cover_grid_tile.dart';
import '../../widgets/cover_image.dart';
import '../library/entry_list_body.dart';
import '../library/entry_list_views.dart';
import '../library/entry_sections.dart';
import '../library/home_type_provider.dart';
import '../library/library_sort.dart';
import '../library/sectioned_list_body.dart';
import '../library/view_menu.dart';
import '../settings/display_preferences.dart';
import '../settings/entry_view.dart';
import 'artist_index.dart';
import 'artist_tiles.dart';
import 'music_tab.dart';

/// The music list with Music picked on the home (Library › Music: artists, text
/// view; Music: artists, list with photos; Music: artists, grid with photos):
/// an Artists / Albums / Songs toggle instead of status segments, one count
/// line for all three, no sort, and a view button whose choice is kept per tab.
/// Albums and Songs are flat lists in title order; the Songs tab lists song
/// entries and rated tracks together.
class MusicTypeBody extends ConsumerStatefulWidget {
  const MusicTypeBody({
    super.key,
    required this.entries,
    required this.onOpenEntry,
    required this.onOpenArtist,
    this.controller,
    this.leadingSlivers = const [],
  });

  /// The visible music entries.
  final List<Entry> entries;
  final void Function(Entry entry) onOpenEntry;
  final void Function(ArtistSummary artist) onOpenArtist;

  /// The home's scroll controller and header: the tabs go under the header and
  /// scroll away with it, the count line pins at the top (Library › Home).
  final ScrollController? controller;
  final List<Widget> leadingSlivers;

  @override
  ConsumerState<MusicTypeBody> createState() => _MusicTypeBodyState();
}

class _MusicTypeBodyState extends ConsumerState<MusicTypeBody> {
  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeMusicTabProvider);
    final theme = Theme.of(context);
    final color = LibraryColors.of(context).music;
    final prefs = ref.watch(displayPreferencesProvider);
    final view = prefs.viewForMusic(tab);
    final artists = artistIndex(widget.entries);
    final albums = widget.entries
        .where((e) => e.kind != MusicKind.song)
        .toList();
    final songs = widget.entries
        .where((e) => e.kind == MusicKind.song)
        .toList();

    final tabs = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: SegmentedControl<MusicTab>(
          segments: [
            for (final t in MusicTab.values) SegmentOption(t, t.label),
          ],
          selected: tab,
          onChanged: ref.read(homeMusicTabProvider.notifier).set,
        ),
      ),
    );
    final countExtent = countRowExtent(MediaQuery.textScalerOf(context));
    final count = PinnedSliver(
      height: countExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 10, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                musicCountLabel(
                  artists: artists.length,
                  albums: albums.length,
                  songs: songs.length,
                ),
                style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
              ),
            ),
            ViewMenuButton(
              current: view,
              photos: tab != MusicTab.albums,
              onChanged: (v) => ref
                  .read(displayPreferencesProvider.notifier)
                  .setMusicView(tab, v),
            ),
          ],
        ),
      ),
    );
    final leading = [...widget.leadingSlivers, tabs, count];
    final pinned = countExtent;

    return switch (tab) {
      MusicTab.artists => ArtistList(
        key: const ValueKey(MusicTab.artists),
        artists: artists,
        view: view,
        color: color,
        onTap: widget.onOpenArtist,
        controller: widget.controller,
        leadingSlivers: leading,
        pinnedExtent: pinned,
      ),
      MusicTab.albums => EntryListBody(
        key: const ValueKey(MusicTab.albums),
        entries: sortEntries(albums, LibrarySort.titleAz),
        sort: LibrarySort.titleAz,
        view: view,
        color: color,
        caption: (e) => e.creator ?? '',
        onTap: widget.onOpenEntry,
        controller: widget.controller,
        leadingSlivers: leading,
        pinnedExtent: pinned,
      ),
      MusicTab.songs => SongList(
        key: const ValueKey(MusicTab.songs),
        items: songItems(songs, albums),
        view: view,
        color: color,
        onTap: widget.onOpenEntry,
        controller: widget.controller,
        leadingSlivers: leading,
        pinnedExtent: pinned,
      ),
    };
  }
}

/// The artists in the chosen view, with letter sections and the alphabet
/// rail when the list is long (Library › Long list: music artists A–Z).
class ArtistList extends StatelessWidget {
  const ArtistList({
    super.key,
    required this.artists,
    required this.view,
    required this.color,
    required this.onTap,
    this.controller,
    this.leadingSlivers = const [],
    this.pinnedExtent = 0,
  });

  final List<ArtistSummary> artists;
  final EntryView view;
  final Color color;
  final void Function(ArtistSummary artist) onTap;
  final ScrollController? controller;
  final List<Widget> leadingSlivers;
  final double pinnedExtent;

  @override
  Widget build(BuildContext context) {
    final grid = view == EntryView.grid;
    final photo = view == EntryView.listWithPhotos;
    Widget row(ArtistSummary artist) =>
        ArtistRow(artist: artist, photo: photo, onTap: () => onTap(artist));
    return SectionedListBody<ArtistSummary>(
      itemCount: artists.length,
      sections: artistSections(artists),
      grid: grid,
      rowExtent: ArtistRow.extent(
        photo: photo,
        scaler: MediaQuery.textScalerOf(context),
      ),
      gridRowExtent: (width) =>
          ArtistGridTile.extent(EntryListMetrics.gridTileWidth(width)) +
          EntryListMetrics.gridMainSpacing,
      gridTopPadding: EntryListMetrics.gridTopPadding,
      gridColumns: EntryListMetrics.gridColumns,
      color: color,
      controller: controller,
      leadingSlivers: leadingSlivers,
      pinnedExtent: pinnedExtent,
      layoutKey: (view, artists.length),
      rowBuilder: (context, artist) => row(artist),
      flatSlivers: grid
          ? [
              SliverPadding(
                padding: const EdgeInsets.only(
                  top: EntryListMetrics.gridTopPadding,
                ),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: EntryListMetrics.gridColumns,
                      crossAxisSpacing: EntryListMetrics.gridCrossSpacing,
                      mainAxisSpacing: EntryListMetrics.gridMainSpacing,
                      mainAxisExtent: ArtistGridTile.extent(
                        EntryListMetrics.gridTileWidth(
                          constraints.crossAxisExtent,
                        ),
                      ),
                    ),
                    itemCount: artists.length,
                    itemBuilder: (context, i) => ArtistGridTile(
                      artist: artists[i],
                      onTap: () => onTap(artists[i]),
                    ),
                  ),
                ),
              ),
            ]
          : [
              SliverList.builder(
                itemCount: artists.length,
                itemBuilder: (context, i) => row(artists[i]),
              ),
            ],
    );
  }
}

/// One row of the Songs tab: a song entry, or a rated track on an album.
class SongItem {
  const SongItem.entry(this.entry) : track = null;
  const SongItem.track(this.entry, Track this.track);

  /// The song entry, or the album the track is on.
  final Entry entry;
  final Track? track;

  String get title => track?.title ?? entry.title;
}

/// Song entries and the rated tracks of [albums], in title order.
List<SongItem> songItems(List<Entry> songs, List<Entry> albums) {
  final items = [
    for (final song in songs) SongItem.entry(song),
    for (final album in albums)
      for (final track in album.tracks ?? const <Track>[])
        SongItem.track(album, track),
  ];
  items.sort((a, b) {
    final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return c != 0 ? c : a.entry.title.compareTo(b.entry.title);
  });
  return items;
}

class SongList extends StatelessWidget {
  const SongList({
    super.key,
    required this.items,
    required this.view,
    required this.color,
    required this.onTap,
    this.controller,
    this.leadingSlivers = const [],
    this.pinnedExtent = 0,
  });

  final List<SongItem> items;
  final EntryView view;
  final Color color;
  final void Function(Entry entry) onTap;
  final ScrollController? controller;
  final List<Widget> leadingSlivers;
  final double pinnedExtent;

  @override
  Widget build(BuildContext context) {
    final grid = view == EntryView.grid;
    final photo = view == EntryView.listWithPhotos;
    Widget row(SongItem item) {
      final leading = photo ? CoverImage(entry: item.entry, width: 40) : null;
      final track = item.track;
      if (track == null) {
        return EntryRow.forEntry(
          item.entry,
          leading: leading,
          subtitle: songSubtitle(item.entry),
          onTap: () => onTap(item.entry),
        );
      }
      return TrackRow(
        title: track.title,
        // The album's artist and year: one format with the song entries.
        subtitle: songSubtitle(item.entry),
        rating: track.rating,
        leading: leading,
        onTap: () => onTap(item.entry),
      );
    }

    return SectionedListBody<SongItem>(
      itemCount: items.length,
      sections: sectionsByTitle(items, (i) => i.title),
      grid: grid,
      rowExtent: EntryListMetrics.rowHeight(
        view,
        MediaQuery.textScalerOf(context),
      ),
      gridRowExtent: (width) =>
          EntryListMetrics.gridRowExtent(width, items.first.entry.type),
      gridTopPadding: EntryListMetrics.gridTopPadding,
      gridColumns: EntryListMetrics.gridColumns,
      color: color,
      controller: controller,
      leadingSlivers: leadingSlivers,
      pinnedExtent: pinnedExtent,
      layoutKey: (view, items.length),
      rowBuilder: (context, item) => row(item),
      flatSlivers: grid
          ? [
              SliverPadding(
                padding: const EdgeInsets.only(
                  top: EntryListMetrics.gridTopPadding,
                ),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: EntryListMetrics.gridColumns,
                      crossAxisSpacing: EntryListMetrics.gridCrossSpacing,
                      mainAxisSpacing: EntryListMetrics.gridMainSpacing,
                      mainAxisExtent: EntryListMetrics.gridTileExtent(
                        constraints.crossAxisExtent,
                        items.first.entry.type,
                      ),
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return CoverGridTile(
                        entry: item.entry,
                        title: item.track?.title,
                        caption: item.track == null
                            ? item.entry.creator ?? ''
                            : item.entry.title,
                        onTap: () => onTap(item.entry),
                      );
                    },
                  ),
                ),
              ),
            ]
          : [
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => row(items[i]),
              ),
            ],
    );
  }
}

/// A rated track in the Songs tab: title, "Artist · Album" and its rating
/// where an entry row has its status mark. Opens the album.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rating,
    required this.onTap,
    this.leading,
  });

  final String title;
  final String subtitle;
  final int rating;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              ratingLabel(rating),
              style: theme.textTheme.labelMedium!.copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
