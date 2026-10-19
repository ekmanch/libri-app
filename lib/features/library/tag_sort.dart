/// How tags are listed wherever a group of them is shown (Library › Filter
/// sheet; Add / edit entry › Tag picker; Plans › Edit plan; Library › Filter:
/// all Authors): A to Z by the tag itself, so people sort by first name, with a
/// leading "the" ignored. Groups over [longTagGroup] tags are a row that opens
/// the full-screen list (Library › Filter: all Authors) instead of inline
/// chips.
library;

import '../../data/models/entry_id.dart';
import '../../data/models/library.dart';
import '../../data/models/tag_category.dart';

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

/// "Stephen King" for #stephen-king: the creator text of an entry that
/// carries the tag and whose creator slugs to it, so the name keeps its
/// dots and accents ("Ursula K. Le Guin", "Jo Nesbø"); else the tag's words
/// with capitals ("Mike Flanagan", "Team Cherry").
String tagDisplayName(String tag, Library library) {
  for (final entry in library.entries) {
    final creator = entry.creator;
    if (creator == null || !entry.tags.contains(tag)) continue;
    for (final part in splitCreators(creator)) {
      if (slugify(part) == tag) return part;
    }
  }
  return tag
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// The names in a creator field: "Stephen King & Peter Straub", "Craig
/// Mazin, Neil Druckmann".
List<String> splitCreators(String creator) => creator
    .split(RegExp(r'\s*(?:,|&|/|\band\b)\s*'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

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
