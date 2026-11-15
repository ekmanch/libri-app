import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../data/models/entry_kind.dart';
import '../../widgets/artist_photo.dart' show artistInitials;
import '../../widgets/labels.dart';
import '../library/entry_sections.dart';
import '../library/library_sort.dart';
import '../library/library_sort.dart' as names show isVariousArtists;
import '../library/sectioned_list_body.dart';

/// The orders of the music list's Artists tab, in menu order (Library ›
/// Music: sort menu, artists).
enum ArtistsSort implements SortOption {
  nameAz,
  newestAdded,
  mostAlbums,
  mostSongs;

  @override
  String get label => switch (this) {
    nameAz => 'Name, A to Z',
    newestAdded => 'Newest added',
    mostAlbums => 'Most albums',
    mostSongs => 'Most songs',
  };
}

/// One artist in the music list (Library › Music: artists, text view): the
/// albums and songs saved under that name. Albums and songs are in year order,
/// oldest first.
class ArtistSummary {
  const ArtistSummary({
    required this.name,
    required this.albums,
    required this.songs,
  });

  final String name;
  final List<Entry> albums;
  final List<Entry> songs;

  /// Today's "Compilations"; pinned at the very end of the list, after Z.
  static const variousArtists = variousArtistsName;

  /// Entries without a creator are grouped under this name.
  static const unknownArtist = unknownArtistName;

  bool get isVariousArtists => names.isVariousArtists(name);

  /// The day the artist's most recently added album or song was added.
  DateTime get newestAdded => [
    ...albums,
    ...songs,
  ].map((e) => e.added).reduce((a, b) => a.isAfter(b) ? a : b);

  /// "7 albums, 2 songs", "1 song".
  String get countLabel => albumsAndSongsLabel(albums.length, songs.length);

  /// Up to two initials for the photo placeholder: "AC" for Alice in Chains.
  String get initials => artistInitials(name);
}

/// The letter an artist is listed under, "#" for names starting with a
/// digit or anything else that is not a letter.
String artistLetter(String name) => titleLetter(artistSortKey(name));

/// Groups music entries, given in the library's order, by artist. Names
/// that differ only in case are one artist.
///
/// By name ([ArtistsSort.nameAz], the default) the artists follow
/// [artistSortKey] with "Various Artists" last. Newest added goes by the
/// artist's most recently added album or song, with the later one in the
/// library first for those added on the same day, as in the entry lists. Most
/// albums and Most songs go by how many are saved, ties by name; a song is a
/// saved song entry, never a track rated on an album.
List<ArtistSummary> artistIndex(
  Iterable<Entry> entries, {
  ArtistsSort sort = ArtistsSort.nameAz,
}) {
  final byKey = <String, List<Entry>>{};
  final displayName = <String, String>{};
  // The artist's newest entry: its day added and its place in the library.
  final newest = <String, (DateTime, int)>{};
  var position = 0;
  for (final entry in entries) {
    position++;
    if (entry.type != MediaType.music) continue;
    final name = artistNameOf(entry);
    final key = name.toLowerCase();
    displayName.putIfAbsent(key, () => name);
    byKey.putIfAbsent(key, () => []).add(entry);
    final best = newest[key];
    if (best == null || !entry.added.isBefore(best.$1)) {
      newest[key] = (entry.added, position);
    }
  }
  final artists = [
    for (final MapEntry(key: key, value: list) in byKey.entries)
      ArtistSummary(
        name: displayName[key]!,
        albums: sortEntries(
          list.where((e) => e.kind != EntryKind.song),
          LibrarySort.yearOldest,
        ),
        songs: sortEntries(
          list.where((e) => e.kind == EntryKind.song),
          LibrarySort.yearOldest,
        ),
      ),
  ];
  int byName(ArtistSummary a, ArtistSummary b) =>
      compareArtistNames(a.name, b.name);
  int Function(ArtistSummary, ArtistSummary) byCount(
    int Function(ArtistSummary artist) countOf,
  ) => (a, b) {
    final c = countOf(b).compareTo(countOf(a));
    return c != 0 ? c : byName(a, b);
  };
  artists.sort(switch (sort) {
    ArtistsSort.nameAz => byName,
    ArtistsSort.newestAdded => (a, b) {
      final na = newest[a.name.toLowerCase()]!;
      final nb = newest[b.name.toLowerCase()]!;
      final c = nb.$1.compareTo(na.$1);
      return c != 0 ? c : nb.$2.compareTo(na.$2);
    },
    ArtistsSort.mostAlbums => byCount((a) => a.albums.length),
    ArtistsSort.mostSongs => byCount((a) => a.songs.length),
  });
  return artists;
}

/// The sections of the artist list and its rail, which follow the sort
/// (Library › Music: sort menu, artists; the n_musicsort and n_rail notes):
/// letters by name, with "Various Artists" its own last section; the months
/// added, as in the entry lists, for newest added; the counts, highest first,
/// for most albums and most songs, with the artists that have none under "No
/// albums" or "No songs" at the end.
List<ListSection<ArtistSummary>> artistSections(
  List<ArtistSummary> artists, {
  ArtistsSort sort = ArtistsSort.nameAz,
  DateTime? today,
}) {
  switch (sort) {
    case ArtistsSort.nameAz:
      return sectionsBy(artists, (artist) {
        if (artist.isVariousArtists) {
          return (
            label: ArtistSummary.variousArtists,
            railLabel: 'VA',
            bubbleLabel: ArtistSummary.variousArtists,
          );
        }
        final letter = artistLetter(artist.name);
        return (label: letter, railLabel: letter, bubbleLabel: letter);
      });
    case ArtistsSort.newestAdded:
      final now = today ?? DateTime.now();
      return mergeOldestAdded<ArtistSummary, ListSection<ArtistSummary>>(
        sectionsBy(
          artists,
          (artist) => addedSectionLabels(artist.newestAdded, now),
        ),
        (items) => ListSection(
          label: olderAddedLabel,
          railLabel: olderAddedLabel,
          bubbleLabel: olderAddedLabel,
          items: items,
        ),
      );
    case ArtistsSort.mostAlbums:
      return _countSections(artists, (a) => a.albums.length, 'album');
    case ArtistsSort.mostSongs:
      return _countSections(artists, (a) => a.songs.length, 'song');
  }
}

/// Sections by how many [noun]s an artist has, for a list already in that
/// order: every count on its own while that fits the rail ([maxRailLabels]),
/// otherwise 1 to 10 one by one and ranges above.
List<ListSection<ArtistSummary>> _countSections(
  List<ArtistSummary> artists,
  int Function(ArtistSummary artist) countOf,
  String noun,
) {
  final exact = sectionsBy(
    artists,
    (artist) => _countLabels(countOf(artist), noun, ranges: false),
  );
  if (exact.length <= maxRailLabels) return exact;
  return sectionsBy(
    artists,
    (artist) => _countLabels(countOf(artist), noun, ranges: true),
  );
}

/// "16 albums" ("16" on the rail), "1 song", "No albums" ("None", as the
/// rail is too narrow for more); with [ranges], "11–15 albums" to "Over 50
/// albums" ("50+") above ten.
SectionLabels _countLabels(int count, String noun, {required bool ranges}) {
  if (count == 0) {
    final label = 'No ${noun}s';
    return (label: label, railLabel: 'None', bubbleLabel: label);
  }
  if (ranges && count > 50) {
    final label = 'Over 50 ${noun}s';
    return (label: label, railLabel: '50+', bubbleLabel: label);
  }
  final short = !ranges || count <= 10
      ? '$count'
      : count <= 15
      ? '11–15'
      : count <= 20
      ? '16–20'
      : count <= 30
      ? '21–30'
      : '31–50';
  final label = '$short ${count == 1 ? noun : '${noun}s'}';
  return (label: label, railLabel: short, bubbleLabel: label);
}
