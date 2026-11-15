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

/// The most labels the jump rail holds (the n_rail note). A sort that gives
/// more sections has them merged, far end first, and the list's headings are
/// the same merged sections, so a jump lands on a heading that says what the
/// rail said. Letters, decades and ratings never get that far.
const maxRailLabels = 24;

/// What a section is called in its three places; see [ListSection].
typedef SectionLabels = ({String label, String railLabel, String bubbleLabel});

/// The section of something added on [added]: its month in the current year
/// ("October 2026", "Oct"), its year before that.
SectionLabels addedSectionLabels(DateTime added, DateTime now) {
  if (added.year == now.year) {
    final month = _months[added.month - 1];
    return (
      label: '$month ${added.year}',
      railLabel: month.substring(0, 3),
      bubbleLabel: '${month.substring(0, 3)} ${added.year}',
    );
  }
  final year = '${added.year}';
  return (label: year, railLabel: year, bubbleLabel: year);
}

/// Sections of an already sorted list: a new one wherever [labelsOf] gives
/// another heading.
List<ListSection<T>> sectionsBy<T>(
  List<T> sorted,
  SectionLabels Function(T item) labelsOf,
) {
  final sections = <ListSection<T>>[];
  ListSection<T>? open;
  for (final item in sorted) {
    final labels = labelsOf(item);
    if (open == null || open.label != labels.label) {
      open = ListSection<T>(
        label: labels.label,
        railLabel: labels.railLabel,
        bubbleLabel: labels.bubbleLabel,
        items: [],
      );
      sections.add(open);
    }
    open.items.add(item);
  }
  return sections;
}

/// Month-added sections that fit the rail: when there are more than
/// [maxRailLabels], the oldest years become one last section, "Older". The
/// months of the current year, at most twelve, always stay.
List<S> mergeOldestAdded<T, S extends ListSection<T>>(
  List<S> sections,
  S Function(List<T> items) older,
) {
  if (sections.length <= maxRailLabels) return sections;
  final kept = maxRailLabels - 1;
  return [
    ...sections.take(kept),
    older([for (final s in sections.skip(kept)) ...s.items]),
  ];
}

/// The last section of a merged month-added list.
const olderAddedLabel = 'Older';

/// Groups an already sorted list into sections that follow the sort: decades
/// for the year orders (with "Older" before 1960 and a last section for
/// entries without a date), months of the current year and then whole years
/// for newest added (the oldest years as "Older" when there are more than
/// [maxRailLabels]), first letters for title order with "#" for digits, the
/// artist's letter for artist order, and the ratings that exist (10 down to
/// 1, then Unrated) for the rating order.
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
  if (sort != LibrarySort.newestAdded) return sections;
  return mergeOldestAdded<Entry, EntrySection>(
    sections,
    (entries) => EntrySection(
      label: olderAddedLabel,
      railLabel: olderAddedLabel,
      bubbleLabel: olderAddedLabel,
      entries: entries,
    ),
  );
}

EntrySection _keyOf(Entry entry, LibrarySort sort, DateTime now) {
  switch (sort) {
    case LibrarySort.newestAdded:
      final labels = addedSectionLabels(entry.added, now);
      return EntrySection(
        label: labels.label,
        railLabel: labels.railLabel,
        bubbleLabel: labels.bubbleLabel,
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
    case LibrarySort.artistAz:
      // The artist's letter, as the Artists tab has it; "Various Artists"
      // is its own last section.
      final name = artistNameOf(entry);
      if (isVariousArtists(name)) {
        return const EntrySection(
          label: variousArtistsName,
          railLabel: 'VA',
          bubbleLabel: variousArtistsName,
          entries: [],
        );
      }
      final letter = titleLetter(artistSortKey(name));
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
) => sectionsBy(sorted, (item) {
  final letter = titleLetter(titleOf(item));
  return (label: letter, railLabel: letter, bubbleLabel: letter);
});

/// "A" to "Z" for a title that starts with a letter once folded to ASCII,
/// otherwise "#".
String titleLetter(String title) {
  final slug = slugify(title);
  final first = slug.isEmpty ? '' : slug[0];
  return RegExp('[a-z]').hasMatch(first) ? first.toUpperCase() : '#';
}
