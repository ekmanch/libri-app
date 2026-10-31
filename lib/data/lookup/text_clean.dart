/// Plain text from the HTML-ish descriptions AniList, Apple Books and
/// Google Books return: tags dropped, `<br>` and paragraph ends become line breaks,
/// common entities decoded, whitespace collapsed.
String stripHtml(String html) {
  var text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>|</div>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAll('\u00a0', ' ')
      .replaceAll('&amp;', '&');
  text = text
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

/// Whether two titles are the same once case, punctuation, diacritics and
/// a leading "The" are set aside: "Salem's Lot" is "Salems lot", "The
/// Mummy" is "Mummy".
bool sameTitle(String a, String b) => titleKey(a) == titleKey(b);

/// What [sameTitle] compares: the title lowercased, without punctuation,
/// spaces or a leading "The". Two titles with the same key are the same.
String titleKey(String title) {
  var key = title
      .toLowerCase()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  if (key.startsWith('the ')) key = key.substring(4);
  return key.replaceAll(' ', '');
}

/// Edition notes a provider tacks on: "Dirt (2022 Remaster)", "Rooster -
/// Remastered", "Dune [Deluxe Edition]". [looseTitle] drops them.
final _editionNote = RegExp(
  r'\s*[\(\[][^\)\]]*\b(remaster(ed)?|edition|deluxe|expanded|anniversary|'
  r'version|bonus|explicit|live|mono|stereo|re-?issue|special)\b[^\)\]]*[\)\]]'
  r'|\s+-\s+(remaster(ed)?|\d{4} remaster(ed)?|live|mono|stereo)\b.*$',
  caseSensitive: false,
);

/// The title without an edition note at its end.
String looseTitle(String title) => title.replaceAll(_editionNote, '').trim();

/// Whether two titles are the same once edition notes are set aside too.
bool sameLooseTitle(String a, String b) =>
    sameTitle(looseTitle(a), looseTitle(b));

/// The key a stored track rating is matched to a listed track by, when
/// their ids differ: the title without case, punctuation or an edition
/// note.
String trackTitleKey(String title) => titleKey(looseTitle(title));

/// The one hit for an entry: the same title in the same year; else the
/// same title a year off (a festival run, a late release); else, when no
/// year is known, the first with the same title; else, with edition notes
/// set aside, the same again. Nothing when the title is not there.
T? pickByTitleAndYear<T>(
  List<T> hits,
  String title, {
  required int? year,
  required String Function(T) titleOf,
  required int? Function(T) yearOf,
}) {
  for (final same in [sameTitle, sameLooseTitle]) {
    final matches = [
      for (final h in hits)
        if (same(titleOf(h), title)) h,
    ];
    if (matches.isEmpty) continue;
    if (year == null) return matches.first;
    for (final h in matches) {
      if (yearOf(h) == year) return h;
    }
    for (final h in matches) {
      final y = yearOf(h);
      if (y != null && (y - year).abs() <= 1) return h;
    }
  }
  return null;
}

/// Whether a book subject or category makes sense as a tag. Open Library's
/// subjects mix genres with catalog notes ("Fiction, science fiction,
/// general"), pseudo-tags ("award:hugo_award=1960") and long headings; only
/// short plain ones do.
bool isTagLike(String subject) =>
    subject.length <= 24 &&
    !subject.contains(RegExp(r'[:=,(){}\[\]/]')) &&
    subject.trim().split(RegExp(r'\s+')).length <= 3;

/// The writing system most of [text]'s letters are in: "latin",
/// "cyrillic", "greek", "cjk" (kana and Chinese characters), "hangul",
/// "arabic", "hebrew", "other", or null when it has no letters. Digits and
/// punctuation do not count.
String? scriptOf(String text) {
  final counts = <String, int>{};
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (!_letter.hasMatch(ch)) continue;
    final script = switch (rune) {
      < 0x0250 => 'latin',
      >= 0x1E00 && < 0x1F00 => 'latin',
      >= 0x0370 && < 0x0400 => 'greek',
      >= 0x1F00 && < 0x2000 => 'greek',
      >= 0x0400 && < 0x0530 => 'cyrillic',
      >= 0x0590 && < 0x0600 => 'hebrew',
      >= 0x0600 && < 0x0780 => 'arabic',
      >= 0x1100 && < 0x1200 => 'hangul',
      >= 0xAC00 && < 0xD7B0 => 'hangul',
      >= 0x3040 && < 0x3100 => 'cjk',
      >= 0x3400 && < 0xA000 => 'cjk',
      >= 0xF900 && < 0xFB00 => 'cjk',
      >= 0xFF66 && < 0xFFA0 => 'cjk',
      >= 0x20000 && < 0x30000 => 'cjk',
      _ => 'other',
    };
    counts[script] = (counts[script] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

final _letter = RegExp(r'\p{L}', unicode: true);

/// Whether [a] and [b] are written in different scripts ([scriptOf]); a
/// text without letters differs from none.
bool otherScript(String a, String b) {
  final sa = scriptOf(a), sb = scriptOf(b);
  return sa != null && sb != null && sa != sb;
}
