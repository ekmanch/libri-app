import '../../data/models/entry.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/tag_category.dart';
import '../../widgets/labels.dart';
import 'library_sort.dart';

/// A tag whose name matches the query, with how many entries use it. A tag
/// in more than one category is one match per category ("#clint-eastwood ·
/// Director", "#clint-eastwood · Actor"), each counting the entries that
/// carry it as that; [category] is null for a tag in one category.
class TagMatch {
  const TagMatch(this.name, this.count, {this.category});
  final String name;
  final int count;
  final TagCategory? category;

  /// "#horror", or "#clint-eastwood · Director".
  String get label => tagLabel(name, [?category]);

  /// The key of [SearchResults.tagged]: the name, with the category after a
  /// slash for a per-category match ("clint-eastwood/directors").
  String get key => category == null ? name : '$name/${category!.name}';
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

  /// Keyed by [TagMatch.key], in the order of [tags].
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

  final tags = <TagMatch>[];
  final tagged = <String, List<Entry>>{};
  for (final name in library.allTags) {
    if (!name.toLowerCase().contains(q)) continue;
    final categories = library.categoriesOf(name);
    for (final category in categories.length > 1 ? categories : [null]) {
      final entries = category == null
          ? pool.where((e) => e.tags.contains(name))
          : pool.where((e) => e.hasTagAs(name, category));
      final hits = homeOrder(entries);
      if (type != null && hits.isEmpty) continue;
      final match = TagMatch(name, hits.length, category: category);
      tags.add(match);
      tagged[match.key] = hits;
    }
  }
  tags.sort((a, b) {
    final c = b.count.compareTo(a.count);
    if (c != 0) return c;
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : (a.category?.index ?? -1) - (b.category?.index ?? -1);
  });
  return SearchResults(
    titles: titles,
    tags: tags,
    tagged: {for (final match in tags) match.key: tagged[match.key]!},
  );
}
