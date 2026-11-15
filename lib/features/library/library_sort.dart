import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';

/// A choice in a "Sort by" sheet (Library › Sort menu).
abstract interface class SortOption {
  String get label;
}

/// The sort choices in Library › Sort menu, in menu order. [artistAz] is
/// offered by the music list's Albums and Songs tabs only (Library › Music:
/// sort menu, albums and songs); the other lists offer [general].
enum LibrarySort implements SortOption {
  newestAdded,
  titleAz,
  artistAz,
  yearNewest,
  yearOldest,
  ratingHighest;

  /// The choices every list has.
  static const general = [
    newestAdded,
    titleAz,
    yearNewest,
    yearOldest,
    ratingHighest,
  ];

  @override
  String get label => switch (this) {
    newestAdded => 'Newest added',
    titleAz => 'Title, A to Z',
    artistAz => 'Artist, A to Z',
    yearNewest => 'Year, newest first',
    yearOldest => 'Year, oldest first',
    ratingHighest => 'Rating, highest first',
  };
}

/// Today's "Compilations"; pinned at the very end of anything in artist
/// order, after Z.
const variousArtistsName = 'Various Artists';

/// Entries without a creator are listed under this name.
const unknownArtistName = 'Unknown artist';

/// The artist an entry is listed under.
String artistNameOf(Entry entry) {
  final name = (entry.creator ?? '').trim();
  return name.isEmpty ? unknownArtistName : name;
}

bool isVariousArtists(String name) =>
    name.trim().toLowerCase() == variousArtistsName.toLowerCase();

/// The key artists sort by: lowercase, without a leading "The".
String artistSortKey(String name) {
  var key = name.trim().toLowerCase();
  if (key.startsWith('the ')) key = key.substring(4).trimLeft();
  return key;
}

/// The order of artists by name: [artistSortKey], "Various Artists" last.
int compareArtistNames(String a, String b) {
  final va = isVariousArtists(a), vb = isVariousArtists(b);
  if (va != vb) return va ? 1 : -1;
  final c = artistSortKey(a).compareTo(artistSortKey(b));
  return c != 0 ? c : a.compareTo(b);
}

int _byTitle(Entry a, Entry b) => compareTitles(a.title, b.title);

/// The order of Title, A to Z, for anything with a title (entries, and the
/// series rows named after their series).
int compareTitles(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

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

/// By artist ([compareArtistNames]), then by year within an artist, oldest
/// first (Library › Music: albums, sorted by artist). Names that differ only
/// in case are one artist, as in the Artists tab.
int _byArtist(Entry a, Entry b) {
  final na = artistNameOf(a), nb = artistNameOf(b);
  if (na.toLowerCase() != nb.toLowerCase()) return compareArtistNames(na, nb);
  return _byYear(a, b, newestFirst: false);
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
    case LibrarySort.artistAz:
      list.sort(_byArtist);
    case LibrarySort.yearNewest:
      list.sort((a, b) => _byYear(a, b, newestFirst: true));
    case LibrarySort.yearOldest:
      list.sort((a, b) => _byYear(a, b, newestFirst: false));
    case LibrarySort.ratingHighest:
      list.sort(_byRatingDesc);
  }
  return list;
}

/// The order of search hits (Library › Search), the home's old order: In
/// progress, then Want, then Done, then DNF; newest added first within each.
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
