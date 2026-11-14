import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_files.dart';
import 'package:library_app/data/covers/cover_picture.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';

import '../../helpers/sample_library.dart';

CoverFile file(String path) => CoverFile(path: path, size: 1000, sha: path);

void main() {
  // The rules are the desktop's (libri-kde `src/covers/mod.rs`): the two
  // apps read and write the same folders, so these must never differ.
  test('a file belongs to a title by its slug and a dot', () {
    expect(coverSlug('movies/the-mummy-1999'), 'the-mummy-1999');
    expect(coverIdFolder('movies/the-mummy-1999'), 'movies');
    expect(coverIdFolder('nothing'), isNull);
    expect(coverBelongs('the-mummy-1999.jpg', 'the-mummy-1999'), isTrue);
    expect(
      coverBelongs('the-mummy-1999.steelbook.jpg', 'the-mummy-1999'),
      isTrue,
    );
    // Another entry's: the slug goes on.
    expect(coverBelongs('the-mummy-1999-2.jpg', 'the-mummy-1999'), isFalse);
    expect(coverBelongs('.jpg', ''), isFalse);
    expect(coverLabelAndExtension('the-mummy-1999.steelbook.jpg'), (
      'steelbook',
      'jpg',
    ));
    expect(coverLabelAndExtension('the-mummy-1999.jpg'), ('', 'jpg'));
    expect(coverSlugOfName('the-mummy-1999.a3f9c2e.jpg'), 'the-mummy-1999');
    expect(isCoverImage('a.JPG'), isTrue);
    expect(isCoverImage('a.txt'), isFalse);
  });

  test('cover_from names the path under covers/', () {
    const path = 'movies/the-mummy-1999.a3f9c2e.jpg';
    expect(repoCoverFrom(path), 'repo:$path');
    expect(repoCoverPath('repo:$path'), path);
    expect(repoCoverPath('tmdb:movie:564'), isNull);
    expect(isRepoCover('repo:$path'), isTrue);
    expect(isRepoCover(null), isFalse);
    expect(splitCoverPath(path), ('movies', 'the-mummy-1999.a3f9c2e.jpg'));
    expect(splitCoverPath('stray.jpg'), ('', 'stray.jpg'));
  });

  test(
    'an upload is named after the slug and its short sha, in lower case',
    () {
      expect(
        coverUploadName('the-mummy-1999', 'A3F9C2E0123456789'),
        'the-mummy-1999.a3f9c2e.jpg',
      );
      expect(isCoverUploadLabel('a3f9c2e'), isTrue);
      expect(isCoverUploadLabel('steelbook'), isFalse);
      expect(isCoverUploadLabel('A3F9C2E'), isFalse);
      expect(file('movies/the-mummy-1999.a3f9c2e.jpg').label, isNull);
      expect(file('movies/the-mummy-1999.steelbook.jpg').label, 'steelbook');
    },
  );

  test('the folder sits beside the library file', () {
    expect(coversRoot('library.json'), 'covers');
    expect(coversRoot('data/library.json'), 'data/covers');
    expect(coverFolder(MediaType.music), 'music');
  });

  test('sizes read as on the desktop', () {
    expect(coverSizeLabel(1400000), '1.4 MB');
    expect(coverSizeLabel(240000), '240 KB');
    expect(coverSizeLabel(1), '1 KB');
  });

  test('candidates and unused follow the names', () {
    final library = sampleLibrary();
    final files = [
      file('movies/the-mummy-1999.jpg'),
      file('movies/the-mummy-1999.steelbook.jpg'),
      file('movies/the-mummy-1999-2.jpg'),
      file('movies/old-poster.png'),
      file('music/dirt-alice-in-chains.91be04c.jpg'),
      file('movies/the-mummy-1999.txt'),
    ];
    expect(
      coverCandidates(files, MediaType.movies, mummy.id).map((f) => f.path),
      ['movies/the-mummy-1999.jpg', 'movies/the-mummy-1999.steelbook.jpg'],
    );
    expect(unusedCovers(files, library).map((f) => f.path), [
      'movies/the-mummy-1999-2.jpg',
      'movies/old-poster.png',
    ]);
    // A file some title shows is in use whatever its name.
    final shown = library.copyWith(
      entries: [
        mummy.copyWith(coverFrom: 'repo:movies/old-poster.png'),
        dirt,
      ],
    );
    expect(unusedCovers(files, shown).map((f) => f.path), [
      'movies/the-mummy-1999-2.jpg',
    ]);
    expect(coverUsers(shown, 'movies/old-poster.png').single.id, mummy.id);
    expect(
      coverUsedElsewhere(shown, 'movies/old-poster.png', mummy.id),
      isFalse,
    );
    expect(coverUsedElsewhere(shown, 'movies/old-poster.png', dirt.id), isTrue);
    expect(coverTitleOf(library, files[1])!.id, mummy.id);
    expect(coverTitleOf(library, files[3]), isNull);
  });

  test("a type change still finds the files of the id's first type", () {
    // The id keeps its first type.
    final moved = mummy.copyWith(type: MediaType.shows);
    final files = [
      file('movies/the-mummy-1999.jpg'),
      file('shows/the-mummy-1999.b.jpg'),
      file('books/the-mummy-1999.jpg'),
    ];
    expect(coverCandidates(files, moved.type, moved.id).map((f) => f.path), [
      'movies/the-mummy-1999.jpg',
      'shows/the-mummy-1999.b.jpg',
    ]);
    expect(
      coverPathIn(MediaType.shows, 'movies/the-mummy-1999.jpg'),
      'shows/the-mummy-1999.jpg',
    );
    expect(unusedCovers(files, Library(entries: [moved])).map((f) => f.path), [
      'books/the-mummy-1999.jpg',
    ]);
  });

  test("a song's cover is its album's while the album is in the library", () {
    final rooster = Entry(
      id: 'music/rooster-alice-in-chains',
      type: MediaType.music,
      title: 'Rooster',
      creator: 'Alice in Chains',
      status: EntryStatus.done,
      added: DateTime(2026),
      kind: EntryKind.song,
      album: 'dirt',
    );
    final library = Library(entries: [mummy, dirt, rooster]);
    expect(coverOwner(library, rooster).id, dirt.id);
    expect(coverOwner(library, dirt).id, dirt.id);
    expect(coverOwner(Library(entries: [rooster]), rooster).id, rooster.id);
    expect(
      coverOwner(library, rooster.copyWith(creator: 'Someone else')).id,
      rooster.id,
    );
  });

  test('a shape within a tenth of the cover is cropped with no step', () {
    expect(coverShapeFits(1000, 1500, square: false), isTrue);
    expect(coverShapeFits(1000, 1400, square: false), isTrue);
    expect(coverShapeFits(1920, 1080, square: false), isFalse);
    expect(coverShapeFits(1080, 2400, square: false), isFalse);
    expect(coverShapeFits(1000, 1000, square: true), isTrue);
    expect(coverShapeFits(1000, 1500, square: true), isFalse);
  });

  test('the crop frame is the largest of the shape, along the long side', () {
    // A wide image: the full height, sliding sideways.
    expect(coverCropFrame(1920, 1080, square: false, at: 0), (
      x: 0,
      y: 0,
      width: 720,
      height: 1080,
    ));
    expect(coverCropFrame(1920, 1080, square: false, at: 1).x, 1200);
    expect(coverCropFrame(1920, 1080, square: false, at: 0.5).x, 600);
    // A tall one: the full width, sliding up or down.
    expect(coverCropFrame(1080, 2400, square: false, at: 1), (
      x: 0,
      y: 780,
      width: 1080,
      height: 1620,
    ));
    expect(coverCropFrame(1920, 1080, square: true, at: 0.5), (
      x: 420,
      y: 0,
      width: 1080,
      height: 1080,
    ));
    // Saved at 1000 × 1500 at most, never scaled up.
    expect(coverFittedSize(3840, 2160, square: false), (1000, 1500));
    expect(coverFittedSize(1920, 1080, square: false), (720, 1080));
    expect(coverFittedSize(3840, 2160, square: true), (1000, 1000));
  });
}
