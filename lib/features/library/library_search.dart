import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/tag_category.dart';
import '../../widgets/labels.dart';
import '../music/music_tab.dart';
import 'home_type_provider.dart';
import 'library_filter_provider.dart';

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

  @override
  bool operator ==(Object other) =>
      other is TagMatch &&
      other.name == name &&
      other.count == count &&
      other.category == category;

  @override
  int get hashCode => Object.hash(name, count, category);

  @override
  String toString() => 'TagMatch($label, $count)';
}

/// The query as it is matched: trimmed, in lower case, without a leading
/// "#". Empty means no search.
String normalizeQuery(String query) {
  var q = query.trim().toLowerCase();
  if (q.startsWith('#')) q = q.substring(1).trimLeft();
  return q;
}

/// Whether [entry] is a result for [q] (already normalized, see
/// [normalizeQuery]): its title, its creator or one of its tags contains it,
/// whatever the case (the Library › Search: Music › Artists note).
bool matchesQuery(Entry entry, String q) =>
    entry.title.toLowerCase().contains(q) ||
    (entry.creator?.toLowerCase().contains(q) ?? false) ||
    entry.tags.any((tag) => tag.toLowerCase().contains(q));

/// The entries of [entries] that match [q], in their order.
List<Entry> searchEntries(Iterable<Entry> entries, String q) => [
  for (final entry in entries)
    if (matchesQuery(entry, q)) entry,
];

/// The tags whose name contains [q] and that an entry of [entries] carries,
/// the most used first (Library › Search: a tag matches). The count is of
/// [entries], the list being searched.
List<TagMatch> matchingTags(
  Library library,
  Iterable<Entry> entries,
  String q,
) {
  final pool = entries.toList();
  final names = <String>{
    for (final entry in pool)
      for (final tag in entry.tags)
        if (tag.toLowerCase().contains(q)) tag,
  };
  final tags = <TagMatch>[];
  for (final name in names) {
    final categories = library.categoriesOf(name);
    for (final category in categories.length > 1 ? categories : [null]) {
      final count = category == null
          ? pool.where((e) => e.tags.contains(name)).length
          : pool.where((e) => e.hasTagAs(name, category)).length;
      if (count > 0) tags.add(TagMatch(name, count, category: category));
    }
  }
  tags.sort((a, b) {
    final c = b.count.compareTo(a.count);
    if (c != 0) return c;
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : (a.category?.index ?? -1) - (b.category?.index ?? -1);
  });
  return tags;
}

/// How many of [entries] match [q], per type, for the types that have any.
Map<MediaType, int> matchCounts(Iterable<Entry> entries, String q) {
  final counts = <MediaType, int>{};
  for (final entry in entries) {
    if (matchesQuery(entry, q)) {
      counts[entry.type] = (counts[entry.type] ?? 0) + 1;
    }
  }
  return counts;
}

/// The music tab a search lands on when Music is opened with the query kept:
/// Artists when an artist's name matches, else Albums when an album does,
/// else Songs.
MusicTab musicTabForQuery(Iterable<Entry> music, String q) {
  final list = music.toList();
  if (list.any((e) => e.creator?.toLowerCase().contains(q) ?? false)) {
    return MusicTab.artists;
  }
  final hits = searchEntries(list, q);
  return hits.any((e) => e.kind != EntryKind.song) || hits.isEmpty
      ? MusicTab.albums
      : MusicTab.songs;
}

/// "Search titles and tags" on Home, "Search movies" with a type picked.
String searchHint(MediaType? type) => type == null
    ? 'Search titles and tags'
    : 'Search ${type.label.toLowerCase()}';

/// What is typed in the library home's search box (Library › Search: Music ›
/// Artists and its five sibling states): it filters the list shown, and no
/// longer opens a screen of its own. Session state.
///
/// The query belongs to the list it was typed over. Another type picked, a
/// swipe to one, or a filter's results opened or left clears it; the status
/// chips and the music tabs keep it. [openType] is the one way to another
/// type that keeps it ("3 results in Music", a heading of the home's
/// results).
class LibrarySearchNotifier extends Notifier<String> {
  MediaType? _kept;

  @override
  String build() {
    ref.listen(homeTypeProvider, (previous, next) {
      if (next != null && next == _kept) {
        _kept = null;
        return;
      }
      state = '';
    });
    ref.listen(libraryFilterProvider, (previous, next) {
      if (previous?.isActive != next.isActive) state = '';
    });
    return '';
  }

  void set(String query) {
    _kept = null;
    state = query;
  }

  void clear() => set('');

  /// Opens [type] with the query kept, on All of its status chips, or for
  /// music on the tab [music] names.
  void openType(MediaType type, {MusicTab? music}) {
    if (type == MediaType.music) {
      ref.read(homeMusicTabProvider.notifier).set(music ?? MusicTab.artists);
    } else {
      ref.read(homeStatusProvider.notifier).set(type, null);
    }
    if (ref.read(homeTypeProvider) == type) return;
    _kept = type;
    ref.read(homeTypeProvider.notifier).set(type);
  }
}

final librarySearchProvider = NotifierProvider<LibrarySearchNotifier, String>(
  LibrarySearchNotifier.new,
);

/// The query the page of [type] (null: Home) is narrowed by, normalized;
/// empty when it is not searched. Only the page shown is: the pages beside
/// it stay whole during a swipe, and under a filter's results the query
/// belongs to those.
final pageQueryProvider = Provider.family<String, MediaType?>((ref, type) {
  if (ref.watch(homeTypeProvider) != type) return '';
  if (ref.watch(libraryFilterProvider.select((f) => f.isActive))) return '';
  return normalizeQuery(ref.watch(librarySearchProvider));
});
