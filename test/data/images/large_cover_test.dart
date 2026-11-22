import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/large_cover.dart';

void main() {
  test('TMDB posters go from the list size to w780, never further', () {
    expect(
      largeCoverUrl('https://image.tmdb.org/t/p/w342/abc.jpg', square: false),
      'https://image.tmdb.org/t/p/w780/abc.jpg',
    );
    expect(
      largeCoverUrl('https://image.tmdb.org/t/p/w185/abc.jpg', square: false),
      'https://image.tmdb.org/t/p/w780/abc.jpg',
    );
    expect(
      largeCoverUrl('https://image.tmdb.org/t/p/w780/abc.jpg', square: false),
      isNull,
    );
    expect(
      largeCoverUrl(
        'https://image.tmdb.org/t/p/original/abc.jpg',
        square: false,
      ),
      isNull,
    );
  });

  test('IGDB covers go to t_1080p', () {
    const at = 'https://images.igdb.com/igdb/image/upload';
    expect(
      largeCoverUrl('$at/t_cover_big/co1.jpg', square: false),
      '$at/t_1080p/co1.jpg',
    );
    expect(largeCoverUrl('$at/t_1080p/co1.jpg', square: false), isNull);
    expect(largeCoverUrl('$at/t_original/co1.jpg', square: false), isNull);
  });

  test('Deezer covers go to the 1000 of cover_xl', () {
    const at = 'https://cdn-images.dzcdn.net/images/cover/h4sh';
    expect(
      largeCoverUrl('$at/500x500-000000-80-0-0.jpg', square: true),
      '$at/1000x1000-000000-80-0-0.jpg',
    );
    expect(
      largeCoverUrl('$at/1000x1000-000000-80-0-0.jpg', square: true),
      isNull,
    );
  });

  test('Apple renders a 1170 box for a book and 900 for an album', () {
    const at =
        'https://is1-ssl.mzstatic.com/image/thumb/Publication122/v4/b7/a1/'
        'etext24022.jpg';
    expect(
      largeCoverUrl('$at/600x600bb.jpg', square: false),
      '$at/1170x1170bb.jpg',
    );
    expect(
      largeCoverUrl('$at/600x600bb.jpg', square: true),
      '$at/900x900bb.jpg',
    );
    expect(largeCoverUrl('$at/1170x1170bb.jpg', square: false), isNull);
  });

  test('a source already at its largest, the owner\'s files and anything '
      'else have no larger version', () {
    for (final url in [
      'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx47.jpg',
      'https://covers.openlibrary.org/b/id/15158664-L.jpg',
      'https://books.google.com/books/content?id=x&printsec=frontcover&img=1',
      'repo:movies/the-mummy-1999.jpg',
      'fake://cover/poster/x',
      'not a url',
    ]) {
      expect(largeCoverUrl(url, square: false), isNull, reason: url);
    }
  });

  group('the width the larger view would get, from the URL alone', () {
    test('a size in the URL is that size', () {
      expect(
        largestCoverWidth(
          'https://image.tmdb.org/t/p/w342/abc.jpg',
          square: false,
        ),
        780,
      );
      expect(
        largestCoverWidth(
          'https://cdn-images.dzcdn.net/images/cover/abc/500x500-000000-80-0-0.jpg',
          square: true,
        ),
        1000,
      );
      const apple =
          'https://is1-ssl.mzstatic.com/image/thumb/Music/v4/a/b/c/x.jpg/600x600bb.jpg';
      expect(largestCoverWidth(apple, square: true), 900);
      // A book's box counts as the desktop's 1200, 800 wide at 2:3,
      // though the larger view asks for 1170; a larger box as it is.
      expect(largestCoverWidth(apple, square: false), 800);
      expect(
        largestCoverWidth(
          apple.replaceFirst('600x600', '1170x1170'),
          square: false,
        ),
        800,
      );
      expect(
        largestCoverWidth(
          apple.replaceFirst('600x600', '1500x1500'),
          square: false,
        ),
        1000,
      );
    });

    test('a named size is the width assumed for it', () {
      expect(
        largestCoverWidth(
          'https://images.igdb.com/igdb/image/upload/t_cover_big/co1.jpg',
          square: false,
        ),
        810,
      );
      expect(
        largestCoverWidth(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx1.jpg',
          square: false,
        ),
        460,
      );
      expect(
        largestCoverWidth(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx1.jpg',
          square: false,
        ),
        230,
      );
      expect(
        largestCoverWidth(
          'https://covers.openlibrary.org/b/olid/OL1M-L.jpg?default=false',
          square: false,
        ),
        500,
      );
    });

    test('one of your own files, or an unknown server, says nothing', () {
      expect(
        largestCoverWidth(
          'repo:movies/the-mummy-1999.a3f9c2e.jpg',
          square: false,
        ),
        isNull,
      );
      expect(
        largestCoverWidth('https://example.com/a.jpg', square: false),
        isNull,
      );
    });
  });

  group('the sharpest of the choices', () {
    test('the widest, when a quarter wider than another', () {
      expect(sharpestCovers([460, 780, 460]), {1});
      // Exactly a quarter is enough; a little under is not.
      expect(sharpestCovers([400, 500]), {1});
      expect(sharpestCovers([400, 499]), isEmpty);
    });

    test('all about the same: none', () {
      expect(sharpestCovers([780, 780, 780]), isEmpty);
      expect(sharpestCovers([780, 810]), isEmpty);
      expect(sharpestCovers([780]), isEmpty);
      expect(sharpestCovers([]), isEmpty);
    });

    test('several equally wide are all the sharpest', () {
      expect(sharpestCovers([780, 500, 780]), {0, 2});
    });

    test('a choice of unknown width is left out', () {
      expect(sharpestCovers([null, 780, 500]), {1});
      expect(sharpestCovers([null, 780]), isEmpty);
    });
  });
}
