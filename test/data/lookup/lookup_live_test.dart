// Talks to the real lookup providers. Opt in with:
//
//   LIBRI_LIVE_LOOKUPS=1 flutter test test/data/lookup/lookup_live_test.dart
//
// AniList, Open Library and Deezer need no key and always run then. TMDB
// and IGDB run when their keys are in the environment too:
// TMDB_READ_TOKEN, IGDB_CLIENT_ID and IGDB_CLIENT_SECRET (and optionally
// GOOGLE_BOOKS_KEY). Nothing is written anywhere but a temporary folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_app/data/lookup/anilist_source.dart';
import 'package:library_app/data/lookup/deezer_source.dart';
import 'package:library_app/data/lookup/google_books.dart';
import 'package:library_app/data/lookup/igdb_source.dart';
import 'package:library_app/data/lookup/igdb_token_store.dart';
import 'package:library_app/data/lookup/open_library_source.dart';
import 'package:library_app/data/lookup/tmdb_source.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/storage/json_file.dart';

void main() {
  final env = Platform.environment;
  if (env['LIBRI_LIVE_LOOKUPS'] != '1') {
    test(
      'live lookups',
      () {},
      skip: 'Set LIBRI_LIVE_LOOKUPS=1 to ask the real providers.',
    );
    return;
  }

  final client = http.Client();
  tearDownAll(client.close);

  // Which keys this run has, so a quiet provider dashboard can be told
  // from a key that never left the shell.
  String masked(String name) {
    final value = env[name] ?? '';
    return value.isEmpty ? '$name unset' : '$name set (${value.length} chars)';
  }

  setUpAll(() {
    // ignore: avoid_print
    print(
      'Live lookups: ${masked('TMDB_READ_TOKEN')}, ${masked('IGDB_CLIENT_ID')}, '
      '${masked('IGDB_CLIENT_SECRET')}, ${masked('GOOGLE_BOOKS_KEY')}',
    );
  });

  test('AniList: search, details and cover', () async {
    final anilist = AniListSource(client);
    final hits = await anilist.search('Akira', type: MediaType.anime);
    final akira = hits.firstWhere((m) => m.source == 'anilist:47');
    expect(akira.released?.year, 1988);
    expect(akira.description, isNotEmpty);
    expect(akira.description, isNot(contains('<')));
    expect(akira.coverUrl, startsWith('https://'));
    expect(akira.tags, isNotEmpty);
    expect(
      await anilist.coverUrl('anilist:47', type: MediaType.anime),
      startsWith('https://'),
    );
    final matched = await anilist.match(
      'Perfect Blue',
      type: MediaType.anime,
      year: 1997,
    );
    expect(matched?.source, 'anilist:437');
  });

  test(
    'Open Library: search, details, cover, and the Google fill-in',
    () async {
      final books = OpenLibrarySource(
        client,
        google: GoogleBooks(client, key: env['GOOGLE_BOOKS_KEY'] ?? ''),
      );
      final hits = await books.search(
        'Dracula Bram Stoker',
        type: MediaType.books,
      );
      final dracula = hits.firstWhere(
        (m) => m.title.toLowerCase() == 'dracula',
      );
      expect(dracula.source, startsWith('openlibrary:OL'));
      expect(dracula.released?.year, 1897);
      expect(dracula.creator, contains('Stoker'));
      final full = await books.details(dracula);
      expect(full.description, isNotEmpty);
      expect(
        await books.coverUrl(dracula.source, type: MediaType.books),
        startsWith('https://'),
      );
      final matched = await books.match(
        'Dracula',
        type: MediaType.books,
        year: 1897,
        creator: 'Bram Stoker',
      );
      expect(matched?.released?.year, 1897);
      // Without a key Google Books shares one small daily quota with
      // everyone, so only a key makes the fill-in worth asserting on.
      if ((env['GOOGLE_BOOKS_KEY'] ?? '').isNotEmpty) {
        final filled = await GoogleBooks(
          client,
          key: env['GOOGLE_BOOKS_KEY']!,
        ).lookUp('Dracula', author: 'Bram Stoker');
        expect(filled.description, isNotEmpty);
        // Only Google Books has it (2026-10-19), and its search answered
        // 503 to most requests then: the retry elsewhere must reach it.
        final angels = await books.search(
          'The Weight of Angels John Boyne',
          type: MediaType.books,
        );
        expect(
          angels.map((m) => m.source),
          contains('googlebooks:eOTEEQAAQBAJ'),
        );
      }
    },
  );

  test('Deezer: albums, songs, details, tracks and an artist photo', () async {
    final deezer = DeezerSource(client);
    final hits = await deezer.search(
      'Dirt Alice in Chains',
      type: MediaType.music,
    );
    final albums = hits.where((m) => m.album == null).toList();
    final dirt = albums.firstWhere(
      (m) => m.title.toLowerCase() == 'dirt',
      orElse: () =>
          albums.firstWhere((m) => m.title.toLowerCase().startsWith('dirt')),
    );
    expect(dirt.source, startsWith('deezer:album:'));
    expect(dirt.creator, 'Alice in Chains');
    final full = await deezer.details(dirt);
    expect(full.released?.year, 1992);
    expect(full.tags, isNotEmpty);
    final tracks = await deezer.albumTracks(dirt.source);
    expect(tracks.map((t) => t.title), anyElement(startsWith('Rooster')));
    expect(tracks.first.id, startsWith('deezer:track:'));
    expect(
      await deezer.coverUrl(dirt.source, type: MediaType.music),
      contains('500x500'),
    );
    final song = hits.firstWhere((m) => m.album != null);
    expect(song.albumSource, startsWith('deezer:album:'));
    expect(
      await deezer.artistPhotoUrl('Alice in Chains'),
      startsWith('https://'),
    );
    expect(await deezer.artistPhotoUrl('Various Artists'), isNull);
    final matched = await deezer.match(
      'Dirt',
      type: MediaType.music,
      creator: 'Alice in Chains',
    );
    expect(matched, isNotNull);
    expect(matched!.creator, 'Alice in Chains');
  });

  final tmdbToken = env['TMDB_READ_TOKEN'] ?? '';
  test('TMDB: movies and shows', () async {
    final tmdb = TmdbSource(client, token: tmdbToken);
    final movies = await tmdb.search('The Mummy', type: MediaType.movies);
    final mummy = movies.firstWhere((m) => m.released?.year == 1999);
    expect(mummy.source, 'tmdb:movie:564');
    final full = await tmdb.details(mummy);
    expect(full.creator, 'Stephen Sommers');
    expect(full.tags, contains('Adventure'));
    expect(
      await tmdb.coverUrl(mummy.source, type: MediaType.movies),
      startsWith('https://image.tmdb.org/t/p/w342/'),
    );
    final shows = await tmdb.search('The Last of Us', type: MediaType.shows);
    expect(shows.first.source, startsWith('tmdb:tv:'));
    final show = await tmdb.details(shows.first);
    expect(show.creator, contains('Mazin'));
  }, skip: tmdbToken.isEmpty ? 'Set TMDB_READ_TOKEN.' : false);

  final igdbId = env['IGDB_CLIENT_ID'] ?? '';
  final igdbSecret = env['IGDB_CLIENT_SECRET'] ?? '';
  test(
    'IGDB: games with platforms',
    () async {
      final dir = await Directory.systemTemp.createTemp('igdb-live');
      addTearDown(() => dir.delete(recursive: true));
      final igdb = IgdbSource(
        client,
        clientId: igdbId,
        clientSecret: igdbSecret,
        tokens: IgdbTokenStore(JsonFile(File('${dir.path}/igdb_token.json'))),
      );
      final hits = await igdb.search('The Last of Us', type: MediaType.games);
      final tlou = hits.firstWhere((m) => m.released?.year == 2013);
      expect(tlou.creator, contains('Naughty Dog'));
      expect(tlou.platforms, contains('PlayStation 3'));
      expect(tlou.coverUrl, contains('t_cover_big'));
      expect(
        await igdb.coverUrl(tlou.source, type: MediaType.games),
        contains('t_cover_big'),
      );
    },
    skip: igdbId.isEmpty || igdbSecret.isEmpty
        ? 'Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET.'
        : false,
  );
}
