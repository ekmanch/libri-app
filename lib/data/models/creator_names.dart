import 'entry_id.dart';
import 'library.dart';

/// "Stephen King" for #stephen-king: the creator text of an entry that
/// carries the tag and whose creator slugs to it, so the name keeps its
/// dots and accents ("Ursula K. Le Guin", "Jo Nesbø"); else the tag's words
/// with capitals ("Mike Flanagan", "Team Cherry"). Used by the tag lists
/// (Library › Filter: all Authors) and the follows (Settings › Follow: authors).
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
