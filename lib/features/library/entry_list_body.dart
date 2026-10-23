import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../settings/entry_view.dart';
import '../shell/app_shell.dart';
import 'entry_list_views.dart';
import 'entry_sections.dart';
import 'library_sort.dart';
import 'sectioned_list_body.dart';
import 'series_groups.dart';

/// The scrolling part of a type's list: a [SectionedListBody] of rows whose
/// sections follow the sort (Library › Long list: rail by release year to
/// Filtered results, several types).
///
/// With [groupSeries], a list at least three screens tall (the rail's
/// constant, measured on the single entries) folds the parts of each
/// series in the library into one row (Library › Movies, text view with a
/// series row; the Library › Series page (from a series row) note), tapped
/// through [onTapSeries]. A shorter list, and a list without the flag,
/// shows every entry.
class EntryListBody extends StatelessWidget {
  const EntryListBody({
    super.key,
    required this.entries,
    required this.sort,
    required this.view,
    required this.color,
    required this.onTap,
    this.onTapSeries,
    this.groupSeries = false,
    this.today,
    this.bottomPadding = AppShell.contentBottomPadding,
    this.typeColors,
    this.caption,
    this.controller,
    this.leadingSlivers = const [],
    this.pinnedExtent = 0,
  });

  /// Already sorted by [sort].
  final List<Entry> entries;
  final LibrarySort sort;
  final EntryView view;

  /// The type color, for the section headers.
  final Color color;
  final void Function(Entry entry) onTap;

  /// A series row tapped (Library › Series page (from a series row)).
  final void Function(SeriesGroup group)? onTapSeries;

  /// Whether a long list groups its series.
  final bool groupSeries;
  final DateTime? today;

  /// Space kept clear of the floating navigation; the rail ends above it.
  final double bottomPadding;

  /// Filtered results: sections by type in these colors instead of the
  /// sort's. With one type they show only when the list is long, like the
  /// sort's (Library › Filtered results, one type); with several they
  /// always show, with a dot rail on a long list (Library › Filtered
  /// results, several types).
  final Color Function(MediaType type)? typeColors;

  /// The line under a grid tile's title; the status by default.
  final String Function(Entry entry)? caption;

  /// See [SectionedListBody.controller] and [SectionedListBody.leadingSlivers].
  final ScrollController? controller;
  final List<Widget> leadingSlivers;
  final double pinnedExtent;

  static const thumbKey = SectionedListBody.thumbKey;
  static const railKey = SectionedListBody.railKey;
  static const thumbHeight = SectionedListBody.thumbHeight;

  /// Whether a list of [entries] in [view] is long enough to group its
  /// series, in a viewport [viewportHeight] tall and [width] wide (the
  /// list's own width, inside its margins).
  static bool groupsAt({
    required List<Entry> entries,
    required LibrarySort sort,
    required EntryView view,
    required double width,
    required double viewportHeight,
    required TextScaler scaler,
    DateTime? today,
  }) {
    final grid = view == EntryView.grid;
    final type = entries.isEmpty ? MediaType.movies : entries.first.type;
    final height = SectionedListBody.contentHeightOf(
      itemCount: entries.length,
      sectionCount: grid
          ? 0
          : sectionEntries(entries, sort, today: today).length,
      grid: grid,
      rowExtent: grid
          ? EntryListMetrics.gridRowExtent(width, type)
          : EntryListMetrics.rowHeight(view, scaler),
      gridColumns: EntryListMetrics.gridColumns,
      gridTopPadding: EntryListMetrics.gridTopPadding,
    );
    return isLongList(contentHeight: height, viewportHeight: viewportHeight);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final grouped =
            groupSeries &&
            groupsAt(
              entries: entries,
              sort: sort,
              view: view,
              width: constraints.maxWidth - 40,
              viewportHeight: constraints.maxHeight,
              scaler: scaler,
              today: today,
            );
        final rows = grouped
            ? groupSeriesRows(entries)
            : [for (final e in entries) EntryItem(e)];
        final byType = typeColors == null
            ? null
            : sectionRowsByType(rows, typeColors!);
        final types = {for (final e in entries) e.type};
        // One type per list, so one cover shape; mixed lists use the poster.
        final type = entries.isEmpty ? MediaType.movies : entries.first.type;
        return SectionedListBody<LibraryRow>(
          itemCount: rows.length,
          sections: byType != null && types.length > 1
              ? byType
              : sectionRows(rows, sort, today: today),
          plainSections: byType,
          grid: view == EntryView.grid,
          rowExtent: EntryListMetrics.rowHeight(view, scaler),
          gridRowExtent: (width) => EntryListMetrics.gridRowExtent(width, type),
          gridTopPadding: EntryListMetrics.gridTopPadding,
          gridColumns: EntryListMetrics.gridColumns,
          color: color,
          bottomPadding: bottomPadding,
          controller: controller,
          leadingSlivers: leadingSlivers,
          pinnedExtent: pinnedExtent,
          layoutKey: (sort, view, entries, grouped),
          rowBuilder: (context, row) => entryListRow(
            row,
            view: view,
            onTap: onTap,
            onTapSeries: onTapSeries,
            today: today,
          ),
          flatSlivers: entryListSlivers(
            rows: rows,
            view: view,
            onTap: onTap,
            onTapSeries: onTapSeries,
            today: today,
            caption: caption,
          ),
        );
      },
    );
  }
}
