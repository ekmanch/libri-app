import 'media_type.dart';

/// Entry ids are slugs frozen at creation: `movies/the-mummy-1999`,
/// `books/dracula-1897`, `music/dirt-alice-in-chains`. Editing a title never
/// changes the id, so plan items keep pointing at the right entry.
///
/// This is the one id scheme: the data repo's migration assigned every
/// existing id with [generate] too, so the app and the data never disagree.
class EntryId {
  EntryId._();

  /// Builds a new id and makes it unique among [existingIds] by appending
  /// "-2", "-3" and so on.
  ///
  /// Music uses the artist as the suffix, every other type (books included)
  /// uses the year.
  static String generate({
    required MediaType type,
    required String title,
    String? year,
    String? artist,
    required Iterable<String> existingIds,
  }) {
    final suffix = type == MediaType.music ? artist : year;
    final parts = [
      slugify(title),
      if (suffix != null) slugify(suffix),
    ].where((p) => p.isNotEmpty).join('-');
    final base = '${type.name}/${parts.isEmpty ? 'untitled' : parts}';
    return unique(base, existingIds);
  }

  /// Returns [base] if unused, otherwise the first free "$base-2", "$base-3".
  static String unique(String base, Iterable<String> existingIds) {
    final existing = existingIds.toSet();
    if (!existing.contains(base)) return base;
    for (var n = 2; ; n++) {
      final candidate = '$base-$n';
      if (!existing.contains(candidate)) return candidate;
    }
  }
}

const _diacritics = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ð': 'd',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'þ': 'th',
  'ß': 'ss',
  'ł': 'l',
  'ś': 's',
  'ż': 'z',
  'ź': 'z',
  'ć': 'c',
  'ń': 'n',
  'č': 'c',
  'š': 's',
  'ž': 'z',
  'ř': 'r',
  'ě': 'e',
  'ů': 'u',
  'ő': 'o',
  'ű': 'u',
  'ı': 'i',
  'ğ': 'g',
  'ş': 's',
  'œ': 'oe',
  'ā': 'a',
  'ē': 'e',
  'ī': 'i',
  'ō': 'o',
  'ū': 'u',
  'ă': 'a',
  'ą': 'a',
  'ę': 'e',
  'ė': 'e',
  'į': 'i',
  'ų': 'u',
  'ļ': 'l',
  'ņ': 'n',
  'ķ': 'k',
  'ģ': 'g',
  'ț': 't',
  'ș': 's',
  'đ': 'd',
};

/// Lowercases, drops apostrophes ("Salem's Lot" becomes `salems-lot`), folds
/// common Latin diacritics to ASCII, turns every run of other characters into
/// one hyphen and trims hyphens from the ends.
String slugify(String text) {
  return foldToAscii(text)
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Lowercases, drops apostrophes and folds common Latin diacritics to ASCII;
/// every other character is kept.
String foldToAscii(String text) => text
    .toLowerCase()
    .replaceAll(_apostrophes, '')
    .split('')
    .map((c) => _diacritics[c] ?? c)
    .join();

final _apostrophes = RegExp("['’`]");
