import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/tag_category.dart';
import '../../widgets/labels.dart';
import '../music/music_tab.dart';
import 'home_type_provider.dart';
import 'library_filter.dart';
import 'library_filter_provider.dart';

/// A tag whose name matches the query, with how many entries use it. A tag
/// in more than one category is one match per category ("#clint-eastwood ·
/// Director", "#clint-eastwood · Actor"), each counting the entries that
/// carry it as that; [category] is null for a tag in one category.
class TagMatch {
  const TagMatch(this.name, this.count, {this.category, this.picked = false});
  final String name;
  final int count;
  final TagCategory? category;

  /// Whether the list is narrowed to this tag: its chip is filled, with a
  /// cross, and a tap lifts it.
  final bool picked;

  /// "#horror", or "#clint-eastwood · Director".
  String get label => tagLabel(name, [?category]);

  @override
  bool operator ==(Object other) =>
      other is TagMatch &&
      other.name == name &&
      other.count == count &&
      other.category == category &&
      other.picked == picked;

  @override
  int get hashCode => Object.hash(name, count, category, picked);

  @override
  String toString() => 'TagMatch($label, $count${picked ? ', picked' : ''})';
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
/// whatever the case (the Library › Search: Music › Artists note), or, for
/// an album, the title of one of its rated tracks, as on the desktop: the
/// unrated titles are known only where the album's list has been fetched.
bool matchesQuery(Entry entry, String q) =>
    entry.title.toLowerCase().contains(q) ||
    (entry.creator?.toLowerCase().contains(q) ?? false) ||
    entry.tags.any((tag) => tag.toLowerCase().contains(q)) ||
    (entry.tracks?.any(
          (track) =>
              track.rating != null && track.title.toLowerCase().contains(q),
        ) ??
        false);

/// The entries of [entries] that match [q], in their order.
List<Entry> searchEntries(Iterable<Entry> entries, String q) => [
  for (final entry in entries)
    if (matchesQuery(entry, q)) entry,
];

/// The chips of a list's Tags row (Library › Search: a tag matches; Search:
/// a tag finds artists): the tags the list is narrowed to ([picked], a
/// filter's tags), filled and first, then the tags whose name contains [q]
/// and that an entry of [entries] carries, each group the most used first.
/// The count is of [entries], the list being searched, before a tag is
/// picked. An empty [q] matches no tag.
List<TagMatch> matchingTags(
  Library library,
  Iterable<Entry> entries,
  String q, {
  LibraryFilter picked = LibraryFilter.none,
}) {
  final pool = entries.toList();
  final names = <String>{
    ...picked.tags,
    if (q.isNotEmpty)
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
      final on = picked.hasTag(name, category);
      // A picked tag stays in the row whatever is typed.
      if (on || (count > 0 && q.isNotEmpty && name.toLowerCase().contains(q))) {
        tags.add(TagMatch(name, count, category: category, picked: on));
      }
    }
  }
  tags.sort((a, b) {
    if (a.picked != b.picked) return a.picked ? -1 : 1;
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
/// results). A filter that narrows the type shown in place keeps it too;
/// the results screen of a filter, opened or left, clears it.
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
      if (previous?.showsResults != next.showsResults) state = '';
    });
    return '';
  }

  void set(String query) {
    _kept = null;
    state = query;
  }

  void clear() => set('');

  /// Opens [type] with the query kept, on All of its status chips, or for
  /// music on the tab [music] names. The tags picked in the Tags row
  /// ([tags]) come along and narrow that type's list.
  void openType(
    MediaType type, {
    MusicTab? music,
    LibraryFilter tags = LibraryFilter.none,
  }) {
    if (type == MediaType.music) {
      ref.read(homeMusicTabProvider.notifier).set(music ?? MusicTab.artists);
    } else {
      ref.read(homeStatusProvider.notifier).set(type, null);
    }
    if (ref.read(homeTypeProvider) == type) return;
    _kept = type;
    ref.read(homeTypeProvider.notifier).set(type);
    if (tags.tags.isNotEmpty) {
      ref
          .read(libraryFilterProvider.notifier)
          .narrow(tags.tagsOnly.copyWith(types: {type}));
    }
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
  if (ref.watch(libraryFilterProvider.select((f) => f.showsResults))) {
    return '';
  }
  return normalizeQuery(ref.watch(librarySearchProvider));
});

/// The tag picked in the Tags row of Home's results (Library › Search: a tag
/// matches), as a filter of tags alone; [LibraryFilter.none] when none is.
/// It stays when the query is cleared. A type opened, a filter's results
/// and a return to the home let go of it. On a type's page the picked tags
/// are that type's filter instead ([LibraryFilterNotifier.narrow]).
class HomeTagsNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() {
    ref.listen(homeTypeProvider, (_, _) => state = LibraryFilter.none);
    ref.listen(libraryFilterProvider, (previous, next) {
      if (previous?.showsResults != next.showsResults) {
        state = LibraryFilter.none;
      }
    });
    return LibraryFilter.none;
  }

  void pick(TagMatch tag) =>
      state = state.withTagPicked(tag.name, tag.category);

  void clear() => state = LibraryFilter.none;
}

final homeTagsProvider = NotifierProvider<HomeTagsNotifier, LibraryFilter>(
  HomeTagsNotifier.new,
);

/// The tags the page of [type] (null: Home) is narrowed to, as a filter of
/// tags alone: Home's own pick, or the tags of the filter that narrows a
/// type's list in place.
final pageTagsProvider = Provider.family<LibraryFilter, MediaType?>((
  ref,
  type,
) {
  if (ref.watch(homeTypeProvider) != type) return LibraryFilter.none;
  if (type == null) {
    return ref.watch(libraryFilterProvider.select((f) => f.showsResults))
        ? LibraryFilter.none
        : ref.watch(homeTagsProvider);
  }
  final filter = ref.watch(libraryFilterProvider);
  return filter.typeView?.type == type ? filter.tagsOnly : LibraryFilter.none;
});
