import 'package:json_annotation/json_annotation.dart';

import '../models/library.dart';
import '../models/tag_category.dart';
import 'library_operation.dart';

part 'tag_operations.g.dart';

/// Adds a tag to the tag map under a category. Tags are only created from the
/// entry form's tag picker (Add / edit entry › New tag: confirm and pick a
/// category), right before the entry that uses them is saved; a tag no entry or
/// plan uses is pruned on the next edit.
@JsonSerializable()
class AddTag extends LibraryOperation {
  const AddTag(this.name, this.category);

  factory AddTag.fromJson(Map<String, Object?> json) => _$AddTagFromJson(json);

  Map<String, Object?> toJson() => _$AddTagToJson(this);

  final String name;
  final TagCategory category;

  @override
  Library apply(Library library) {
    if (library.allTags.contains(name)) return library;
    final tags = {
      for (final MapEntry(key: k, value: v) in library.tags.entries) k: [...v],
    };
    tags.putIfAbsent(category, () => []).add(name);
    // A new category goes in its place, not at the end of the map.
    return library.copyWith(tags: Library.tagsInCategoryOrder(tags));
  }

  @override
  String summary(Library before) => 'Add the tag #$name';
}
