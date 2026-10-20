import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/track.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';

/// What the user picked in Add / edit entry › Saving an album: songs already
/// saved or Saving a song: album already saved. Null means cancel the save.
enum ReplaceChoice { keepBoth, replace }

String _norm(String? text) => (text ?? '').trim().toLowerCase();

/// Same artist, by name, when both have one.
bool _sameArtist(Entry a, Entry b) =>
    _norm(a.creator).isNotEmpty && _norm(a.creator) == _norm(b.creator);

/// Song entries that are from [album] (same artist, album title matches the
/// song's `album` field). Saving the album then asks Add / edit entry › Saving
/// an album: songs already saved.
List<Entry> songsFromAlbum(Library library, Entry album) => library.entries
    .where(
      (e) =>
          e.type == MediaType.music &&
          e.kind == EntryKind.song &&
          e.id != album.id &&
          _sameArtist(e, album) &&
          _norm(e.album) == _norm(album.title),
    )
    .toList();

/// The album entry [song] is from, if saved: the one with the song's album id
/// ([albumSource], from the lookup) when both are known, else by artist and
/// album title. No album info on the song means no match. Saving the song then
/// asks Add / edit entry › Saving a song: album already saved.
Entry? albumOfSong(Library library, Entry song, {String? albumSource}) {
  if (albumSource != null) {
    for (final e in library.entries) {
      if (e.type == MediaType.music &&
          e.kind != EntryKind.song &&
          e.id != song.id &&
          e.source == albumSource) {
        return e;
      }
    }
  }
  if (_norm(song.album).isEmpty) return null;
  for (final e in library.entries) {
    if (e.type == MediaType.music &&
        e.kind != EntryKind.song &&
        e.id != song.id &&
        _sameArtist(e, song) &&
        _norm(e.title) == _norm(song.album)) {
      return e;
    }
  }
  return null;
}

/// The album with the songs' ratings moved into its track list. Unrated
/// songs leave nothing behind; a track already rated keeps its rating.
Entry absorbSongs(Entry album, List<Entry> songs) {
  final tracks = [...?album.tracks];
  for (final song in songs) {
    final rating = song.rating;
    if (rating == null) continue;
    if (tracks.any((t) => _norm(t.title) == _norm(song.title))) continue;
    tracks.add(Track(title: song.title, rating: rating));
  }
  return album.copyWith(tracks: tracks.isEmpty ? null : tracks);
}

const _words = [
  '',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
];

String _count(int n) => n < _words.length ? _words[n] : '$n';

/// Saving an album when song entries from it exist (Add / edit entry ›
/// Saving an album: songs already saved).
Future<ReplaceChoice?> showReplaceSongsDialog(
  BuildContext context, {
  required Entry album,
  required List<Entry> songs,
}) {
  final n = songs.length;
  return showAppDialog<ReplaceChoice>(
    context,
    builder: (context) => AppDialog(
      title:
          'You have $n ${n == 1 ? 'song' : 'songs'} from ${album.title} saved',
      body: songs.map((s) => s.title).join(' · '),
      note: n == 1
          ? "The song entry is removed. Its rating moves to the album's "
                'track list.'
          : 'The ${_count(n)} song entries are removed. Their ratings move '
                "to the album's track list.",
      actionsLayout: DialogActionsLayout.column,
      actions: [
        AppButton(
          label: 'Keep both',
          kind: AppButtonKind.neutral,
          onPressed: () => Navigator.pop(context, ReplaceChoice.keepBoth),
        ),
        AppButton(
          label: 'Replace songs with album',
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, ReplaceChoice.replace),
        ),
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}

/// Saving a song when its album is saved (Add / edit entry › Saving a song:
/// album already saved). Says what would be lost.
Future<ReplaceChoice?> showReplaceAlbumDialog(
  BuildContext context, {
  required Entry song,
  required Entry album,
  required bool adding,
}) {
  return showAppDialog<ReplaceChoice>(
    context,
    builder: (context) => AppDialog(
      title: '${album.title} is already in your library',
      body:
          'You are ${adding ? 'adding' : 'saving'} the song ${song.title} '
          'from this album.',
      note: 'Replacing deletes the album entry, with its rating and note.',
      actionsLayout: DialogActionsLayout.column,
      actions: [
        AppButton(
          label: 'Keep both',
          kind: AppButtonKind.neutral,
          onPressed: () => Navigator.pop(context, ReplaceChoice.keepBoth),
        ),
        AppButton(
          label: 'Replace album with this song',
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, ReplaceChoice.replace),
        ),
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
