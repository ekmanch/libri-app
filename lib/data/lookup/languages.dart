import '../models/media_type.dart';

/// The tag a language code names (#japanese for "ja"), for the Languages
/// tag category (Add / edit entry › Tag picker note "Languages"). Keyed by
/// the two-letter ISO 639-1 codes TMDB and IGDB use and the three-letter
/// ISO 639-2 codes Open Library uses (both the bibliographic and the
/// terminology form where they differ). A code not listed names no tag.
const languageTags = <String, String>{
  'ar': 'arabic',
  'ara': 'arabic',
  'bg': 'bulgarian',
  'bul': 'bulgarian',
  'bn': 'bengali',
  'ben': 'bengali',
  'ca': 'catalan',
  'cat': 'catalan',
  'cs': 'czech',
  'ces': 'czech',
  'cze': 'czech',
  'da': 'danish',
  'dan': 'danish',
  'de': 'german',
  'deu': 'german',
  'ger': 'german',
  'el': 'greek',
  'ell': 'greek',
  'gre': 'greek',
  'en': 'english',
  'eng': 'english',
  'es': 'spanish',
  'spa': 'spanish',
  'et': 'estonian',
  'est': 'estonian',
  'fa': 'persian',
  'fas': 'persian',
  'per': 'persian',
  'fi': 'finnish',
  'fin': 'finnish',
  'fr': 'french',
  'fra': 'french',
  'fre': 'french',
  'he': 'hebrew',
  'heb': 'hebrew',
  'hi': 'hindi',
  'hin': 'hindi',
  'hr': 'croatian',
  'hrv': 'croatian',
  'hu': 'hungarian',
  'hun': 'hungarian',
  'id': 'indonesian',
  'ind': 'indonesian',
  'is': 'icelandic',
  'isl': 'icelandic',
  'ice': 'icelandic',
  'it': 'italian',
  'ita': 'italian',
  'ja': 'japanese',
  'jpn': 'japanese',
  'ko': 'korean',
  'kor': 'korean',
  'la': 'latin',
  'lat': 'latin',
  'lt': 'lithuanian',
  'lit': 'lithuanian',
  'lv': 'latvian',
  'lav': 'latvian',
  'nb': 'norwegian',
  'nob': 'norwegian',
  'nl': 'dutch',
  'nld': 'dutch',
  'dut': 'dutch',
  'nn': 'norwegian',
  'nno': 'norwegian',
  'no': 'norwegian',
  'nor': 'norwegian',
  'pl': 'polish',
  'pol': 'polish',
  'pt': 'portuguese',
  'por': 'portuguese',
  'ro': 'romanian',
  'ron': 'romanian',
  'rum': 'romanian',
  'ru': 'russian',
  'rus': 'russian',
  'sk': 'slovak',
  'slk': 'slovak',
  'slo': 'slovak',
  'sl': 'slovenian',
  'slv': 'slovenian',
  'sr': 'serbian',
  'srp': 'serbian',
  'sv': 'swedish',
  'swe': 'swedish',
  'sw': 'swahili',
  'swa': 'swahili',
  'ta': 'tamil',
  'tam': 'tamil',
  'th': 'thai',
  'tha': 'thai',
  'tl': 'tagalog',
  'tgl': 'tagalog',
  'tr': 'turkish',
  'tur': 'turkish',
  'uk': 'ukrainian',
  'ukr': 'ukrainian',
  'vi': 'vietnamese',
  'vie': 'vietnamese',
  'zh': 'chinese',
  'zho': 'chinese',
  'chi': 'chinese',
  'cn': 'chinese',
};

/// The tag for a language [code] as a lookup gives it ("ja", "jpn",
/// "ja-JP", "en-US"), or null for an unknown or empty code.
String? languageTag(String? code) {
  if (code == null) return null;
  final base = code.trim().toLowerCase().split(RegExp(r'[-_]')).first;
  return languageTags[base];
}

/// The language tag Add / edit entry suggests for an entry of [type] whose
/// lookup says it is in [code]: none for English, which nearly everything
/// is in, and none for Japanese on an anime, for the same reason.
String? languageSuggestion(MediaType type, String? code) {
  final tag = languageTag(code);
  if (tag == null || tag == 'english') return null;
  if (type == MediaType.anime && tag == 'japanese') return null;
  return tag;
}

/// The language of an AniList entry from its country of origin: Japan,
/// Korea, China and Taiwan are where nearly every anime, manhwa and donghua
/// come from; anywhere else says nothing.
String? languageOfCountry(String? country) => switch (country?.toUpperCase()) {
  'JP' => 'ja',
  'KR' => 'ko',
  'CN' || 'TW' => 'zh',
  _ => null,
};
