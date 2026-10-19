import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';

/// The sort choices in Library › Sort menu, in menu order.
enum LibrarySort { newestAdded, titleAz, yearNewest, yearOldest, ratingHighest }

extension LibrarySortLabel on LibrarySort {
  String get label => switch (this) {
    LibrarySort.newestAdded => 'Newest added',
    LibrarySort.titleAz => 'Title, A to Z',
    LibrarySort.yearNewest => 'Year, newest first',
    LibrarySort.yearOldest => 'Year, oldest first',
    LibrarySort.ratingHighest => 'Rating, highest first',
  };
}

int _byTitle(Entry a, Entry b) =>
    a.title.toLowerCase().compareTo(b.title.toLowerCase());

/// `added` is a date, so entries added on the same day tie; the one later
/// in the library (added later, since adding appends) goes first. The
/// position map comes from the input order, which is the library's.
int Function(Entry, Entry) _byAddedDesc(Map<String, int> position) => (a, b) {
  final c = b.added.compareTo(a.added);
  if (c != 0) return c;
  final p = position[b.id]!.compareTo(position[a.id]!);
  return p != 0 ? p : _byTitle(a, b);
};

Map<String, int> _positions(List<Entry> list) => {
  for (final (i, e) in list.indexed) e.id: i,
};

/// Entries without a year go last in both year orders.
int _byYear(Entry a, Entry b, {required bool newestFirst}) {
  final ya = a.year, yb = b.year;
  if (ya == null && yb == null) return _byTitle(a, b);
  if (ya == null) return 1;
  if (yb == null) return -1;
  final c = newestFirst ? yb.compareTo(ya) : ya.compareTo(yb);
  return c != 0 ? c : _byTitle(a, b);
}

/// 10 first, down to 1; unrated entries last; ties by title. Albums and
/// songs sort by their own rating.
int _byRatingDesc(Entry a, Entry b) {
  final ra = a.rating, rb = b.rating;
  if (ra == null && rb == null) return _byTitle(a, b);
  if (ra == null) return 1;
  if (rb == null) return -1;
  final c = rb.compareTo(ra);
  return c != 0 ? c : _byTitle(a, b);
}

/// A new, sorted list.
List<Entry> sortEntries(Iterable<Entry> entries, LibrarySort sort) {
  final list = entries.toList();
  switch (sort) {
    case LibrarySort.newestAdded:
      list.sort(_byAddedDesc(_positions(list)));
    case LibrarySort.titleAz:
      list.sort(_byTitle);
    case LibrarySort.yearNewest:
      list.sort((a, b) => _byYear(a, b, newestFirst: true));
    case LibrarySort.yearOldest:
      list.sort((a, b) => _byYear(a, b, newestFirst: false));
    case LibrarySort.ratingHighest:
      list.sort(_byRatingDesc);
  }
  return list;
}

/// The order on the library home (Library › Home): In progress, then Want, then
/// Done, then DNF; newest added first within each.
List<Entry> homeOrder(Iterable<Entry> entries) {
  int rank(EntryStatus s) => switch (s) {
    EntryStatus.inProgress => 0,
    EntryStatus.want => 1,
    EntryStatus.done => 2,
    EntryStatus.dnf => 3,
  };
  final list = entries.toList();
  final byAdded = _byAddedDesc(_positions(list));
  list.sort((a, b) {
    final c = rank(a.status).compareTo(rank(b.status));
    return c != 0 ? c : byAdded(a, b);
  });
  return list;
}
