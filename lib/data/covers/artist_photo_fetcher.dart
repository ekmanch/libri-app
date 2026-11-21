import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../lookup/apple_artists.dart';
import '../lookup/lookup_failure.dart';
import '../models/entry.dart';
import '../models/entry_kind.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../net/network_kind.dart';
import 'artist_photos.dart';
import 'cover_store.dart';

/// One artist of the library as the photo rules see them: the name as the
/// library spells it, its slug, the album titles saved for them (their
/// albums, and the albums their saved songs name), the titles of their
/// saved songs in the library's order (asked about only when no album
/// tells who the artist is) and the latest day one of their entries was
/// added.
typedef LibraryArtist = ({
  String name,
  String slug,
  List<String> owned,
  List<String> songs,
  DateTime added,
});

/// The artists of [library] that can have a photo: everyone with a name
/// that makes a slug, but "Various Artists" and "Unknown artist". Names
/// that differ only in case are one artist, as in the artist list.
List<LibraryArtist> photoArtists(Library library) {
  final names = <String, String>{};
  final owned = <String, List<String>>{};
  final songs = <String, List<String>>{};
  final added = <String, DateTime>{};
  for (final entry in library.entries) {
    if (entry.type != MediaType.music) continue;
    final name = (entry.creator ?? '').trim();
    if (name.isEmpty || isSkippedArtist(name)) continue;
    final key = name.toLowerCase();
    names.putIfAbsent(key, () => name);
    final title = entry.kind == EntryKind.song ? entry.album : entry.title;
    if (title != null && title.trim().isNotEmpty) {
      owned.putIfAbsent(key, () => []).add(title);
    }
    if (entry.kind == EntryKind.song) {
      final saved = songs.putIfAbsent(key, () => []);
      if (!saved.contains(entry.title)) saved.add(entry.title);
    }
    final best = added[key];
    if (best == null || entry.added.isAfter(best)) added[key] = entry.added;
  }
  return [
    for (final MapEntry(:key, value: name) in names.entries)
      if (artistSlug(name) case final slug?)
        (
          name: name,
          slug: slug,
          owned: owned[key] ?? const <String>[],
          songs: songs[key] ?? const <String>[],
          added: added[key]!,
        ),
  ];
}

/// "312 of 348 artists have one": how many of the artists that can have a
/// photo have a file.
({int have, int total}) artistPhotoCounts(Library library, CoverStore covers) {
  final artists = photoArtists(library);
  final files = covers.artistPhotos;
  return (
    have: artists.where((a) => files.containsKey(a.slug)).length,
    total: artists.length,
  );
}

/// Fetches the photos of new artists on the phone (DESIGN.md section 10e).
///
/// The first full run belongs to the desktop: nothing is asked until
/// GitHub's `_missing.json` holds its `backfilled` day. From then on Apple
/// is asked only about an artist with no file and no fresh entry in the
/// record, one at a time in name order, never on mobile data while Only on
/// Wi-Fi is on. A photo is stored as the artist's file and shown at once;
/// "nothing found" is recorded; both go out with the next sync. A 403 or a
/// 429 stops the work for the session, being offline ends the run, and any
/// other failure passes that artist over until the next session without
/// recording anything.
class ArtistPhotoFetcher {
  ArtistPhotoFetcher({
    required this.covers,
    required this.apple,
    this.network = const FixedNetworkKind(),
    DateTime Function()? now,
    void Function(String message)? log,
  }) : _now = now ?? DateTime.now,
       _log = log ?? debugPrint;

  final CoverStore covers;
  final AppleArtists apple;
  final NetworkKind network;
  final DateTime Function() _now;
  final void Function(String) _log;

  /// The artists a failure passed over this session, by slug.
  final _passed = <String>{};

  /// The artists asked about this session, by slug.
  final _asked = <String>{};
  bool _running = false;

  bool get isRunning => _running;

  /// The artists to ask about now, in name order; empty before the
  /// desktop's first run is seen, before GitHub's list has come this
  /// session, and once Apple refused.
  List<LibraryArtist> due(Library library) {
    if (!covers.hasListed || covers.backfilled == null || apple.stopped) {
      return const [];
    }
    final missing = covers.missing;
    final files = covers.artistPhotos;
    final today = _now();
    bool sameDay(DateTime a, DateTime b) => artistDayOf(a) == artistDayOf(b);
    final out = [
      for (final artist in photoArtists(library))
        if (!files.containsKey(artist.slug) && !_passed.contains(artist.slug))
          if (missing.isDue(artist.slug, today, artist.added) ||
              // Recorded today with an entry added today: the device
              // that adds the entry asks once more.
              (!_asked.contains(artist.slug) &&
                  sameDay(artist.added, today) &&
                  sameDay(missing.artists[artist.slug]!.tried, today)))
            artist,
    ];
    return out
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Asks about every artist that is [due]; returns how many were settled
  /// (a photo, or a record). Does nothing while a run is under way.
  Future<int> run(Library library, {required bool wifiOnly}) async {
    if (_running) return 0;
    _running = true;
    var settled = 0;
    apple.photoSide = covers.photoSize;
    try {
      for (final artist in due(library)) {
        if (wifiOnly && await network.isOnMobileData()) break;
        _asked.add(artist.slug);
        final ArtistFound found;
        try {
          found = await apple.find(artist.name, artist.owned, artist.songs);
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.rateLimited) {
            _log('Apple stopped answering: no more artist photos for now.');
            break;
          }
          if (e.failure == LookupFailure.offline) break;
          _log('Passing over ${artist.name}: $e');
          _passed.add(artist.slug);
          continue;
        }
        // A photo that arrives for an artist who got a file meanwhile is
        // dropped.
        if (covers.artistPhotos.containsKey(artist.slug)) continue;
        switch (found) {
          case ArtistPhotoFound(:final bytes):
            await covers.putArtistPhoto(
              artist.name,
              bytes,
              picked: false,
              summary: 'Add a photo of ${artist.name}',
            );
          case ArtistNotFound(:final reason):
            await covers.recordMissing(
              MissingSet(
                artist.slug,
                TriedArtist(
                  name: artist.name,
                  tried: artistDayOf(_now()),
                  reason: reason,
                ),
              ),
              summary: 'Note that ${artist.name} has no photo',
            );
        }
        settled++;
      }
    } finally {
      _running = false;
    }
    return settled;
  }
}

/// The titles [photoArtists] counts as owned for the artist called [name]
/// (Pick a photo asks Apple with them).
List<String> ownedTitlesOf(Library library, String name) {
  final key = name.trim().toLowerCase();
  return [
    for (final Entry entry in library.entries)
      if (entry.type == MediaType.music &&
          (entry.creator ?? '').trim().toLowerCase() == key)
        if (entry.kind == EntryKind.song ? entry.album : entry.title
            case final title? when title.trim().isNotEmpty)
          title,
  ];
}

/// The titles of the songs saved by the artist called [name], in the
/// library's order, as [photoArtists] has them.
List<String> savedSongsOf(Library library, String name) {
  final key = name.trim().toLowerCase();
  final songs = <String>[];
  for (final Entry entry in library.entries) {
    if (entry.type == MediaType.music &&
        entry.kind == EntryKind.song &&
        (entry.creator ?? '').trim().toLowerCase() == key &&
        !songs.contains(entry.title)) {
      songs.add(entry.title);
    }
  }
  return songs;
}

/// The slugs of [library]'s artists, for the record's merge: an artist no
/// entry names any more leaves `_missing.json`.
Set<String> artistSlugsOf(Library library) => {
  for (final artist in photoArtists(library)) artist.slug,
};
