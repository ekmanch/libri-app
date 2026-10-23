import 'lookup_match.dart';
import 'text_clean.dart';

/// How many subjects or genres become tag suggestions; the form keeps
/// six at most.
const maxBookTags = 6;

/// Whether two book hits are the same book: the same title (as
/// [sameTitle]) and an author in common, case and punctuation aside; two
/// hits without an author need only the title.
bool sameBook(LookupMatch a, LookupMatch b) =>
    sameTitle(a.title, b.title) && shareAuthor(a.creator, b.creator);

/// Whether two creator lines ("James Clavell", "A, B") name an author in
/// common, case and punctuation aside; two without an author count as
/// sharing one.
bool shareAuthor(String? a, String? b) {
  final left = _authorKeys(a);
  final right = _authorKeys(b);
  if (left.isEmpty || right.isEmpty) return left.isEmpty && right.isEmpty;
  return left.any(right.contains);
}

/// The edition a book's cover is of, as Add / edit entry › Pick a cover
/// captions it: a tie-in from the title ("Shōgun (TV Tie-in)" is a "TV
/// tie-in"), else Open Library's physical format ("Mass Market Paperback"
/// reads "Paperback"), else [fallback] ("Ebook" for Apple Books). Null
/// when nothing says.
String? editionLabel(String title, {String? format, String? fallback}) {
  if (RegExp(r'tie[- ]?in', caseSensitive: false).hasMatch(title)) {
    if (RegExp(
      r'\b(tv|television|series|netflix|hbo|fx)\b',
      caseSensitive: false,
    ).hasMatch(title)) {
      return 'TV tie-in';
    }
    if (RegExp(r'\b(movie|film)\b', caseSensitive: false).hasMatch(title)) {
      return 'Movie tie-in';
    }
    return 'Tie-in';
  }
  final f = format?.toLowerCase() ?? '';
  if (f.contains('hardcover') || f.contains('hardback')) return 'Hardcover';
  if (f.contains('paperback') || f.contains('softcover')) return 'Paperback';
  if (f.contains('audio')) return 'Audiobook';
  if (f.contains('ebook') || f.contains('e-book') || f.contains('electronic')) {
    return 'Ebook';
  }
  return fallback;
}

Set<String> _authorKeys(String? creator) => {
  for (final name in (creator ?? '').split(','))
    if (name.trim().isNotEmpty)
      name.toLowerCase().replaceAll(
        RegExp(r'[^\p{L}\p{N}]+', unicode: true),
        '',
      ),
};

/// The first publication year among a work's edition years, as Open
/// Library lists them (`publish_year`): the earliest, except that a year
/// more than [gap] years before the next is taken as a mis-dated edition
/// and skipped while the years after it still have two within [gap] of
/// each other. "King Rat" (1962) lists a 1950 edition that is nothing of
/// the kind; a book with one edition, or with editions decades apart,
/// keeps its earliest year. Null without years.
int? firstPublishYear(Iterable<int> years, {int gap = 10}) {
  final sorted = years.toSet().toList()..sort();
  for (var i = 0; i < sorted.length; i++) {
    if (i == sorted.length - 1 || sorted[i + 1] - sorted[i] <= gap) {
      return sorted[i];
    }
    var run = false;
    for (var j = i + 1; j + 1 < sorted.length; j++) {
      if (sorted[j + 1] - sorted[j] <= gap) {
        run = true;
        break;
      }
    }
    if (!run) return sorted[i];
  }
  return null;
}

/// A manga or comic volume number in a title: "Berserk, Vol. 43", "Berserk
/// Volume 43", "Berserk #43" give the series "Berserk" and 43. Null when the
/// title has none.
({String name, int number})? volumeOf(String title) {
  final match = _volume.firstMatch(title);
  if (match == null) return null;
  final name = match.group(1)!.replaceAll(RegExp(r'[\s,:–-]+$'), '').trim();
  final number = int.tryParse(match.group(2)!);
  if (name.isEmpty || number == null) return null;
  return (name: name, number: number);
}

final _volume = RegExp(
  r'^(.+?)[\s,:–-]+(?:vol\.?|volume|#)\s*(\d+)\b',
  caseSensitive: false,
);
