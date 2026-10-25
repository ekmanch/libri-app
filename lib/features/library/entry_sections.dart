import 'dart:ui' show Color;

import '../../data/models/entry.dart';
import '../../data/models/entry_id.dart';
import '../../data/models/media_type.dart';
import '../../widgets/labels.dart';
import 'library_filter.dart';
import 'library_sort.dart';
import 'sectioned_list_body.dart';
import 'series_groups.dart';

/// A section of entries; see [ListSection].
class EntrySection extends ListSection<Entry> {
  const EntrySection({
    required super.label,
    required super.railLabel,
    required super.bubbleLabel,
    required List<Entry> entries,
    super.uppercaseHeader,
    super.color,
    super.dotColor,
  }) : super(items: entries);

  List<Entry> get entries => items;
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Groups an already sorted list into sections that follow the sort: decades
/// for the year orders (with "Older" before 1960 and a last section for
/// entries without a date), months of the current year and then whole years
/// for newest added, first letters for title order with "#" for digits, and
/// the ratings that exist (10 down to 1, then Unrated) for the rating order.
List<EntrySection> sectionEntries(
  List<Entry> sorted,
  LibrarySort sort, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final sections = <EntrySection>[];
  EntrySection? open;
  for (final entry in sorted) {
    final key = _keyOf(entry, sort, now);
    if (open == null || open.label != key.label) {
      open = EntrySection(
        label: key.label,
        railLabel: key.railLabel,
        bubbleLabel: key.bubbleLabel,
        entries: [],
        uppercaseHeader: key.uppercaseHeader,
      );
      sections.add(open);
    }
    open.entries.add(entry);
  }
  return sections;
}

EntrySection _keyOf(Entry entry, LibrarySort sort, DateTime now) {
  switch (sort) {
    case LibrarySort.newestAdded:
      final added = entry.added;
      if (added.year == now.year) {
        final month = _months[added.month - 1];
        return EntrySection(
          label: '$month ${added.year}',
          railLabel: month.substring(0, 3),
          bubbleLabel: '${month.substring(0, 3)} ${added.year}',
          entries: const [],
        );
      }
      final year = '${added.year}';
      return EntrySection(
        label: year,
        railLabel: year,
        bubbleLabel: year,
        entries: const [],
      );
    case LibrarySort.yearNewest:
    case LibrarySort.yearOldest:
      final decade = Decade.of(entry.year);
      if (decade == null) {
        return const EntrySection(
          label: 'Not released yet',
          railLabel: 'TBA',
          bubbleLabel: 'Not released yet',
          entries: [],
        );
      }
      return EntrySection(
        label: decade.label,
        railLabel: decade.isOlder
            ? 'Older'
            : '${(decade.start! % 100).toString().padLeft(2, '0')}s',
        bubbleLabel: decade.label,
        entries: const [],
        uppercaseHeader: decade.isOlder,
      );
    case LibrarySort.titleAz:
      final letter = titleLetter(entry.title);
      return EntrySection(
        label: letter,
        railLabel: letter,
        bubbleLabel: letter,
        entries: const [],
      );
    case LibrarySort.ratingHighest:
      final rating = entry.rating;
      if (rating == null) {
        // The rail is 36 dp wide, too narrow for "Unrated" at its size.
        return const EntrySection(
          label: 'Unrated',
          railLabel: 'None',
          bubbleLabel: 'Unrated',
          entries: [],
        );
      }
      return EntrySection(
        label: '$rating / 10',
        railLabel: '$rating',
        bubbleLabel: '$rating / 10',
        entries: const [],
      );
  }
}

/// Library › Long list: rail by release year to Long grid: fast-scroll thumb:
/// the jump rail (with its section headers) or the grid's fast-scroll thumb
/// appears only when the list is at least three screens tall ([isLongList])
/// and has two sections or more.
bool showJumpRail({
  required int sectionCount,
  required double contentHeight,
  required double viewportHeight,
}) =>
    sectionCount >= 2 &&
    isLongList(contentHeight: contentHeight, viewportHeight: viewportHeight);

/// [sectionEntries] for a list of rows (entries and grouped series): a
/// series row sits in the section its first-sorting part would, except
/// under Title, A to Z, where it sits under its name's letter.
List<ListSection<LibraryRow>> sectionRows(
  List<LibraryRow> rows,
  LibrarySort sort, {
  DateTime? today,
}) => sort == LibrarySort.titleAz
    ? sectionsByTitle(rows, (r) => r.sortTitle)
    : _rowSections(
        rows,
        sectionEntries([for (final r in rows) r.lead], sort, today: today),
      );

/// [sectionEntriesByType] for a list of rows.
List<ListSection<LibraryRow>> sectionRowsByType(
  List<LibraryRow> rows,
  Color Function(MediaType type) colorOf,
) => _rowSections(
  rows,
  sectionEntriesByType([for (final r in rows) r.lead], colorOf),
);

/// The sections of the rows' lead entries, with the rows put back in.
List<ListSection<LibraryRow>> _rowSections(
  List<LibraryRow> rows,
  List<EntrySection> sections,
) {
  final byLead = {for (final row in rows) row.lead.id: row};
  return [
    for (final s in sections)
      ListSection<LibraryRow>(
        label: s.label,
        railLabel: s.railLabel,
        bubbleLabel: s.bubbleLabel,
        items: [for (final e in s.entries) byLead[e.id]!],
        uppercaseHeader: s.uppercaseHeader,
        color: s.color,
        dotColor: s.dotColor,
      ),
  ];
}

/// Filtered results with several types (Library › Filtered results, several
/// types): one section per type, in type order, each with its color for the
/// header and the rail dot.
List<EntrySection> sectionEntriesByType(
  List<Entry> sorted,
  Color Function(MediaType type) colorOf,
) {
  return [
    for (final type in MediaType.values)
      if (sorted.any((e) => e.type == type))
        EntrySection(
          label: type.label,
          railLabel: type.label,
          bubbleLabel: type.label,
          entries: sorted.where((e) => e.type == type).toList(),
          color: colorOf(type),
          dotColor: colorOf(type),
        ),
  ];
}

/// Sections by first letter of [titleOf], "#" for anything else, for an
/// already title-sorted list. Used where the items are not all entries,
/// like the Songs tab with its rated tracks.
List<ListSection<T>> sectionsByTitle<T>(
  List<T> sorted,
  String Function(T item) titleOf,
) {
  final sections = <ListSection<T>>[];
  ListSection<T>? open;
  for (final item in sorted) {
    final letter = titleLetter(titleOf(item));
    if (open == null || open.label != letter) {
      open = ListSection<T>(
        label: letter,
        railLabel: letter,
        bubbleLabel: letter,
        items: [],
      );
      sections.add(open);
    }
    open.items.add(item);
  }
  return sections;
}

/// "A" to "Z" for a title that starts with a letter once folded to ASCII,
/// otherwise "#".
String titleLetter(String title) {
  final slug = slugify(title);
  final first = slug.isEmpty ? '' : slug[0];
  return RegExp('[a-z]').hasMatch(first) ? first.toUpperCase() : '#';
}
