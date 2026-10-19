import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../data/models/music_kind.dart';
import '../../data/models/track.dart';
import '../../widgets/labels.dart';
import '../library/entry_sections.dart';
import '../library/library_sort.dart';
import '../library/sectioned_list_body.dart';

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
  static const variousArtists = 'Various Artists';

  /// Entries without a creator are grouped under this name.
  static const unknownArtist = 'Unknown artist';

  bool get isVariousArtists =>
      name.toLowerCase() == variousArtists.toLowerCase();

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

  /// Rated tracks on this artist's albums, with the album each is on.
  List<(Entry album, Track track)> get ratedTracks => [
    for (final album in albums)
      for (final track in album.tracks ?? const <Track>[]) (album, track),
  ];
}

/// The key artists sort by: lowercase, without a leading "The".
String artistSortKey(String name) {
  var key = name.trim().toLowerCase();
  if (key.startsWith('the ')) key = key.substring(4).trimLeft();
  return key;
}

/// The letter an artist is listed under, "#" for names starting with a
/// digit or anything else that is not a letter.
String artistLetter(String name) => titleLetter(artistSortKey(name));

/// Groups music entries by artist, sorted by [artistSortKey] with
/// "Various Artists" last. Names that differ only in case are one artist.
List<ArtistSummary> artistIndex(Iterable<Entry> entries) {
  final byKey = <String, List<Entry>>{};
  final displayName = <String, String>{};
  for (final entry in entries) {
    if (entry.type != MediaType.music) continue;
    final raw = (entry.creator ?? '').trim();
    final name = raw.isEmpty ? ArtistSummary.unknownArtist : raw;
    final key = name.toLowerCase();
    displayName.putIfAbsent(key, () => name);
    byKey.putIfAbsent(key, () => []).add(entry);
  }
  final artists = [
    for (final MapEntry(key: key, value: list) in byKey.entries)
      ArtistSummary(
        name: displayName[key]!,
        albums: sortEntries(
          list.where((e) => e.kind != MusicKind.song),
          LibrarySort.yearOldest,
        ),
        songs: sortEntries(
          list.where((e) => e.kind == MusicKind.song),
          LibrarySort.yearOldest,
        ),
      ),
  ];
  artists.sort((a, b) {
    if (a.isVariousArtists != b.isVariousArtists) {
      return a.isVariousArtists ? 1 : -1;
    }
    final c = artistSortKey(a.name).compareTo(artistSortKey(b.name));
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return artists;
}

/// Letter sections for the artist list and its rail (Library › Music: artists,
/// text view; Long list: music artists A–Z). "Various Artists" gets its own
/// last section.
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
