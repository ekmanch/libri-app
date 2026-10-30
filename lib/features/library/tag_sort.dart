/// How tags are listed wherever a group of them is shown (Library › Filter
/// sheet; Add / edit entry › Tag picker; Plans › Edit plan; Library › Filter:
/// all Authors): A to Z by the tag itself, so people sort by first name, with a
/// leading "the" ignored. Groups over [longTagGroup] tags are a row that opens
/// the full-screen list (Library › Filter: all Authors) instead of inline
/// chips.
library;

import '../../data/models/tag_category.dart';

export '../../data/models/creator_names.dart'
    show splitCreators, tagDisplayName;

/// A group with more tags than this is shown as a row that opens Library ›
/// Filter: all Authors.
const longTagGroup = 24;

/// The key a tag sorts by: the tag without a leading "the-".
String tagSortKey(String tag) =>
    tag.startsWith('the-') ? tag.substring(4) : tag;

/// [tags] in display order.
List<String> sortedTags(Iterable<String> tags) {
  final list = tags.toList();
  list.sort((a, b) {
    final c = tagSortKey(a).compareTo(tagSortKey(b));
    return c != 0 ? c : a.compareTo(b);
  });
  return list;
}

/// "author", "authors" for the creator groups, "tag", "tags" for the rest: the
/// noun Library › Filter: all Authors counts in ("64 authors · 1 selected",
/// "Search authors").
String tagGroupNoun(TagCategory category, int count) {
  final one = switch (category) {
    TagCategory.authors => 'author',
    TagCategory.directors => 'director',
    TagCategory.actors => 'actor',
    TagCategory.studios => 'studio',
    _ => 'tag',
  };
  return count == 1 ? one : '${one}s';
}

/// "64 authors · 1 selected", "12 tags".
String tagGroupCountLabel(TagCategory category, int count, int selected) =>
    '$count ${tagGroupNoun(category, count)}'
    '${selected > 0 ? ' · $selected selected' : ''}';
