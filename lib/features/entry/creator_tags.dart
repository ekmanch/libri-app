/// The tags the entry form suggests for the people behind an entry
/// (Add / edit entry): the creator field's author of a book, director of a
/// movie or studio of a game or an anime, each as a slug ("#stephen-king",
/// "#naughty-dog") in its creator group, and for movies and shows the
/// top-billed cast from the lookup as actor tags ("#kate-siegel"). Studios
/// whose name is how their films are known get their tag instead of the
/// director's: a Pixar film suggests #pixar, not the director. Music suggests
/// nothing, since an artist is not a tag.
library;

import '../../data/lookup/languages.dart';
import '../../data/models/entry_id.dart';
import '../../data/models/media_type.dart';
import '../../data/models/tag_category.dart';
import '../library/tag_sort.dart';

/// One suggested tag and the group it is created in.
typedef CreatorTag = ({String tag, TagCategory category});

/// Companies (as a lookup names them, lowercased) whose films carry the
/// studio's tag rather than the director's. Checked in this order, so a
/// Pixar film with "Walt Disney Pictures" on it is #pixar. Only the
/// animation studios: "Walt Disney Pictures" alone is a live-action film,
/// which keeps its director.
const brandStudios = <String, String>{
  'studio ghibli': 'studio-ghibli',
  'pixar': 'pixar',
  'walt disney animation studios': 'disney',
  'walt disney productions': 'disney',
  'disneytoon studios': 'disney',
  'dreamworks animation': 'dreamworks',
};

/// Directors whose name, typed by hand with no lookup to say the company,
/// still means the studio.
const houseDirectors = <String, String>{
  'hayao miyazaki': 'studio-ghibli',
  'isao takahata': 'studio-ghibli',
};

/// The brand among [companies], or null.
String? brandStudioOf(Iterable<String> companies) {
  final names = companies.map((c) => c.toLowerCase()).toList();
  for (final MapEntry(key: brand, value: tag) in brandStudios.entries) {
    if (names.any((n) => n.contains(brand))) return tag;
  }
  return null;
}

/// The tags for an entry of [type] whose creator field reads [creator],
/// found through a lookup that named [companies] (production companies,
/// studios, developers). Empty for music, for an empty field, and when
/// nothing slugs to a tag.
List<CreatorTag> creatorTags({
  required MediaType type,
  required String? creator,
  Iterable<String> companies = const [],
}) {
  final group = TagCategory.creatorGroupFor(type);
  if (group == null) return const [];
  if (brandStudioOf(companies) case final brand?) {
    return [(tag: brand, category: TagCategory.studios)];
  }
  final tags = <CreatorTag>[];
  for (final name in splitCreators(creator ?? '')) {
    final lower = name.toLowerCase();
    final house = houseDirectors[lower] ?? brandStudioOf([lower]);
    final tag = house ?? slugify(name);
    if (tag.isEmpty || tags.any((t) => t.tag == tag)) continue;
    tags.add((tag: tag, category: house != null ? TagCategory.studios : group));
  }
  return tags;
}

/// How many of the billed cast Add / edit entry suggests, at most.
const maxActorTags = 3;

/// Actor tags for an entry of [type] from a lookup's billed [cast], in
/// billing order: at most [maxActorTags], movies and shows only, each in
/// the Actors group.
List<CreatorTag> actorTags({
  required MediaType type,
  Iterable<String> cast = const [],
}) {
  if (type != MediaType.movies && type != MediaType.shows) return const [];
  final tags = <CreatorTag>[];
  for (final name in cast) {
    final tag = slugify(name);
    if (tag.isEmpty || tags.any((t) => t.tag == tag)) continue;
    tags.add((tag: tag, category: TagCategory.actors));
    if (tags.length == maxActorTags) break;
  }
  return tags;
}

/// The language tag for an entry of [type] whose lookup says it is in
/// [language] (a code: "ja", "jpn"): one tag in the Languages group, or
/// none for English, for Japanese on an anime, and for a language the app
/// has no tag for (Add / edit entry › Tag picker note "Languages").
List<CreatorTag> languageTags({
  required MediaType type,
  required String? language,
}) {
  final tag = languageSuggestion(type, language);
  return tag == null ? const [] : [(tag: tag, category: TagCategory.languages)];
}

/// Streaming platforms (as TMDB names the network or the production
/// company, lowercased) and their tag in Streaming, for names that do not
/// slug to it: "Disney+" is #disney-plus, "Apple TV+" #apple-tv, "Prime
/// Video" #amazon-prime, and the platforms' film arms ("Apple Original
/// Films", "HBO Films") are the platform. A movie is a platform original only when one of these, or a
/// company that slugs to a Streaming tag the library has, is among its
/// production companies.
const streamingPlatforms = <String, String>{
  'netflix': 'netflix',
  'hbo': 'hbo',
  'hbo max': 'hbo',
  'max': 'hbo',
  'hbo films': 'hbo',
  'apple tv+': 'apple-tv',
  'apple tv': 'apple-tv',
  'apple original films': 'apple-tv',
  'apple studios': 'apple-tv',
  'disney+': 'disney-plus',
  'hulu': 'hulu',
  'prime video': 'amazon-prime',
  'amazon prime video': 'amazon-prime',
  'amazon prime': 'amazon-prime',
  'paramount+': 'paramount-plus',
  'peacock': 'peacock',
};

/// The Streaming tag for an entry of [type] (Add / edit entry › Tag picker
/// note "Streaming"): for a show, its first [network], only when it is one
/// of the library's [streaming] tags (a show that first aired on ABC gets
/// nothing); for a movie, a platform among its production [companies] (a
/// Netflix original), as a tag the library has or a new one. Nothing for
/// the other types.
List<CreatorTag> streamingTags({
  required MediaType type,
  String? network,
  Iterable<String> companies = const [],
  Iterable<String> streaming = const [],
}) {
  String? tagOf(String name) =>
      streamingPlatforms[name.trim().toLowerCase()] ??
      switch (slugify(name)) {
        final slug when streaming.contains(slug) => slug,
        _ => null,
      };
  final String? tag;
  if (type == MediaType.shows) {
    final found = network == null ? null : tagOf(network);
    tag = found != null && streaming.contains(found) ? found : null;
  } else if (type == MediaType.movies) {
    tag = companies.map(tagOf).nonNulls.firstOrNull;
  } else {
    tag = null;
  }
  return tag == null ? const [] : [(tag: tag, category: TagCategory.streaming)];
}
