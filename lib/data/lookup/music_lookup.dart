import 'package:flutter/foundation.dart';

import '../models/entry_kind.dart';
import 'lookup_match.dart';

/// What the music lookup lists: albums or songs (Add / edit entry › Music
/// search: albums, … songs). It is the form's "Album or song" field, so the
/// two always agree.
enum MusicScope {
  albums,
  songs;

  /// Songs for a song, albums for anything else.
  static MusicScope of(EntryKind? kind) =>
      kind == EntryKind.song ? songs : albums;

  EntryKind get kind => this == songs ? EntryKind.song : EntryKind.album;

  /// "Albums" or "Songs", as the switch reads.
  String get label => this == songs ? 'Songs' : 'Albums';

  /// "album" or "albums", by [n].
  String noun(int n) => switch (this) {
    albums => n == 1 ? 'album' : 'albums',
    songs => n == 1 ? 'song' : 'songs',
  };
}

/// An artist whose name matches a music search: the music source's id for
/// them ("deezer:artist:8506054"), the name, a photo and how many albums
/// the source lists (EPs and singles among them).
@immutable
class ArtistHit {
  const ArtistHit({
    required this.source,
    required this.name,
    this.pictureUrl,
    this.albums,
  });

  final String source;
  final String name;
  final String? pictureUrl;
  final int? albums;

  @override
  bool operator ==(Object other) =>
      other is ArtistHit &&
      other.source == source &&
      other.name == name &&
      other.pictureUrl == pictureUrl &&
      other.albums == albums;

  @override
  int get hashCode => Object.hash(source, name);

  @override
  String toString() => 'ArtistHit($source, $name)';
}

/// The list the music lookup pages through: a search, or one artist's
/// albums or songs, newest first.
@immutable
sealed class MusicList {
  const MusicList();
}

final class MusicSearch extends MusicList {
  const MusicSearch(this.query);

  final String query;

  @override
  bool operator ==(Object other) =>
      other is MusicSearch && other.query == query;

  @override
  int get hashCode => query.hashCode;
}

final class MusicArtist extends MusicList {
  const MusicArtist({required this.source, required this.name});

  MusicArtist.of(ArtistHit artist) : source = artist.source, name = artist.name;

  final String source;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is MusicArtist && other.source == source && other.name == name;

  @override
  int get hashCode => Object.hash(source, name);
}

/// One page of a music list: the list, albums or songs, and where the page
/// starts (an offset, or for an artist's songs the album the walk is at;
/// whatever [MusicPage.next] gave).
@immutable
class MusicRequest {
  const MusicRequest({
    required this.list,
    required this.scope,
    this.cursor = 0,
  });

  final MusicList list;
  final MusicScope scope;
  final int cursor;

  @override
  bool operator ==(Object other) =>
      other is MusicRequest &&
      other.list == list &&
      other.scope == scope &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(list, scope, cursor);
}

/// A page of a music list: its matches, how many the list holds when the
/// source says, where the next page starts (null at the end) and, on a
/// search's first page, the artists whose names match.
@immutable
class MusicPage {
  const MusicPage({
    this.matches = const [],
    this.total,
    this.next,
    this.artists = const [],
  });

  final List<LookupMatch> matches;
  final int? total;
  final int? next;
  final List<ArtistHit> artists;
}

/// How many matches a music page asks for.
const musicPageSize = 25;

/// How many matching artists a music search shows above its results.
const matchingArtists = 3;
