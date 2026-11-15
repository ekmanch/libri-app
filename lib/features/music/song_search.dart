import 'package:flutter/foundation.dart';

import '../../data/lookup/text_clean.dart';
import '../../data/lookup/track_info.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/media_type.dart';
import '../../data/models/track.dart';

/// A row of the Songs tab while it is searched: a song entry, or a track of
/// a saved album, which the tab lists only then (DESIGN.md section 5, "A
/// search on the Songs tab").
@immutable
class SongItem {
  /// A song saved on its own.
  const SongItem.entry(this.entry) : track = null, rating = null;

  /// The track [track] of the album [entry], with its stored [rating].
  const SongItem.track(this.entry, String this.track, {this.rating});

  /// The song entry, or the album the track is on: what a tap opens.
  final Entry entry;

  /// The track's title; null for a song entry.
  final String? track;

  /// The track's rating; a song entry's is its own.
  final int? rating;

  bool get isTrack => track != null;
  String get title => track ?? entry.title;

  @override
  bool operator ==(Object other) =>
      other is SongItem &&
      other.entry.id == entry.id &&
      other.track == track &&
      other.rating == rating;

  @override
  int get hashCode => Object.hash(entry.id, track, rating);

  @override
  String toString() =>
      isTrack ? 'SongItem($title on ${entry.title})' : 'SongItem($title)';
}

/// Whether the search [q] (normalized) names [entry]'s artist.
bool namesArtist(Entry entry, String q) =>
    q.isNotEmpty && (entry.creator?.toLowerCase().contains(q) ?? false);

/// Every track of [album], rated or not, as its details list them: the
/// [fetched] list in its order with the stored ratings on it (by id, else by
/// title), then the rated tracks that list lacks. Without a fetched list
/// (not on the device yet, or an album with no online match) the stored
/// tracks.
List<SongItem> tracksOf(Entry album, List<TrackInfo>? fetched) {
  final stored = album.tracks ?? const <Track>[];
  if (fetched == null) {
    return [
      for (final t in stored) SongItem.track(album, t.title, rating: t.rating),
    ];
  }
  Track? storedFor(TrackInfo info) {
    for (final t in stored) {
      if (t.id != null && t.id == info.id) return t;
    }
    final key = trackTitleKey(info.title);
    for (final t in stored) {
      if (trackTitleKey(t.title) == key) return t;
    }
    return null;
  }

  final listed = <Track>{};
  final items = <SongItem>[];
  for (final info in fetched) {
    final track = storedFor(info);
    if (track != null) listed.add(track);
    items.add(SongItem.track(album, info.title, rating: track?.rating));
  }
  for (final t in stored) {
    if (t.rating != null && !listed.contains(t)) {
      items.add(SongItem.track(album, t.title, rating: t.rating));
    }
  }
  return items;
}

/// The Songs tab for the search [q] (normalized, not empty), as the desktop
/// lists it. [found] are the music entries the search found, in the order
/// to show. Each song entry is a row. An album whose artist the search
/// names brings every track it has, rated or not, right where the album
/// would have been ([fetched] gives its track list once that is on the
/// device; until then its stored tracks stand in). Any other album brings
/// only its rated tracks whose own title holds the search: that song, not
/// the rest of the album, and nothing for an album found by its title or a
/// tag.
List<SongItem> songsMatching(
  Iterable<Entry> found,
  String q, {
  required List<TrackInfo>? Function(Entry album) fetched,
}) {
  final songs = <SongItem>[];
  for (final entry in found) {
    if (entry.type != MediaType.music) continue;
    if (entry.kind == EntryKind.song) {
      songs.add(SongItem.entry(entry));
    } else if (namesArtist(entry, q)) {
      songs.addAll(tracksOf(entry, fetched(entry)));
    } else {
      for (final t in entry.tracks ?? const <Track>[]) {
        if (t.rating != null && t.title.toLowerCase().contains(q)) {
          songs.add(SongItem.track(entry, t.title, rating: t.rating));
        }
      }
    }
  }
  return songs;
}
