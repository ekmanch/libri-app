import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/artist_photo.dart';
import '../../widgets/cover_image.dart';
import '../library/library_filter.dart';
import '../library/library_filter_provider.dart';
import '../library/library_sort.dart';
import '../library/sort_sheet.dart';
import '../settings/display_preferences.dart';
import '../settings/entry_view.dart';
import '../shell/app_shell.dart';
import 'artist_index.dart';
import 'artist_photo_sheet.dart';
import 'music_tab.dart';

/// Opens one artist (Music › Artist, text view; Artist, with photos) inside the
/// Library tab, so the floating navigation stays.
Future<void> openArtistScreen(
  BuildContext context,
  ArtistSummary artist, {
  void Function(Entry entry)? onOpenEntry,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ArtistScreen(name: artist.name, onOpenEntry: onOpenEntry),
    ),
  );
}

/// One artist: an Albums section, then a Songs section (Music › Artist, text
/// view). With a photo view chosen for the Artists tab the rows show covers
/// (Music › Artist, with photos). The order comes from the sort link and is
/// kept on the device.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.name, this.onOpenEntry});

  final String name;
  final void Function(Entry entry)? onOpenEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final prefs = ref.watch(displayPreferencesProvider);
    final includeSeasonal = ref
        .watch(libraryFilterProvider)
        .includeSeasonalOnly;
    final library = ref.watch(libraryProvider).value;
    final visible = library == null
        ? const <Entry>[]
        : LibraryFilter(includeSeasonalOnly: includeSeasonal)
              .apply(library.entriesOfType(MediaType.music));
    final artist = artistIndex(visible)
        .where((a) => a.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    final photo = prefs.viewForMusic(MusicTab.artists) != EntryView.text;

    Widget row(Entry entry, {required bool album}) => EntryRow(
      title: entry.title,
      subtitle: album ? yearSubtitle(entry) : entrySubtitle(entry),
      status: entry.status,
      leading: photo ? CoverImage(entry: entry, width: 44) : null,
      onTap: () => onOpenEntry?.call(entry),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: artist?.name ?? name,
              onBack: () => Navigator.pop(context),
              // On light a page heading gets no dot (the Library "Type
              // colors" note).
              leading: colors.typeColorsAreFills
                  ? null
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.music,
                        shape: BoxShape.circle,
                      ),
                    ),
              // A long press on the name, like one on the photo, opens
              // Music › Pick a photo.
              onTitleLongPress: artist == null
                  ? null
                  : () => showArtistPhotoPicker(context, name: artist.name),
            ),
            if (artist == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text(
                  'Nothing saved for this artist any more.',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.muted,
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 10, 0),
                child: Row(
                  children: [
                    // The artist's round photo leads the count line, in the
                    // text view too (Music › Artist, text view; Artist,
                    // with photos). A tap shows it larger
                    // (Music › Artist photo, larger); a long press opens
                    // Music › Pick a photo.
                    Semantics(
                      button: true,
                      label:
                          '${artist.name}. Tap to see the photo, long-press '
                          'to change it',
                      excludeSemantics: true,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            showArtistPhotoViewer(context, name: artist.name),
                        onLongPress: () =>
                            showArtistPhotoPicker(context, name: artist.name),
                        child: ArtistPhoto(
                          name: artist.name,
                          initials: artist.initials,
                          size: 72,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final count = Text(
                            artist.countLabel,
                            style: theme.textTheme.bodySmall!.copyWith(
                              fontSize: 14,
                            ),
                          );
                          final sort = SortButton(
                            current: prefs.artistSort,
                            options: LibrarySort.general,
                            onChanged: (sort) => ref
                                .read(displayPreferencesProvider.notifier)
                                .setArtistSort(sort),
                          );
                          // Beside the photo the two stack, in every
                          // view: side by side they do not fit a narrow
                          // phone at a large text size.
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [count, sort],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    AppShell.contentBottomPadding,
                  ),
                  children: [
                    if (artist.albums.isNotEmpty) ...[
                      SectionHeading(
                        'Albums',
                        trailing: '${artist.albums.length}',
                      ),
                      for (final album in sortEntries(
                        artist.albums,
                        prefs.artistSort,
                      ))
                        row(album, album: true),
                    ],
                    if (artist.songs.isNotEmpty) ...[
                      SectionHeading(
                        'Songs',
                        trailing: '${artist.songs.length}',
                      ),
                      for (final song in sortEntries(
                        artist.songs,
                        prefs.artistSort,
                      ))
                        row(song, album: false),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Just the year, or "Not released yet"; for an album under its artist,
/// where repeating the artist would say nothing.
String yearSubtitle(Entry entry, {DateTime? today}) {
  final released = entry.released;
  if (released == null) return '';
  if (!released.isReleasedOn(today ?? DateTime.now())) {
    return 'Not released yet';
  }
  return '${released.year}';
}
