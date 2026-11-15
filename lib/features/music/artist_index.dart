import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../data/models/entry_kind.dart';
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

  /// "7 albums, 2 songs", "1 song".
  String get countLabel => albumsAndSongsLabel(albums.length, songs.length);

  /// Up to two initials for the photo placeholder: "AC" for Alice in Chains.
  String get initials {
    final words = name
        .replaceAll('&', '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return (words[0][0] + (words.length > 1 ? words[1][0] : '')).toUpperCase();
  }
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

/// Letter sections for the artist list by name and its rail (Library › Music:
/// artists, text view; Long list: music artists A–Z). "Various Artists" gets
/// its own last section. The other orders are one list with no sections.
List<ListSection<ArtistSummary>> artistSections(List<ArtistSummary> artists) {
  final sections = <ListSection<ArtistSummary>>[];
  ListSection<ArtistSummary>? open;
  for (final artist in artists) {
    final label = artist.isVariousArtists
        ? ArtistSummary.variousArtists
        : artistLetter(artist.name);
    if (open == null || open.label != label) {
      open = ListSection(
        label: label,
        railLabel: artist.isVariousArtists ? 'VA' : label,
        bubbleLabel: label,
        items: [],
      );
      sections.add(open);
    }
    open.items.add(artist);
  }
  return sections;
}
