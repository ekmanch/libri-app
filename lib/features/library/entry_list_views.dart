import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../widgets/entry_row.dart';
import '../settings/entry_view.dart';
import 'cover_grid.dart';
import 'cover_grid_tile.dart';
import 'larger_cover.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/cover_placeholder.dart';
import 'sectioned_list_body.dart';
import 'series_groups.dart';
import 'series_row.dart';

/// Row heights and grid metrics, shared with the jump rail so that section
/// offsets can be computed without laying the list out.
abstract final class EntryListMetrics {
  static const textRowHeight = 56.0;
  static const coverRowHeight = 76.0;
  static const headerHeight = SectionedListBody.headerHeight;
  static const gridColumns = 3;
  static const gridCrossSpacing = 12.0;
  static const gridMainSpacing = 16.0;
  static const gridTopPadding = 10.0;

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

  /// What the grid's row heights follow from, for [titles] under covers
  /// of [type]'s shape.
  static CoverGridSpec gridSpec(
    BuildContext context, {
    required List<String> titles,
    required MediaType type,
  }) => CoverGridSpec(
    titles: titles,
    text: GridTileText.of(context),
    coverAspectRatio: CoverPlaceholder.aspectRatio(type),
    columns: gridColumns,
    crossSpacing: gridCrossSpacing,
    mainSpacing: gridMainSpacing,
  );
}

/// The home's pinned count row (Library › Home): [top] above a 48 dp button
/// row, grown with the text size. A pinned sliver needs a fixed height. Under
/// the status chips [top] is 0: their 48 dp row already leaves 8 below the
/// chip.
double countRowExtent(TextScaler scaler, {double top = 8}) =>
    top + 48 + EntryListMetrics.textGrowth(scaler);

/// The slivers for a list of rows in the chosen view: text rows, rows with
/// covers (Library › Movies, list with covers) or a three-column grid
/// (Library › Movies, grid with covers), which needs its [gridSpec]. A
/// series grouped as one row gets [SeriesGroupRow] or [SeriesGridTile], and
/// [onTapSeries]. A long press on any of them opens its cover larger
/// (Library › Cover, larger).
List<Widget> entryListSlivers({
  required List<LibraryRow> rows,
  required EntryView view,
  required void Function(Entry entry) onTap,
  void Function(SeriesGroup group)? onTapSeries,
  DateTime? today,
  String Function(Entry entry)? caption,
  CoverGridSpec? gridSpec,
}) {
  Widget row(BuildContext context, LibraryRow item) => entryListRow(
    context,
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
          itemBuilder: (context, i) => row(context, rows[i]),
        ),
      ];
    case EntryView.grid:
      return [
        CoverGridSliver(
          spec: gridSpec!,
          topPadding: EntryListMetrics.gridTopPadding,
          itemBuilder: (context, i) => switch (rows[i]) {
            EntryItem(:final entry) => CoverGridTile(
              entry: entry,
              today: today,
              caption: caption?.call(entry),
              onTap: () => onTap(entry),
              onLongPress: () => showLargerCover(context, entry),
            ),
            final SeriesGroup group => SeriesGridTile(
              group: group,
              onTap: () => onTapSeries?.call(group),
              onLongPress: () => showLargerSeriesCover(context, group),
            ),
          },
        ),
      ];
  }
}

/// The title under [item]'s cover in the grid: the entry's, or the series'.
String gridTitleOf(LibraryRow item) => switch (item) {
  EntryItem(:final entry) => entry.title,
  final SeriesGroup group => group.title,
};

/// One row of the text or list view for [item]: an [EntryRow], or a
/// [SeriesGroupRow] for a grouped series. A long press opens its cover
/// larger.
Widget entryListRow(
  BuildContext context,
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
      onLongPress: () => showLargerCover(context, entry),
      leading: withCover ? CoverImage(entry: entry, width: 40) : null,
    ),
    final SeriesGroup group => SeriesGroupRow(
      group: group,
      withCover: withCover,
      onTap: () => onTapSeries?.call(group),
      onLongPress: () => showLargerSeriesCover(context, group),
    ),
  };
}
