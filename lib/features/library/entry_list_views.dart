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
import 'series_groups.dart';
import 'series_row.dart';

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

/// The slivers for a list of rows in the chosen view: text rows, rows with
/// covers (Library › Movies, list with covers) or a three-column grid
/// (Library › Movies, grid with covers). A series grouped as one row gets
/// [SeriesGroupRow] or [SeriesGridTile], and [onTapSeries].
List<Widget> entryListSlivers({
  required List<LibraryRow> rows,
  required EntryView view,
  required void Function(Entry entry) onTap,
  void Function(SeriesGroup group)? onTapSeries,
  DateTime? today,
  String Function(Entry entry)? caption,
}) {
  Widget row(LibraryRow item) => entryListRow(
    item,
    view: view,
    onTap: onTap,
    onTapSeries: onTapSeries,
    today: today,
  );
  switch (view) {
    case EntryView.text:
    case EntryView.listWithPhotos:
      return [
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) => row(rows[i]),
        ),
      ];
    case EntryView.grid:
      // One type per list, so one cover shape; mixed lists use the poster.
      final type = rows.isEmpty ? MediaType.movies : rows.first.lead.type;
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
              itemCount: rows.length,
              itemBuilder: (context, i) => switch (rows[i]) {
                EntryItem(:final entry) => CoverGridTile(
                  entry: entry,
                  today: today,
                  caption: caption?.call(entry),
                  onTap: () => onTap(entry),
                ),
                final SeriesGroup group => SeriesGridTile(
                  group: group,
                  onTap: () => onTapSeries?.call(group),
                ),
              },
            ),
          ),
        ),
      ];
  }
}

/// One row of the text or list view for [item]: an [EntryRow], or a
/// [SeriesGroupRow] for a grouped series.
Widget entryListRow(
  LibraryRow item, {
  required EntryView view,
  required void Function(Entry entry) onTap,
  void Function(SeriesGroup group)? onTapSeries,
  DateTime? today,
}) {
  final withCover = view == EntryView.listWithPhotos;
  return switch (item) {
    EntryItem(:final entry) => EntryRow.forEntry(
      entry,
      today: today,
      onTap: () => onTap(entry),
      leading: withCover ? CoverImage(entry: entry, width: 40) : null,
    ),
    final SeriesGroup group => SeriesGroupRow(
      group: group,
      withCover: withCover,
      onTap: () => onTapSeries?.call(group),
    ),
  };
}
