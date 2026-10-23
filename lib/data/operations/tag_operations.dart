import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

import '../models/entry.dart';
import '../models/library.dart';
import '../models/tag_category.dart';
import 'library_operation.dart';

part 'tag_operations.g.dart';

/// Adds a tag to the tag map under one or more categories. Tags are only
/// created from the entry form's tag picker (Add / edit entry › New tag:
/// confirm and pick a category), right before the entry that uses them is
/// saved; a tag no entry or plan uses is pruned on the next edit. A tag can
/// be in several categories of one kind (people: Authors, Directors, Actors;
/// genres: Genres, Game genres, Music genres); the dialog sees to that.
@JsonSerializable()
class AddTag extends LibraryOperation {
  const AddTag(this.name, this.categories);

  /// A tag in one category.
  AddTag.single(String name, TagCategory category) : this(name, [category]);

  /// Reads `categories`, or the one `category` the operation had before
  /// tags could be in several (a queue written before 2026-10-21).
  factory AddTag.fromJson(Map<String, Object?> json) => _$AddTagFromJson(
    json['categories'] == null && json['category'] != null
        ? {
            ...json,
            'categories': [json['category']],
          }
        : json,
  );

  Map<String, Object?> toJson() => _$AddTagToJson(this);

  final String name;
  final List<TagCategory> categories;

  @override
  Library apply(Library library) {
    if (library.allTags.contains(name) || categories.isEmpty) return library;
    final tags = {
      for (final MapEntry(key: k, value: v) in library.tags.entries) k: [...v],
    };
    for (final category in TagCategory.values) {
      if (categories.contains(category)) {
        tags.putIfAbsent(category, () => []).add(name);
      }
    }
    // A new category goes in its place, not at the end of the map.
    return library.copyWith(tags: Library.tagsInCategoryOrder(tags));
  }

  @override
  String summary(Library before) => 'Add the tag #$name';
}

/// Puts an existing tag in exactly [categories] (Add / edit entry › Tag
/// picker: a long-press on a tag, or "+ Add to Actors" on a search hit from
/// another category of the same kind). Every entry carrying the tag keeps
/// the categories it had that remain; an entry that had the tag only in a
/// category taken away loses the tag. A move from one category to one
/// other (Other to Languages: a tag of a kind that has one category) keeps
/// the tag on every entry. Picks are written only while the tag is in more
/// than one category. An unknown tag, or no category, changes nothing.
@JsonSerializable()
class SetTagCategories extends LibraryOperation {
  const SetTagCategories(this.name, this.categories);

  factory SetTagCategories.fromJson(Map<String, Object?> json) =>
      _$SetTagCategoriesFromJson(json);

  Map<String, Object?> toJson() => _$SetTagCategoriesToJson(this);

  final String name;
  final List<TagCategory> categories;

  @override
  Library apply(Library library) {
    final before = library.categoriesOf(name);
    final after = [
      for (final c in TagCategory.values)
        if (categories.contains(c)) c,
    ];
    if (before.isEmpty || after.isEmpty || listEquals(before, after)) {
      return library;
    }
    final tags = {
      for (final MapEntry(key: k, value: v) in library.tags.entries) k: [...v],
    };
    for (final category in TagCategory.values) {
      final list = tags[category];
      final listed = list?.contains(name) ?? false;
      if (after.contains(category) && !listed) {
        tags.putIfAbsent(category, () => []).add(name);
      } else if (!after.contains(category) && listed) {
        list!.remove(name);
        if (list.isEmpty) tags.remove(category);
      }
    }
    return library
        .copyWith(
          tags: Library.tagsInCategoryOrder(tags),
          entries: [
            for (final entry in library.entries) _retag(entry, before, after),
          ],
        )
        .withUnusedTagsRemoved();
  }

  Entry _retag(Entry entry, List<TagCategory> before, List<TagCategory> after) {
    if (!entry.tags.contains(name)) return entry;
    if (before.length == 1 && after.length == 1) {
      // A move: the tag is on the entry as its one category, whatever it was.
      final picks = {...?entry.tagCategories}..remove(name);
      return entry.copyWith(tagCategories: picks.isEmpty ? null : picks);
    }
    final had = entry.categoriesOf(name, before);
    final kept = [
      for (final c in after)
        if (had.contains(c)) c,
    ];
    final picks = {...?entry.tagCategories}..remove(name);
    if (kept.isEmpty) {
      return entry.copyWith(
        tags: entry.tags.where((t) => t != name).toList(),
        tagCategories: picks.isEmpty ? null : picks,
      );
    }
    if (after.length > 1) picks[name] = kept;
    return entry.copyWith(tagCategories: picks.isEmpty ? null : picks);
  }

  @override
  String summary(Library before) {
    final labels = [for (final c in categories) _$TagCategoryEnumMap[c]];
    return 'Put the tag #$name under ${labels.join(', ')}';
  }
}
