import 'package:flutter/foundation.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/tag_category.dart';
import '../../widgets/labels.dart';

/// A release decade in the filter sheet: "Older" for everything before
/// [oldestNamed], then one chip per decade. The chips come from the library:
/// the row runs from the earliest to the latest decade that has an entry,
/// with the decades in between filled in so there is no gap, and "Older"
/// only when something is older than 1960.
@immutable
class Decade implements Comparable<Decade> {
  const Decade(int this.start) : assert(start % 10 == 0);
  const Decade.older() : start = null;

  /// The first year of the decade, null for "Older".
  final int? start;

  static const oldestNamed = 1960;

  bool get isOlder => start == null;

  String get label => isOlder ? 'Older' : '${start}s';

  static Decade? of(int? year) {
    if (year == null) return null;
    if (year < oldestNamed) return const Decade.older();
    return Decade(year ~/ 10 * 10);
  }

  /// The chips for a library whose entries have [years] (nulls ignored).
  static List<Decade> optionsFor(Iterable<int?> years) {
    var older = false;
    int? first;
    int? last;
    for (final year in years) {
      if (year == null) continue;
      if (year < oldestNamed) {
        older = true;
        continue;
      }
      final start = year ~/ 10 * 10;
      if (first == null || start < first) first = start;
      if (last == null || start > last) last = start;
    }
    return [
      if (older) const Decade.older(),
      if (first != null)
        for (var y = first; y <= last!; y += 10) Decade(y),
    ];
  }

  @override
  int compareTo(Decade other) => (start ?? 0).compareTo(other.start ?? 0);

  @override
  bool operator ==(Object other) => other is Decade && other.start == start;

  @override
  int get hashCode => start.hashCode;

  @override
  String toString() => label;
}

/// The filter sheet's choices (Library › Filter sheet). Within type, status,
/// kind and released any choice matches; every chosen tag must be on the entry.
/// Kind (albums, songs) only narrows music. Seasonal-only entries are hidden
/// unless [includeSeasonalOnly] is on.
///
/// A tag in more than one category is chosen per category: Directors ›
/// #clint-eastwood matches only entries where he is picked as a director.
/// Such a choice is the tag in [tags] plus its categories in [tagCategories];
/// a tag there with no categories (one in a single category, or chosen by
/// name) matches whatever category it has on the entry.
@immutable
class LibraryFilter {
  const LibraryFilter({
    this.types = const {},
    this.statuses = const {},
    this.kinds = const {},
    this.decades = const {},
    this.tags = const {},
    this.tagCategories = const {},
    this.includeSeasonalOnly = false,
  });

  final Set<MediaType> types;
  final Set<EntryStatus> statuses;
  final Set<EntryKind> kinds;
  final Set<Decade> decades;
  final Set<String> tags;

  /// The categories a tag in [tags] is chosen as, for tags chosen per
  /// category. Never an empty set: a tag with none is not in the map.
  final Map<String, Set<TagCategory>> tagCategories;
  final bool includeSeasonalOnly;

  static const none = LibraryFilter();

  /// True when nothing is chosen, so the home shows the plain library.
  bool get isEmpty =>
      types.isEmpty &&
      statuses.isEmpty &&
      kinds.isEmpty &&
      decades.isEmpty &&
      tags.isEmpty &&
      !includeSeasonalOnly;

  bool get isActive => !isEmpty;

  /// Spells out a filter that matches nothing (Library › Empty states): "No
  /// books are both in progress and tagged #christmas. Remove a filter to see
  /// more."
  String get noMatchesText {
    String join(List<String> parts, String word) => parts.length < 2
        ? parts.join()
        : '${parts.sublist(0, parts.length - 1).join(', ')} $word ${parts.last}';
    String plural(MediaType t) => switch (t) {
      MediaType.music when kinds.length == 1 => kinds.single.plural,
      MediaType.music => 'albums or songs',
      _ => t.label.toLowerCase(),
    };
    final subject = types.isEmpty
        ? 'entries'
        : join([
            for (final t in MediaType.values)
              if (types.contains(t)) plural(t),
          ], 'or');
    final conditions = [
      if (statuses.isNotEmpty)
        join([
          for (final s in EntryStatus.values)
            if (statuses.contains(s))
              switch (s) {
                EntryStatus.want => 'wanted',
                EntryStatus.inProgress => 'in progress',
                EntryStatus.done => 'done',
                EntryStatus.dnf => 'not finished',
              },
        ], 'or'),
      if (decades.isNotEmpty)
        join([
          for (final d in decades.toList()..sort())
            d.isOlder
                ? 'from before ${Decade.oldestNamed}'
                : 'from the ${d.label}',
        ], 'or'),
      if (tags.isNotEmpty)
        'tagged ${join([for (final chip in tagChips) chip.label], 'and')}',
    ];
    const tail = 'Remove a filter to see more.';
    if (conditions.isEmpty) return tail;
    final what = switch (conditions.length) {
      1 => conditions.single,
      2 => 'both ${conditions[0]} and ${conditions[1]}',
      _ => join(conditions, 'and'),
    };
    return 'No $subject are $what. $tail';
  }

  /// The type view that shows this filter, when the home's chips can: one type
  /// and at most one status, nothing else (Library › Movies + Done (filter
  /// result)). For music the kind plays the status segment's part: at most one
  /// kind and no status, so Music + Songs is the Songs tab (Library › Music:
  /// songs (filter result)) and Music + Albums the Albums tab (Library › Music:
  /// albums (filter result)). That is not a results screen.
  TypeView? get typeView {
    if (types.length != 1 ||
        decades.isNotEmpty ||
        tags.isNotEmpty ||
        includeSeasonalOnly) {
      return null;
    }
    final type = types.single;
    if (type == MediaType.music) {
      if (statuses.isNotEmpty || kinds.length > 1) return null;
      return (type: type, status: null, kind: kinds.firstOrNull);
    }
    if (statuses.length > 1) return null;
    return (type: type, status: statuses.firstOrNull, kind: null);
  }

  /// What the home's type view shows, as a filter: the sheet opens with it.
  static LibraryFilter ofTypeView(
    MediaType? type, {
    EntryStatus? status,
    EntryKind? kind,
  }) => LibraryFilter(types: {?type}, statuses: {?status}, kinds: {?kind});

  /// The Kind group shows only with music chosen.
  bool get offersKind => types.contains(MediaType.music);

  /// The status chips for the chosen types: no In progress when only movies
  /// and music are chosen, no DNF when only music is. All of them with no
  /// type chosen.
  List<EntryStatus> get statusOptions => types.isEmpty
      ? EntryStatus.values
      : [
          for (final s in EntryStatus.values)
            if (types.any((t) => EntryStatus.optionsFor(t).contains(s))) s,
        ];

  /// The tag groups the sheet shows (Library › Filter sheet), in category
  /// order: a group shows when an entry of a chosen type uses one of its tags,
  /// so Games shows Genres too once a game is tagged #horror. Streaming shows
  /// only when movies or shows are among the chosen types. With no type,
  /// every group.
  List<(TagCategory, List<String>)> tagGroupsIn(Library library) {
    final used = types.isEmpty
        ? null
        : {
            for (final e in library.entries)
              if (types.contains(e.type)) ...e.tags,
          };
    return [
      for (final category in TagCategory.values)
        if (library.tags[category] case final names?
            when names.isNotEmpty &&
                (used == null ||
                    (types.any(category.usedFor) && names.any(used.contains))))
          (category, names),
    ];
  }

  /// Drops chosen tags whose group the chosen types no longer show.
  LibraryFilter keepTagsShownIn(Library library) {
    final shown = {for (final (_, names) in tagGroupsIn(library)) ...names};
    return copyWith(
      tags: tags.where(shown.contains).toSet(),
      tagCategories: {
        for (final MapEntry(key: tag, value: categories)
            in tagCategories.entries)
          if (shown.contains(tag)) tag: categories,
      },
    );
  }

  /// Whether [tag] is chosen, as [category] when one is given: chosen in
  /// that category, or chosen by name alone (which counts in every one).
  bool hasTag(String tag, [TagCategory? category]) {
    if (!tags.contains(tag)) return false;
    final categories = tagCategories[tag];
    return category == null ||
        categories == null ||
        categories.contains(category);
  }

  /// The removable chips for the chosen tags: "#horror", and for a tag
  /// chosen per category one per category, "#clint-eastwood · Director".
  List<ActiveFilterChip> get tagChips => [
    for (final tag in tags) ..._chipsFor(tag),
  ];

  List<ActiveFilterChip> _chipsFor(String tag) {
    final categories = tagCategories[tag];
    if (categories == null) {
      return [ActiveFilterChip('#$tag', (f) => f.toggleTag(tag))];
    }
    return [
      for (final c in TagCategory.values)
        if (categories.contains(c))
          ActiveFilterChip(
            tagLabel(tag, [c]),
            (f) => f.toggleTag(tag, category: c),
          ),
    ];
  }

  /// Number shown on the filter button badge.
  int get count =>
      types.length +
      statuses.length +
      kinds.length +
      decades.length +
      tagChips.length +
      (includeSeasonalOnly ? 1 : 0);

  bool matches(Entry entry) {
    if (entry.seasonalOnly && !includeSeasonalOnly) return false;
    if (types.isNotEmpty && !types.contains(entry.type)) return false;
    if (statuses.isNotEmpty && !statuses.contains(entry.status)) return false;
    if (kinds.isNotEmpty &&
        entry.type == MediaType.music &&
        !kinds.contains(entry.kind ?? EntryKind.album)) {
      return false;
    }
    if (decades.isNotEmpty && !decades.contains(Decade.of(entry.year))) {
      return false;
    }
    for (final tag in tags) {
      if (!entry.tags.contains(tag)) return false;
      for (final category in tagCategories[tag] ?? const <TagCategory>{}) {
        if (!entry.hasTagAs(tag, category)) return false;
      }
    }
    return true;
  }

  List<Entry> apply(Iterable<Entry> entries) => entries.where(matches).toList();

  LibraryFilter copyWith({
    Set<MediaType>? types,
    Set<EntryStatus>? statuses,
    Set<EntryKind>? kinds,
    Set<Decade>? decades,
    Set<String>? tags,
    Map<String, Set<TagCategory>>? tagCategories,
    bool? includeSeasonalOnly,
  }) => LibraryFilter(
    types: types ?? this.types,
    statuses: statuses ?? this.statuses,
    kinds: kinds ?? this.kinds,
    decades: decades ?? this.decades,
    tags: tags ?? this.tags,
    tagCategories: tagCategories ?? this.tagCategories,
    includeSeasonalOnly: includeSeasonalOnly ?? this.includeSeasonalOnly,
  );

  static Set<T> _toggled<T>(Set<T> set, T value) =>
      set.contains(value) ? (set.toSet()..remove(value)) : {...set, value};

  /// Toggles a type and drops any chosen status the types can no longer
  /// have, and the kind without music, so a hidden chip never filters.
  LibraryFilter toggleType(MediaType t) {
    final next = copyWith(types: _toggled(types, t));
    final options = next.statusOptions;
    return next.copyWith(
      statuses: statuses.where(options.contains).toSet(),
      kinds: next.offersKind ? kinds : const {},
    );
  }

  LibraryFilter toggleStatus(EntryStatus s) =>
      copyWith(statuses: _toggled(statuses, s));
  LibraryFilter toggleKind(EntryKind k) => copyWith(kinds: _toggled(kinds, k));
  LibraryFilter toggleDecade(Decade d) =>
      copyWith(decades: _toggled(decades, d));

  /// Toggles a tag, as [category] for a tag chosen per category: the first
  /// category chooses the tag, the last one taken away drops it. With no
  /// category the tag is toggled by name, which also clears its categories.
  /// A tag chosen by name and then toggled as a category keeps only that
  /// category (the sheet never shows such a tag, see [hasTag]).
  LibraryFilter toggleTag(String tag, {TagCategory? category}) {
    final others = {...tagCategories}..remove(tag);
    if (category == null) {
      return copyWith(tags: _toggled(tags, tag), tagCategories: others);
    }
    final Set<TagCategory> chosen =
        tagCategories[tag] == null && tags.contains(tag)
        ? {category}
        : _toggled(tagCategories[tag] ?? const {}, category);
    if (chosen.isEmpty) {
      return copyWith(tags: {...tags}..remove(tag), tagCategories: others);
    }
    return copyWith(
      tags: {...tags, tag},
      tagCategories: {...others, tag: chosen},
    );
  }

  /// The removable chips of Library › Filtered results, one type and several
  /// types, in sheet order.
  List<ActiveFilterChip> get chips => [
    for (final t in MediaType.values)
      if (types.contains(t)) ActiveFilterChip(t.label, (f) => f.toggleType(t)),
    for (final s in EntryStatus.values)
      if (statuses.contains(s))
        ActiveFilterChip(s.label, (f) => f.toggleStatus(s)),
    for (final k in EntryKind.musicKinds)
      if (kinds.contains(k)) ActiveFilterChip(k.label, (f) => f.toggleKind(k)),
    for (final d in decades.toList()..sort())
      ActiveFilterChip(d.label, (f) => f.toggleDecade(d)),
    ...tagChips,
    if (includeSeasonalOnly)
      ActiveFilterChip(
        'Seasonal-only included',
        (f) => f.copyWith(includeSeasonalOnly: false),
      ),
  ];

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      setEquals(other.types, types) &&
      setEquals(other.statuses, statuses) &&
      setEquals(other.kinds, kinds) &&
      setEquals(other.decades, decades) &&
      setEquals(other.tags, tags) &&
      _sameCategories(other.tagCategories, tagCategories) &&
      other.includeSeasonalOnly == includeSeasonalOnly;

  static bool _sameCategories(
    Map<String, Set<TagCategory>> a,
    Map<String, Set<TagCategory>> b,
  ) =>
      a.length == b.length &&
      a.entries.every((e) => b[e.key] != null && setEquals(b[e.key], e.value));

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(types),
    Object.hashAllUnordered(statuses),
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(decades),
    Object.hashAllUnordered(tags),
    Object.hashAllUnordered([
      for (final MapEntry(key: tag, value: categories) in tagCategories.entries)
        Object.hash(tag, Object.hashAllUnordered(categories)),
    ]),
    includeSeasonalOnly,
  );
}

/// The home's type view: the picked type, its status segment and, for
/// music, the Albums or Songs tab (null kind is the Artists tab).
typedef TypeView = ({MediaType type, EntryStatus? status, EntryKind? kind});

/// One active filter and how to remove it.
class ActiveFilterChip {
  const ActiveFilterChip(this.label, this.remove);
  final String label;
  final LibraryFilter Function(LibraryFilter) remove;
}
