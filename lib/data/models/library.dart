import 'package:freezed_annotation/freezed_annotation.dart';

import 'entry.dart';
import 'media_type.dart';
import 'plan.dart';
import 'tag_category.dart';

part 'library.freezed.dart';
part 'library.g.dart';

/// The whole `library.json` file, version 2.
@freezed
abstract class Library with _$Library {
  const Library._();

  const factory Library({
    @Default(2) int version,
    @Default({}) Map<TagCategory, List<String>> tags,
    @Default([]) List<Entry> entries,
    @Default([]) List<Plan> plans,
  }) = _Library;

  factory Library.fromJson(Map<String, Object?> json) =>
      _$LibraryFromJson(json);

  Entry? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Plan? planById(String id) {
    for (final plan in plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  List<Entry> entriesOfType(MediaType type) =>
      entries.where((e) => e.type == type).toList();

  /// Every tag name in the map, in any category.
  Set<String> get allTags => {for (final names in tags.values) ...names};

  /// The categories [tag] is in, in category order: one for most tags,
  /// several for a person or a genre listed in more than one category of
  /// its kind (#clint-eastwood under Directors and Actors). Empty for a tag
  /// the map does not have.
  List<TagCategory> categoriesOf(String tag) => [
    for (final MapEntry(key: category, value: names) in tags.entries)
      if (names.contains(tag)) category,
  ];

  /// Whether [tag] is in more than one category.
  bool isMultiCategory(String tag) => categoriesOf(tag).length > 1;

  /// The categories [tag] has on [entry]: the entry's own pick for a tag in
  /// several categories, else every category the tag is in.
  List<TagCategory> categoriesOn(Entry entry, String tag) =>
      entry.categoriesOf(tag, categoriesOf(tag));

  /// How many entries carry [tag] as [category].
  int countTagAs(String tag, TagCategory category) =>
      entries.where((e) => e.hasTagAs(tag, category)).length;

  /// Tags used by at least one entry or one plan.
  Set<String> get usedTags => {
    for (final entry in entries) ...entry.tags,
    for (final plan in plans) ...plan.tags,
  };

  /// The tag map with its categories in [TagCategory] declaration order,
  /// which is the order `library.json` and the data repo's `library.py`
  /// expect. Order within a category is kept. A Dart map keeps insertion
  /// order, so without this a category added after the file was first
  /// written ("Studios" on a file from before the Creators split) would
  /// land at the end.
  static Map<TagCategory, List<String>> tagsInCategoryOrder(
    Map<TagCategory, List<String>> tags,
  ) => {for (final category in TagCategory.values) category: ?tags[category]};

  /// Drops tags no entry and no plan uses, and categories left empty.
  /// Order within a category is kept.
  Library withUnusedTagsRemoved() {
    final used = usedTags;
    final pruned = <TagCategory, List<String>>{};
    for (final MapEntry(key: category, value: names) in tags.entries) {
      final kept = names.where(used.contains).toList();
      if (kept.isNotEmpty) pruned[category] = kept;
    }
    return copyWith(tags: pruned);
  }
}
