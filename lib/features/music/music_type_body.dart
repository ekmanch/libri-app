import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_kind.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/pinned_sliver.dart';
import '../../widgets/chips.dart';
import '../library/cover_grid_tile.dart';
import '../../widgets/cover_image.dart';
import '../library/entry_list_body.dart';
import '../library/entry_list_views.dart';
import '../library/entry_sections.dart';
import '../library/home_type_provider.dart';
import '../library/library_sort.dart';
import '../library/sectioned_list_body.dart';
import '../library/sort_sheet.dart';
import '../library/view_menu.dart';
import '../settings/display_preferences.dart';
import '../settings/entry_view.dart';
import 'artist_index.dart';
import 'artist_tiles.dart';
import 'music_tab.dart';

/// The music list with Music picked on the home (Library › Music: artists, text
/// view; Music: artists, list with photos; Music: artists, grid with photos):
/// an Artists / Albums / Songs toggle instead of status segments, a count of
/// the tab shown, and a sort and a view button whose choices are kept per tab
/// (Music: sort menu, artists; Music: sort menu, albums and songs). The Songs
/// tab lists song entries only, not the songs rated on albums.
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
    final artistsSort = prefs.musicArtistsSort;
    final artists = artistIndex(widget.entries, sort: artistsSort);
    final albums = widget.entries
        .where((e) => e.kind != EntryKind.song)
        .toList();
    final songs = widget.entries
        .where((e) => e.kind == EntryKind.song)
        .toList();
    final notifier = ref.read(displayPreferencesProvider.notifier);
    final sort = prefs.sortForMusic(tab);

    final tabs = SliverToBoxAdapter(
      child: Padding(
        // As the status chips of the other types (home_pages.dart).
        padding: const EdgeInsets.only(top: 4),
        child: ChoiceChips<MusicTab>(
          options: [
            for (final t in MusicTab.values) ChoiceChipOption(t, t.label),
          ],
          selected: tab,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          onChanged: ref.read(homeMusicTabProvider.notifier).set,
        ),
      ),
    );
    final countExtent = countRowExtent(
      MediaQuery.textScalerOf(context),
      top: 0,
    );
    final count = PinnedSliver(
      height: countExtent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
        child: Row(
          children: [
            Text(
              musicCountLabel(tab, switch (tab) {
                MusicTab.artists => artists.length,
                MusicTab.albums => albums.length,
                MusicTab.songs => songs.length,
              }),
              style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
            ),
            // The count is short; a long sort label cuts off before it
            // pushes the view button out.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: tab == MusicTab.artists
                    ? SortButton<ArtistsSort>(
                        current: artistsSort,
                        options: ArtistsSort.values,
                        onChanged: notifier.setMusicArtistsSort,
                      )
                    : SortButton<LibrarySort>(
                        current: sort,
                        options: LibrarySort.values,
                        onChanged: (s) => notifier.setMusicSort(tab, s),
                      ),
              ),
            ),
            ViewMenuButton(
              current: view,
              photos: tab != MusicTab.albums,
              onChanged: (v) => notifier.setMusicView(tab, v),
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
        sectioned: artistsSort == ArtistsSort.nameAz,
        view: view,
        color: color,
        onTap: widget.onOpenArtist,
        controller: widget.controller,
        leadingSlivers: leading,
        pinnedExtent: pinned,
      ),
      MusicTab.albums => EntryListBody(
        key: const ValueKey(MusicTab.albums),
        entries: sortEntries(albums, sort),
        sort: sort,
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
        songs: sortEntries(songs, sort),
        sort: sort,
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

/// The artists in the chosen view. By name they have letter sections and the
/// alphabet rail when the list is long (Library › Long list: music artists
/// A–Z); the other orders are one list with no headings and no rail.
class ArtistList extends StatelessWidget {
  const ArtistList({
    super.key,
    required this.artists,
    this.sectioned = true,
    required this.view,
    required this.color,
    required this.onTap,
    this.controller,
    this.leadingSlivers = const [],
    this.pinnedExtent = 0,
  });

  /// In the order to show.
  final List<ArtistSummary> artists;

  /// Whether [artists] are in name order, and so get letter sections.
  final bool sectioned;
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
      sections: sectioned ? artistSections(artists) : const [],
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
      layoutKey: (view, artists.length, sectioned),
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

/// The Songs tab: the song entries only. A song rated on a saved album
/// stays on that album (Music › Album with track ratings) and is not listed.
class SongList extends StatelessWidget {
  const SongList({
    super.key,
    required this.songs,
    this.sort = LibrarySort.titleAz,
    required this.view,
    required this.color,
    required this.onTap,
    this.controller,
    this.leadingSlivers = const [],
    this.pinnedExtent = 0,
  });

  /// Song entries, already sorted by [sort].
  final List<Entry> songs;
  final LibrarySort sort;
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
    Widget row(Entry song) => EntryRow.forEntry(
      song,
      leading: photo ? CoverImage(entry: song, width: 40) : null,
      subtitle: songSubtitle(song),
      onTap: () => onTap(song),
    );

    return SectionedListBody<Entry>(
      itemCount: songs.length,
      sections: sectionEntries(songs, sort),
      grid: grid,
      rowExtent: EntryListMetrics.rowHeight(
        view,
        MediaQuery.textScalerOf(context),
      ),
      gridRowExtent: (width) =>
          EntryListMetrics.gridRowExtent(width, songs.first.type),
      gridTopPadding: EntryListMetrics.gridTopPadding,
      gridColumns: EntryListMetrics.gridColumns,
      color: color,
      controller: controller,
      leadingSlivers: leadingSlivers,
      pinnedExtent: pinnedExtent,
      layoutKey: (view, songs.length, sort),
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
                        songs.first.type,
                      ),
                    ),
                    itemCount: songs.length,
                    itemBuilder: (context, i) => CoverGridTile(
                      entry: songs[i],
                      caption: songs[i].creator ?? '',
                      onTap: () => onTap(songs[i]),
                    ),
                  ),
                ),
              ),
            ]
          : [
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (context, i) => row(songs[i]),
              ),
            ],
    );
  }
}
