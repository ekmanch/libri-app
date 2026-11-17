import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/artist_photo_fetcher.dart';
import '../../data/covers/cover_files.dart';
import '../../data/library_providers.dart';
import '../../data/models/library.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/artist_photo.dart';
import '../../widgets/page_header.dart';
import '../music/artist_index.dart';
import '../music/artist_photo_sheet.dart';

/// The artists of [library] with no file of their own among [files] (the
/// artists' photos by slug), A to Z: everyone who can have a photo and has
/// none, whether they show a library cover as a stand-in or their
/// initials.
List<ArtistSummary> artistsWithoutPhoto(
  Library library,
  Map<String, CoverFile> files,
) {
  final without = {
    for (final artist in photoArtists(library))
      if (!files.containsKey(artist.slug)) artist.name.toLowerCase(),
  };
  return [
    for (final artist in artistIndex(library.entries))
      if (without.contains(artist.name.toLowerCase())) artist,
  ];
}

/// "63 artists. No photo was found for these; pick or upload one."
String artistsWithoutPhotoIntro(int count) => switch (count) {
  0 => 'Every artist has a photo.',
  1 => '1 artist. No photo was found for this one; pick or upload one.',
  _ => '$count artists. No photo was found for these; pick or upload one.',
};

void openArtistsWithoutPhotoScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ArtistsWithoutPhotoScreen()),
  );
}

/// Settings › Artists without a photo ("Without a photo"): every artist
/// with no file of their own, A to Z, each with the circle they show today
/// (a library cover or initials), the name, what is saved by them and "Add
/// photo ›". A tap opens Music › Pick a photo for that artist; once a
/// photo is picked or uploaded the artist leaves the list. The quick way
/// to the artists that never match on their own (DESIGN.md section 10e).
class ArtistsWithoutPhotoScreen extends ConsumerWidget {
  const ArtistsWithoutPhotoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final library = ref.watch(libraryProvider).value;
    final files = ref.watch(artistPhotoFilesProvider);
    final artists = library == null
        ? const <ArtistSummary>[]
        : artistsWithoutPhoto(library, files);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Without a photo',
              onBack: () => Navigator.pop(context),
            ),
            if (library != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  artistsWithoutPhotoIntro(artists.length),
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    fontSize: 14.5,
                    height: 1.45,
                    color: colors.muted,
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                itemCount: artists.length,
                itemBuilder: (context, i) => _ArtistRow(
                  key: ValueKey(artists[i].name.toLowerCase()),
                  artist: artists[i],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({super.key, required this.artist});

  final ArtistSummary artist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final accent = theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: '${artist.name}, ${artist.countLabel}, add a photo',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showArtistPhotoPicker(context, name: artist.name),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              ArtistPhoto(
                name: artist.name,
                initials: artist.initials,
                size: 48,
                initialsSize: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge!.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist.countLabel,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontStyle: FontStyle.normal,
                        fontSize: 13.5,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Add photo',
                style: theme.textTheme.labelLarge!.copyWith(
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
