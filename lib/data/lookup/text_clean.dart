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
bool sameTitle(String a, String b) => _titleKey(a) == _titleKey(b);

String _titleKey(String title) {
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
String trackTitleKey(String title) => _titleKey(looseTitle(title));

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
