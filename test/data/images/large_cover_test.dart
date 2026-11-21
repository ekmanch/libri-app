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
}
