import 'package:flutter/material.dart';

import '../library/cover_grid.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artist_photo.dart';
import '../../widgets/row_ink_well.dart';
import '../library/entry_list_views.dart';
import 'artist_index.dart';
import 'artist_photo_sheet.dart';

/// One artist in the text or list view (Library › Music: artists, text view;
/// Music: artists, list with photos): name and what is saved, "7 albums, 2
/// songs". A text row is 48 dp with the count on the right; with [photo] the
/// row is 64 dp, a 48 dp photo, and the count under the name. A long press
/// opens Music › Pick a photo, in every view.
class ArtistRow extends StatelessWidget {
  const ArtistRow({
    super.key,
    required this.artist,
    required this.onTap,
    this.photo = false,
  });

  final ArtistSummary artist;
  final VoidCallback onTap;
  final bool photo;

  static const textHeight = 48.0;
  static const photoHeight = 64.0;

  /// The fixed extent of a row in the long list, grown for the text size.
  static double extent({required bool photo, TextScaler? scaler}) =>
      (photo ? photoHeight : textHeight) + EntryListMetrics.textGrowth(scaler);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      label: '${artist.name}, ${artist.countLabel}',
      onLongPressHint: 'Change photo',
      excludeSemantics: true,
      child: RowInkWell(
        onTap: onTap,
        onLongPress: () => showArtistPhotoPicker(context, name: artist.name),
        child: Container(
          constraints: BoxConstraints(
            minHeight: photo ? photoHeight : textHeight,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: photo
              ? Row(
                  children: [
                    ArtistPhoto(
                      name: artist.name,
                      initials: artist.initials,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            artist.countLabel,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        artist.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      artist.countLabel,
                      style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One cell of the artist grid (Library › Music: artists, grid with photos):
/// round photo, the name on up to two lines, and the count right under it.
/// The grid measures its rows from the same text ([ArtistGridTile.spec]).
class ArtistGridTile extends StatelessWidget {
  const ArtistGridTile({super.key, required this.artist, required this.onTap});

  final ArtistSummary artist;
  final VoidCallback onTap;

  /// What the row heights of a grid of [artists] follow from.
  static CoverGridSpec spec(
    BuildContext context,
    List<ArtistSummary> artists,
  ) => CoverGridSpec(
    titles: [for (final artist in artists) artist.name],
    text: GridTileText.of(context),
    coverAspectRatio: 1,
    columns: EntryListMetrics.gridColumns,
    crossSpacing: EntryListMetrics.gridCrossSpacing,
    mainSpacing: EntryListMetrics.gridMainSpacing,
  );

  @override
  Widget build(BuildContext context) {
    final text = GridTileText.of(context);
    return Semantics(
      button: true,
      label: '${artist.name}, ${artist.countLabel}',
      onLongPressHint: 'Change photo',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => showArtistPhotoPicker(context, name: artist.name),
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ArtistPhoto(
                name: artist.name,
                initials: artist.initials,
                size: constraints.maxWidth,
                initialsSize: 22,
              ),
              const SizedBox(height: GridTileText.coverGap),
              Text(
                artist.name,
                maxLines: text.titleLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: text.scaler,
                style: text.title,
              ),
              const SizedBox(height: GridTileText.captionGap),
              Text(
                artist.countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: text.scaler,
                style: text.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
