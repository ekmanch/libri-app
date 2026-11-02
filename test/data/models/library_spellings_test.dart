import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/library_spellings.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/series.dart';

import '../../helpers/sample_library.dart';

void main() {
  final song = dirt.copyWith(
    id: 'music/would-alice-in-chains',
    title: 'Would?',
    kind: EntryKind.song,
    album: 'Dirt',
    tracks: null,
  );
  final library = sampleLibrary().copyWith(
    entries: [
      mummy.copyWith(series: const Series(name: 'The Mummy', number: 1)),
      dirt,
      song,
    ],
  );

  test('a new entry takes the library spelling of its artist', () {
    final added = dirt.copyWith(
      id: 'music/facelift-alice-in-chains',
      title: 'Facelift',
      creator: 'alice  in chains ',
    );
    expect(withLibrarySpellings(added, library).creator, 'Alice in Chains');
  });

  test('a song takes the album title by the same artist', () {
    final added = song.copyWith(
      id: 'music/rooster-alice-in-chains',
      creator: 'ALICE IN CHAINS',
      album: 'DIRT',
    );
    final saved = withLibrarySpellings(added, library);
    expect(saved.creator, 'Alice in Chains');
    expect(saved.album, 'Dirt');
    // Another artist's "Dirt" is not that album.
    final other = added.copyWith(creator: 'Nirvana');
    expect(withLibrarySpellings(other, library).album, 'DIRT');
  });

  test('a series takes the library spelling within its type', () {
    final added = mummy.copyWith(
      id: 'movies/the-mummy-returns-2001',
      title: 'The Mummy Returns',
      series: const Series(name: 'the mummy', number: 2),
    );
    final saved = withLibrarySpellings(added, library);
    expect(saved.series, const Series(name: 'The Mummy', number: 2));
    // A game named like it keeps its own spelling.
    final game = added.copyWith(id: 'games/x', type: MediaType.games);
    expect(withLibrarySpellings(game, library).series?.name, 'the mummy');
  });

  test('a name only re-cased in an edit keeps the new casing', () {
    final fixed = song.copyWith(creator: 'Alice In Chains');
    expect(
      withLibrarySpellings(fixed, library, before: song).creator,
      'Alice In Chains',
    );
  });

  test('a name nothing else has is kept as typed', () {
    final added = dirt.copyWith(id: 'music/x', creator: 'deafheaven');
    expect(withLibrarySpellings(added, library).creator, 'deafheaven');
  });
}
