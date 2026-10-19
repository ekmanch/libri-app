import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../widgets/entry_row.dart';
import '../settings/entry_view.dart';
import '../shell/app_shell.dart';
import '../../widgets/cover_image.dart';
import 'entry_list_views.dart';
import 'entry_sections.dart';
import 'library_sort.dart';
import 'sectioned_list_body.dart';

/// The scrolling part of a type's list: a [SectionedListBody] of entries whose
/// sections follow the sort (Library › Long list: rail by release year to
/// Filtered results, several types).
class EntryListBody extends StatelessWidget {
  const EntryListBody({
    super.key,
    required this.entries,
    required this.sort,
    required this.view,
    required this.color,
    required this.onTap,
    this.today,
    this.bottomPadding = AppShell.contentBottomPadding,
    this.railSections,
    this.plainSections,
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
  final DateTime? today;

  /// Space kept clear of the floating navigation; the rail ends above it.
  final double bottomPadding;

  /// The sections behind the rail. By default they follow [sort]; filtered
  /// results with several types pass one section per type (Library › Filtered
  /// results, several types).
  final List<EntrySection>? railSections;

  /// Sections to show with headers when the list is too short for a rail
  /// (filtered results by type: Library › Filtered results, several types).
  /// Null means a flat list.
  final List<EntrySection>? plainSections;

  /// The line under a grid tile's title; the status by default.
  final String Function(Entry entry)? caption;

  /// See [SectionedListBody.controller] and [SectionedListBody.leadingSlivers].
  final ScrollController? controller;
  final List<Widget> leadingSlivers;
  final double pinnedExtent;

  static const thumbKey = SectionedListBody.thumbKey;
  static const railKey = SectionedListBody.railKey;
  static const thumbHeight = SectionedListBody.thumbHeight;

  @override
  Widget build(BuildContext context) {
    // One type per list, so one cover shape; mixed lists use the poster.
    final type = entries.isEmpty ? MediaType.movies : entries.first.type;
    return SectionedListBody<Entry>(
      itemCount: entries.length,
      sections: railSections ?? sectionEntries(entries, sort, today: today),
      plainSections: plainSections,
      grid: view == EntryView.grid,
      rowExtent: EntryListMetrics.rowHeight(
        view,
        MediaQuery.textScalerOf(context),
      ),
      gridRowExtent: (width) => EntryListMetrics.gridRowExtent(width, type),
      gridTopPadding: EntryListMetrics.gridTopPadding,
      gridColumns: EntryListMetrics.gridColumns,
      color: color,
      bottomPadding: bottomPadding,
      controller: controller,
      leadingSlivers: leadingSlivers,
      pinnedExtent: pinnedExtent,
      layoutKey: (sort, view, entries),
      rowBuilder: (context, entry) => EntryRow.forEntry(
        entry,
        today: today,
        onTap: () => onTap(entry),
        leading: view == EntryView.listWithPhotos
            ? CoverImage(entry: entry, width: 40)
            : null,
      ),
      flatSlivers: entryListSlivers(
        entries: entries,
        view: view,
        onTap: onTap,
        today: today,
        caption: caption,
      ),
    );
  }
}
