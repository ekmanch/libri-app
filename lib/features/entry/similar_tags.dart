/// Tag names as typed are cleaned up and checked against the existing tags
/// before a new one is created (DESIGN.md section 7).
library;

import '../../data/models/entry_id.dart';

/// A tag is lowercase ASCII letters, digits and hyphens; a dot only
/// between two digits ("2.5d"); and "&" only between two letters or digits
/// ("r&b", "drum&bass"), so never at an end, doubled, or beside a hyphen
/// or a dot. The data repo's `library.py` checks the same rule.
///
/// Drops a leading "#", lowercases, folds diacritics, drops apostrophes,
/// turns every run of other characters into one hyphen and trims the
/// ends. What the "&" rule forbids is cleaned up rather than refused: the
/// spaces and hyphens around an "&" go ("R & B" is "r&b", "rock -&- roll"
/// is "rock&roll"), "&&" is one "&", and an "&" at an end is dropped.
String normalizeTag(String raw) {
  var name = raw.trim();
  if (name.startsWith('#')) name = name.substring(1);
  return foldToAscii(name)
      .replaceAll(_outsideTag, '-')
      .replaceAll(_aroundAmpersand, '&')
      .replaceAll(_tagEnds, '');
}

/// A run of characters a tag cannot hold: anything but a letter, a digit,
/// an "&" or a dot, and a dot not between two digits.
final _outsideTag = RegExp(r'(?:[^a-z0-9.&]|(?<![0-9])\.|\.(?![0-9]))+');

/// An "&" with the hyphens and further "&"s around it.
final _aroundAmpersand = RegExp('-*&[-&]*');

final _tagEnds = RegExp(r'^[-&]+|[-&]+$');

/// Whether [tag] holds [q], a query in lower case: as typed, or with the
/// spaces around an "&" dropped, so "r & b" finds "r&b". The one way a
/// tag's name is searched, wherever tags are listed.
bool tagContains(String tag, String q) {
  if (tag.contains(q)) return true;
  if (!q.contains('&')) return false;
  final joined = q
      .replaceAll(RegExp(r'\s*&\s*'), '&')
      .replaceAll(RegExp(r'^&+|&+$'), '');
  return joined.isNotEmpty && tag.contains(joined);
}

/// The library's spelling of a genre a lookup names another way:
/// "science-fiction" is "scifi". Applied to a lookup's suggestions before
/// they are matched against the existing tags, so a synonym is never
/// offered as a new tag beside the one that is there.
const tagAliases = <String, String>{
  'science-fiction': 'scifi',
  'sci-fi': 'scifi',
  'sf': 'scifi',
  'science-fiction-fiction': 'scifi',
  'fantasy-fiction': 'fantasy',
  'horror-fiction': 'horror',
  'horror-tales': 'horror',
  'horror-stories': 'horror',
  'comedies': 'comedy',
  'comedy-films': 'comedy',
  'thrillers': 'thriller',
  'thriller-fiction': 'thriller',
  'mystery-fiction': 'mystery',
  'detective-and-mystery-stories': 'mystery',
  'romance-fiction': 'romance',
  'love-stories': 'romance',
  'role-playing-rpg': 'rpg',
  'role-playing': 'rpg',
  'platform': 'platformer',
  'hack-and-slash-beat-em-up': 'hack-and-slash',
  'turn-based-strategy-tbs': 'strategy',
  'real-time-strategy-rts': 'strategy',
  'slice-of-life': 'slice-of-life',
  // Deezer's "Rap/Hip Hop", and the spellings other catalogs use.
  'rap-hip-hop': 'hiphop',
  'hip-hop-rap': 'hiphop',
  'hip-hop': 'hiphop',
  // Deezer's genres in Swedish, as it named them by the caller's country
  // before the lookup asked for English, and "Film Scores".
  'alternativmusik': 'alternative',
  'filmmusik': 'movie-music',
  'film-scores': 'movie-music',
  'electro': 'electronic',
};

/// [normalizeTag] with any brackets dropped ("Role-playing (RPG)"), then
/// the library's spelling when [tagAliases] has one.
String canonicalTag(String raw) {
  final name = normalizeTag(raw.replaceAll(RegExp(r'[()\[\]]'), ' '));
  // The aliases are spelled with hyphens: "Rap & Hip Hop" is "rap-hip-hop".
  return tagAliases[name] ?? tagAliases[name.replaceAll('&', '-')] ?? name;
}

/// A lookup's genre as the tags to offer for it: [canonicalTag], or, when
/// [existing] has neither that tag nor one like it but has every tag the
/// name is made of, those instead: "Indie Pop" is #indie and #pop, "Indie
/// Rock/Rock pop" is #indie, #rock and #pop. A name with a word the
/// library has no tag for stays whole.
List<String> libraryTags(String raw, Set<String> existing) {
  final name = canonicalTag(raw);
  if (existing.contains(name) || findSimilarTag(name, existing) != null) {
    return [name];
  }
  // The words, split at hyphens and "&"s: "sci-fi&fantasy" is #scifi and
  // #fantasy. A run of them keeps what joins it, so #r&b is found whole.
  final words = RegExp('[^-&]+').allMatches(name).toList();
  final tags = <String>[];
  var start = 0;
  while (start < words.length) {
    // The longest run of words that is a tag, so "hack-and-slash" is found
    // before "hack".
    String? tag;
    var end = words.length;
    for (; end > start; end--) {
      final run = name.substring(words[start].start, words[end - 1].end);
      final candidate =
          tagAliases[run] ?? tagAliases[run.replaceAll('&', '-')] ?? run;
      if (existing.contains(candidate)) {
        tag = candidate;
        break;
      }
    }
    if (tag == null) return [name];
    if (!tags.contains(tag)) tags.add(tag);
    start = end;
  }
  return tags;
}

/// The existing tag most like [candidate], or null when none is close.
///
/// Two names are similar when they are the same once hyphens and dots are
/// ignored and an "&" read as "and" or as nothing ("r&b" beside "r-and-b"
/// or "r-b", see [_readings]), when one is the plural of the other, or
/// when they are one edit apart (two for a candidate of six letters or
/// more): a letter changed, added or dropped, or two neighboring letters
/// swapped. An exact match is not similar, it is the same tag.
String? findSimilarTag(String candidate, Iterable<String> existing) {
  final name = normalizeTag(candidate);
  if (name.isEmpty) return null;
  String? best;
  var bestRank = 1 << 30;
  for (final other in existing) {
    if (other == name) continue;
    final rank = _similarityRank(name, other);
    if (rank != null && rank < bestRank) {
      best = other;
      bestRank = rank;
    }
  }
  return best;
}

/// Lower is closer; null means not similar.
int? _similarityRank(String a, String b) {
  final readings = _readings(b);
  if (_readings(a).any(readings.contains)) return 0;
  if (_isPluralOf(a, b) || _isPluralOf(b, a)) return 1;
  final limit = a.length >= 6 ? 2 : 1;
  final distance = _editDistance(a, b);
  return distance <= limit ? 1 + distance : null;
}

/// The ways [tag] reads with its hyphens and dots ignored: its "&" left
/// out and spelled "and", as on the desktop (`similarity_rank` in
/// libri-kde's `text.rs`). So "r&b" reads "rb" and "randb", and meets
/// "r-b" and "r-and-b"; "rnb" is one edit from it. A tag without an "&"
/// reads one way.
Set<String> _readings(String tag) {
  final plain = tag.replaceAll(_joiners, '');
  return {plain.replaceAll('&', ''), plain.replaceAll('&', 'and')};
}

final _joiners = RegExp('[-.]');

bool _isPluralOf(String plural, String singular) {
  if (plural == '${singular}s' || plural == '${singular}es') return true;
  return singular.endsWith('y') &&
      plural == '${singular.substring(0, singular.length - 1)}ies';
}

/// Optimal string alignment distance: substitutions, insertions, deletions
/// and adjacent transpositions each cost one.
int _editDistance(String a, String b) {
  final rows = a.length + 1;
  final cols = b.length + 1;
  final d = List.generate(rows, (i) => List<int>.filled(cols, 0));
  for (var i = 0; i < rows; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j < cols; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i < rows; i++) {
    for (var j = 1; j < cols; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
      if (d[i - 1][j - 1] + cost < best) best = d[i - 1][j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          d[i - 2][j - 2] + 1 < best) {
        best = d[i - 2][j - 2] + 1;
      }
      d[i][j] = best;
    }
  }
  return d[a.length][b.length];
}
