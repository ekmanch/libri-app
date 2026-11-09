import '../data/lookup/lookup_match.dart';
import '../data/lookup/music_lookup.dart';
import '../data/models/entry_id.dart';
import '../data/models/media_type.dart';
import '../data/models/released.dart';
import 'fake_lookup.dart';

/// The music lookup of the fake (Add / edit entry › Music search), with the
/// mockup's "ghost" search: three artists, 412 albums and 2,960 songs (the
/// mockup's rows first, generated ones after, so the paging has pages to
/// ask), and Ghost's 38 records newest first. Any other search answers
/// from [fakeCatalog], and its artists are the catalog's.

/// The mockup's artists with their album counts, most fans first.
const _ghostArtists = [
  ('Ghost', 38),
  ('Ghostface Killah', 27),
  ('Ghostemane', 45),
];

/// (record type, title, artist, year).
const _ghostAlbums = [
  ('album', 'Skeletá', 'Ghost', 2025),
  ('album', 'Impera', 'Ghost', 2022),
  ('album', 'Ghost Stories', 'Coldplay', 2014),
  ('album', 'Prequelle', 'Ghost', 2018),
  ('album', 'Meliora', 'Ghost', 2015),
  ('album', 'Ghosts V: Together', 'Nine Inch Nails', 2020),
  ('album', 'Infestissumam', 'Ghost', 2013),
];

/// (title, artist, album, year).
const _ghostSongs = [
  ('Ghost', 'Justin Bieber', 'Justice', 2021),
  ('Mary On A Cross', 'Ghost', 'Seven Inches of Satanic Panic', 2019),
  ('Ghost Town', 'Kanye West', 'ye', 2018),
  ('Square Hammer', 'Ghost', 'Popestar', 2016),
  ('Dance Macabre', 'Ghost', 'Prequelle', 2018),
  ('Ghostbusters', 'Ray Parker Jr.', 'Ghostbusters', 1984),
  ('Ghost', 'Ella Henderson', 'Chapter One', 2014),
];

/// Ghost's records as the mockup lists them, newest first: (record type,
/// title, year, songs).
const _ghostRecords = <(String, String, int, List<String>)>[
  ('album', 'Skeletá', 2025, ['Satanized', 'Lachryma', 'Peacefield']),
  ('album', 'Rite Here Rite Now (Original Soundtrack)', 2024, []),
  ('ep', 'Phantomime', 2023, []),
  (
    'album',
    'Impera',
    2022,
    ['Spillways', 'Call Me Little Sunshine', 'Kaisarion'],
  ),
  ('single', 'Seven Inches of Satanic Panic', 2019, ['Mary On A Cross']),
  ('album', 'Prequelle', 2018, ['Rats', 'Dance Macabre']),
  ('ep', 'Popestar', 2016, ['Square Hammer']),
  ('album', 'Meliora', 2015, []),
  ('album', 'Infestissumam', 2013, []),
];

const _ghostAlbumTotal = 412;
const _ghostSongTotal = 2960;

LookupMatch _album(String type, String title, String artist, int year) {
  final id = 'fake:album:${slugify('$artist $title')}';
  return LookupMatch(
    type: MediaType.music,
    title: title,
    source: id,
    creator: artist,
    released: Released(year),
    recordType: type,
    coverUrl: 'fake://cover/square/$id',
  );
}

LookupMatch _song(String title, String artist, String album, int year) {
  final albumId = 'fake:album:${slugify('$artist $album')}';
  return LookupMatch(
    type: MediaType.music,
    title: title,
    source: 'fake:track:${slugify('$artist $title')}',
    creator: artist,
    album: album,
    albumSource: albumId,
    released: Released(year),
    coverUrl: 'fake://cover/square/$albumId',
  );
}

ArtistHit _artist(String name, int albums) => ArtistHit(
  source: 'fake:artist:${slugify(name)}',
  name: name,
  pictureUrl: 'fake://cover/square/artist:${slugify(name)}',
  albums: albums,
);

/// Row [i] of the "ghost" search: the mockup's, then generated ones.
LookupMatch _ghostRow(MusicScope scope, int i) {
  if (scope == MusicScope.albums) {
    if (i < _ghostAlbums.length) {
      final (type, title, artist, year) = _ghostAlbums[i];
      return _album(type, title, artist, year);
    }
    return _album(
      'album',
      'Ghost Notes, Vol. ${i - 6}',
      'The Night Shift',
      2010,
    );
  }
  if (i < _ghostSongs.length) {
    final (title, artist, album, year) = _ghostSongs[i];
    return _song(title, artist, album, year);
  }
  return _song('Ghost Light ${i - 6}', 'The Night Shift', 'Ghost Notes', 2010);
}

/// An artist's records, newest first: Ghost's are the mockup's and older
/// singles up to 38, anyone else's are theirs in the catalog, else
/// generated ones as many as their row counts.
List<LookupMatch> _artistAlbums(String name) {
  final count = _ghostArtists.where((a) => a.$1 == name).firstOrNull?.$2;
  if (name == 'Ghost') {
    return [
      for (final (type, title, year, _) in _ghostRecords)
        _album(type, title, name, year),
      for (var n = 1; n <= count! - _ghostRecords.length; n++)
        _album('single', 'Ritual Sessions, No. $n', name, 2012 - n ~/ 6),
    ];
  }
  if (count == null) {
    return [
      for (final match in fakeCatalog)
        if (match.type == MediaType.music &&
            match.album == null &&
            match.creator == name)
          match,
    ];
  }
  return [
    for (var n = count; n >= 1; n--)
      _album('album', '$name, Vol. $n', name, 1995 + n ~/ 2),
  ];
}

/// An artist's songs, album by album, newest first.
List<LookupMatch> _artistSongs(String name) {
  if (name == 'Ghost') {
    final albums = _artistAlbums(name);
    return [
      for (final (_, title, year, songs) in _ghostRecords)
        for (final song in songs) _song(song, name, title, year),
      for (final single in albums.skip(_ghostRecords.length))
        _song(single.title, name, single.title, single.released!.year),
    ];
  }
  final albums = _artistAlbums(name);
  if (albums.any((album) => album.source.startsWith('fake:album:'))) {
    return [
      for (final album in albums)
        _song('${album.title}: Intro', name, album.title, album.released!.year),
    ];
  }
  return [
    for (final match in fakeCatalog)
      if (match.type == MediaType.music &&
          match.album != null &&
          match.creator == name)
        match,
  ];
}

/// A music page of the fake.
MusicPage fakeMusicPage(MusicRequest request, {int limit = musicPageSize}) {
  final cursor = request.cursor;
  final songs = request.scope == MusicScope.songs;
  MusicPage slice(
    List<LookupMatch> rows, {
    List<ArtistHit> artists = const [],
  }) {
    final end = (cursor + limit).clamp(0, rows.length);
    return MusicPage(
      matches: rows.skip(cursor).take(limit).toList(),
      total: rows.length,
      next: end < rows.length ? end : null,
      artists: cursor == 0 ? artists : const [],
    );
  }

  switch (request.list) {
    case MusicArtist(:final name):
      return slice(songs ? _artistSongs(name) : _artistAlbums(name));
    case MusicSearch(:final query):
      final q = query.trim().toLowerCase();
      if (q.startsWith('ghost')) {
        final total = songs ? _ghostSongTotal : _ghostAlbumTotal;
        final end = (cursor + limit).clamp(0, total);
        return MusicPage(
          matches: [
            for (var i = cursor; i < end; i++) _ghostRow(request.scope, i),
          ],
          total: total,
          next: end < total ? end : null,
          artists: cursor == 0
              ? [
                  for (final (name, albums) in _ghostArtists)
                    _artist(name, albums),
                ]
              : const [],
        );
      }
      final music = fakeCatalog.where((m) => m.type == MediaType.music);
      final names = <String>{
        for (final match in music)
          if (match.creator case final creator?
              when creator.toLowerCase().contains(q))
            creator,
      };
      return slice(
        [
          for (final match in FakeLookupSource.catalogSearch(
            query,
            type: MediaType.music,
          ))
            if ((match.album != null) == songs) match,
        ],
        artists: [
          for (final name in names.take(matchingArtists))
            _artist(name, _artistAlbums(name).length),
        ],
      );
  }
}
