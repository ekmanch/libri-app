import 'package:flutter/material.dart';

import '../library/cover_grid_tile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artist_photo.dart';
import '../../widgets/row_ink_well.dart';
import '../library/entry_list_views.dart';
import 'artist_index.dart';

/// One artist in the text or list view (Library › Music: artists, text view;
/// Music: artists, list with photos): name and what is saved, "7 albums, 2
/// songs". A text row is 48 dp with the count on the right; with [photo] the
/// row is 64 dp, a 48 dp photo, and the count under the name.
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
      excludeSemantics: true,
      child: RowInkWell(
        onTap: onTap,
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
/// round photo, name, count.
class ArtistGridTile extends StatelessWidget {
  const ArtistGridTile({super.key, required this.artist, required this.onTap});

  final ArtistSummary artist;
  final VoidCallback onTap;

  /// Exact height of a tile of [width]: the disc plus two fixed text lines.
  static double extent(double width) =>
      width +
      6 +
      CoverGridTile.titleLineHeight +
      1 +
      CoverGridTile.captionLineHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${artist.name}, ${artist.countLabel}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ArtistPhoto(
                name: artist.name,
                initials: artist.initials,
                size: constraints.maxWidth,
                initialsSize: 22,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: CoverGridTile.titleLineHeight,
                child: Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: theme.textTheme.labelMedium!.copyWith(
                    fontSize: CoverGridTile.titleFontSize,
                    height:
                        CoverGridTile.titleLineHeight /
                        CoverGridTile.titleFontSize,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: CoverGridTile.captionLineHeight,
                child: Text(
                  artist.countLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontSize: CoverGridTile.captionFontSize,
                    height:
                        CoverGridTile.captionLineHeight /
                        CoverGridTile.captionFontSize,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
