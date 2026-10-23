import '../../data/lookup/text_clean.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../entry/series.dart';

/// One row of a type's list (Library › Movies, text view): an entry, or the
/// parts of a series grouped as one row (the Library › Series page (from a
/// series row) note).
sealed class LibraryRow {
  const LibraryRow();

  /// The entry whose place in the sort the row takes.
  Entry get lead;
}

/// A row for one entry.
class EntryItem extends LibraryRow {
  const EntryItem(this.entry);

  final Entry entry;

  @override
  Entry get lead => entry;

  @override
  bool operator ==(Object other) =>
      other is EntryItem && other.entry.id == entry.id;

  @override
  int get hashCode => entry.id.hashCode;
}

/// The parts of a series that are in the library, as one row: named after
/// the series, with one cover and the count, placed where its first-sorting
/// part would be.
class SeriesGroup extends LibraryRow {
  SeriesGroup({required this.name, required this.lead, required this.parts})
    : assert(parts.length >= 2);

  /// The series name as stored.
  final String name;

  /// The part that sorts first, whose place the row takes.
  @override
  final Entry lead;

  /// The parts in series order: by number, parts without one last in
  /// library order.
  final List<Entry> parts;

  MediaType get type => lead.type;

  /// The name as shown: TMDB's "Collection" suffix dropped.
  String get title => seriesDisplayName(name);

  int get count => parts.length;

  /// The part whose cover stands for the series: the one marked `cover`,
  /// else part 1 (the first in series order).
  Entry get coverEntry => seriesCoverEntry(parts);

  int get doneCount => parts.where((p) => p.status == EntryStatus.done).length;

  bool get allDone => doneCount == parts.length;

  /// "2008–2024", "2008" when every part has the same year, null without
  /// any year.
  String? get yearSpan {
    final years = [for (final p in parts) ?p.year]..sort();
    if (years.isEmpty) return null;
    return years.first == years.last
        ? '${years.first}'
        : '${years.first}–${years.last}';
  }

  /// "4 movies", "3 volumes".
  String get countLabel => '$count ${seriesNouns(type).$2}';

  /// The italic line under the name: "4 movies · 2008–2024".
  String get subtitle => [countLabel, yearSpan].whereType<String>().join(' · ');

  /// "2 of 4 done"; the row shows a check instead when all are done.
  String get doneLabel => '$doneCount of $count done';

  @override
  bool operator ==(Object other) =>
      other is SeriesGroup &&
      other.type == type &&
      other.name == name &&
      other.lead.id == lead.id;

  @override
  int get hashCode => Object.hash(type, name, lead.id);
}

/// Whether a type list with [status] picked groups series (the status
/// segment All, Done or DNF). Want and In progress always show the single
/// entries: there you are picking what to watch next.
bool groupsSeriesFor(EntryStatus? status) =>
    status == null || status == EntryStatus.done || status == EntryStatus.dnf;

/// The same rule for filtered results, by the statuses in the filter: none,
/// or only Done and DNF, groups; a filter asking for Want or In progress
/// shows single entries.
bool groupsSeriesForFilter(Set<EntryStatus> statuses) =>
    statuses.every(groupsSeriesFor);

/// [sorted] with the parts of each series folded into one [SeriesGroup] at
/// the place of its first part in the order; entries in no series, and the
/// only part of a series in the library, stay single rows. A series is told
/// by type and name (compared like a title).
List<LibraryRow> groupSeriesRows(List<Entry> sorted) {
  final groups = <String, List<Entry>>{};
  final keyOf = <String, String>{};
  for (final entry in sorted) {
    final name = entry.series?.name;
    if (name == null || !entry.canHaveSeries) continue;
    final key = '${entry.type.name}/${titleKey(name)}';
    keyOf[entry.id] = key;
    groups.putIfAbsent(key, () => []).add(entry);
  }
  final done = <String>{};
  final rows = <LibraryRow>[];
  for (final entry in sorted) {
    final key = keyOf[entry.id];
    final parts = key == null ? null : groups[key]!;
    if (parts == null || parts.length < 2) {
      rows.add(EntryItem(entry));
      continue;
    }
    if (!done.add(key!)) continue;
    rows.add(
      SeriesGroup(
        name: entry.series!.name,
        lead: entry,
        parts: _inSeriesOrder(parts),
      ),
    );
  }
  return rows;
}

/// By number, parts without one after the rest in the order they came.
List<Entry> _inSeriesOrder(List<Entry> parts) {
  final indexed = parts.indexed.toList()
    ..sort((a, b) {
      final x = a.$2.series?.number, y = b.$2.series?.number;
      if (x != null && y != null && x != y) return x.compareTo(y);
      if (x == null && y != null) return 1;
      if (x != null && y == null) return -1;
      return a.$1.compareTo(b.$1);
    });
  return [for (final (_, part) in indexed) part];
}

/// A list "at least three screens tall" (the Library › Long list and Series
/// page notes): the rail's rule, and the one that decides whether a type
/// list groups its series.
const longListScreens = 3;

bool isLongList({
  required double contentHeight,
  required double viewportHeight,
}) => contentHeight >= longListScreens * viewportHeight;
