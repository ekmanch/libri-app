import 'lookup_match.dart';
import 'text_clean.dart';

/// How many subjects or genres become tag suggestions; the form keeps
/// six at most.
const maxBookTags = 6;

/// Whether two book hits are the same book: the same title (as
/// [sameTitle]) and an author in common, case and punctuation aside; two
/// hits without an author need only the title.
bool sameBook(LookupMatch a, LookupMatch b) {
  if (!sameTitle(a.title, b.title)) return false;
  final left = _authorKeys(a.creator);
  final right = _authorKeys(b.creator);
  if (left.isEmpty || right.isEmpty) return left.isEmpty && right.isEmpty;
  return left.any(right.contains);
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
