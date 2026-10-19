import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../widgets/entry_row.dart';
import '../settings/entry_view.dart';
import 'cover_grid_tile.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/cover_placeholder.dart';
import 'sectioned_list_body.dart';

/// Row heights and grid metrics, shared with the jump rail so that section
/// offsets can be computed without measuring.
abstract final class EntryListMetrics {
  static const textRowHeight = 56.0;
  static const coverRowHeight = 76.0;
  static const headerHeight = SectionedListBody.headerHeight;
  static const gridColumns = 3;
  static const gridCrossSpacing = 12.0;
  static const gridMainSpacing = 16.0;
  static const gridTopPadding = 10.0;

  /// Text under a grid cover: a gap, two title lines, a gap, one caption
  /// line. The line heights are fixed in [CoverGridTile], so this does not
  /// depend on font metrics or the device's text scale.
  static const gridCaptionHeight =
      6 +
      CoverGridTile.titleLineHeight * CoverGridTile.titleLines +
      1 +
      CoverGridTile.captionLineHeight;

  /// The fixed extent of one row in a long list. A row grows with the
  /// user's text size (title plus subtitle, about 36 px of scaled text), so
  /// it never overflows at text scale 1.3.
  static double rowHeight(EntryView view, [TextScaler? scaler]) {
    final base = view == EntryView.listWithPhotos
        ? coverRowHeight
        : textRowHeight;
    return base + textGrowth(scaler);
  }

  /// Extra height a row needs at the user's text size.
  static double textGrowth(TextScaler? scaler) =>
      scaler == null ? 0 : math.max(0.0, scaler.scale(36) - 36);

  static double gridTileWidth(double width) =>
      (width - gridCrossSpacing * (gridColumns - 1)) / gridColumns;

  /// Exact height of one grid tile for a list of [width].
  static double gridTileExtent(double width, MediaType type) =>
      gridTileWidth(width) / CoverPlaceholder.aspectRatio(type) +
      gridCaptionHeight;

  /// Height of one grid row (tile plus spacing) for a list of [width].
  static double gridRowExtent(double width, MediaType type) =>
      gridTileExtent(width, type) + gridMainSpacing;
}

/// The home's pinned count row (Library › Home): 8 above a 48 dp button row,
/// grown with the text size. A pinned sliver needs a fixed height.
double countRowExtent(TextScaler scaler) =>
    8 + 48 + EntryListMetrics.textGrowth(scaler);

/// The slivers for a list of entries in the chosen view: text rows, rows with
/// covers (Library › Movies, list with covers) or a three-column grid
/// (Library › Movies, grid with covers).
List<Widget> entryListSlivers({
  required List<Entry> entries,
  required EntryView view,
  required void Function(Entry entry) onTap,
  DateTime? today,
  String Function(Entry entry)? caption,
}) {
  switch (view) {
    case EntryView.text:
      return [
        SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (context, i) => EntryRow.forEntry(
            entries[i],
            today: today,
            onTap: () => onTap(entries[i]),
          ),
        ),
      ];
    case EntryView.listWithPhotos:
      return [
        SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (context, i) => EntryRow.forEntry(
            entries[i],
            today: today,
            onTap: () => onTap(entries[i]),
            leading: CoverImage(entry: entries[i], width: 40),
          ),
        ),
      ];
    case EntryView.grid:
      // One type per list, so one cover shape; mixed lists use the poster.
      final type = entries.isEmpty ? MediaType.movies : entries.first.type;
      return [
        SliverPadding(
          padding: const EdgeInsets.only(top: EntryListMetrics.gridTopPadding),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: EntryListMetrics.gridColumns,
                crossAxisSpacing: EntryListMetrics.gridCrossSpacing,
                mainAxisSpacing: EntryListMetrics.gridMainSpacing,
                mainAxisExtent: EntryListMetrics.gridTileExtent(
                  constraints.crossAxisExtent,
                  type,
                ),
              ),
              itemCount: entries.length,
              itemBuilder: (context, i) => CoverGridTile(
                entry: entries[i],
                today: today,
                caption: caption?.call(entries[i]),
                onTap: () => onTap(entries[i]),
              ),
            ),
          ),
        ),
      ];
  }
}
