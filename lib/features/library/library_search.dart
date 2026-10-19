import '../../data/models/entry.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import 'library_sort.dart';

/// A tag whose name matches the query, with how many entries use it.
class TagMatch {
  const TagMatch(this.name, this.count);
  final String name;
  final int count;
}

/// What Library › Search shows for a query: matching titles, matching tags, and
/// the entries behind each matching tag.
class SearchResults {
  const SearchResults({
    this.titles = const [],
    this.tags = const [],
    this.tagged = const {},
  });

  static const empty = SearchResults();

  final List<Entry> titles;
  final List<TagMatch> tags;

  /// Keyed by tag, in the order of [tags].
  final Map<String, List<Entry>> tagged;

  bool get isEmpty => titles.isEmpty && tags.isEmpty;
}

/// Case-insensitive substring search over titles and tag names. A leading
/// "#" in the query is ignored. Seasonal-only entries are included; search
/// is not one of the main lists. With [type] set (a type chip picked on the
/// home) only that type's entries are searched, and a tag is listed only
/// when one of them uses it.
SearchResults searchLibrary(Library library, String query, {MediaType? type}) {
  var q = query.trim().toLowerCase();
  if (q.startsWith('#')) q = q.substring(1);
  if (q.isEmpty) return SearchResults.empty;
  final pool = type == null ? library.entries : library.entriesOfType(type);

  final titles = sortEntries(
    pool.where((e) => e.title.toLowerCase().contains(q)),
    LibrarySort.titleAz,
  );

  final counts = <String, int>{};
  for (final entry in pool) {
    for (final tag in entry.tags) {
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final tags =
      [
        for (final name in library.allTags)
          if (name.toLowerCase().contains(q) &&
              (type == null || counts.containsKey(name)))
            TagMatch(name, counts[name] ?? 0),
      ]..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.name.compareTo(b.name);
      });

  final tagged = {
    for (final tag in tags)
      tag.name: homeOrder(pool.where((e) => e.tags.contains(tag.name))),
  };
  return SearchResults(titles: titles, tags: tags, tagged: tagged);
}
