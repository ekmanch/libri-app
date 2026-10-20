import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/book_match.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/models/media_type.dart';

void main() {
  LookupMatch book(String source, String title, {String? creator}) =>
      LookupMatch(
        type: MediaType.books,
        title: title,
        source: source,
        creator: creator,
      );

  group('the same book', () {
    test('is the same title and author, case and punctuation aside', () {
      expect(
        sameBook(
          book(
            'openlibrary:OL1W',
            'The Weight of Angels',
            creator: 'John Boyne',
          ),
          book('itunes:1', 'the weight of angels', creator: 'JOHN BOYNE'),
        ),
        isTrue,
      );
      // One author in common is enough; the order does not matter.
      expect(
        sameBook(
          book(
            'openlibrary:OL2W',
            'Good Omens',
            creator: 'Terry Pratchett, Neil Gaiman',
          ),
          book('itunes:2', 'Good Omens', creator: 'Neil Gaiman'),
        ),
        isTrue,
      );
    });

    test('is not another title, nor another author, nor a missing one', () {
      final ol = book('openlibrary:OL1W', 'Dracula', creator: 'Bram Stoker');
      expect(
        sameBook(ol, book('itunes:1', 'Carmilla', creator: 'Bram Stoker')),
        isFalse,
      );
      expect(
        sameBook(ol, book('itunes:2', 'Dracula', creator: 'Dacre Stoker')),
        isFalse,
      );
      expect(sameBook(ol, book('itunes:3', 'Dracula')), isFalse);
      expect(
        sameBook(
          book('openlibrary:OL9W', 'Beowulf'),
          book('itunes:4', 'Beowulf'),
        ),
        isTrue,
      );
    });
  });

  group('the first publication year', () {
    test('is the earliest edition year', () {
      expect(firstPublishYear([1897, 1898, 1899, 1920]), 1897);
      expect(firstPublishYear([1983]), 1983);
      expect(firstPublishYear([1975, 1974, 1974]), 1974);
      expect(firstPublishYear([]), isNull);
    });

    test('skips a lone year more than a decade before the rest, as "King '
        'Rat" (1962) lists a 1950 edition', () {
      expect(firstPublishYear([1950, 1962, 1963, 1965, 1972, 2013]), 1962);
      // A placeholder year, then two lone years, then the real run.
      expect(firstPublishYear([1900, 1920, 1935, 1980, 1981]), 1980);
      // Exactly a decade apart is close enough.
      expect(firstPublishYear([1952, 1962, 1963]), 1952);
    });

    test('keeps the earliest year when no run of editions follows', () {
      expect(firstPublishYear([1920, 1980]), 1920);
      expect(firstPublishYear([1920, 1950, 1980]), 1920);
      expect(firstPublishYear([1975, 2010, 2010]), 1975);
    });
  });

  group('a volume number in a title', () {
    test('is read from "Vol.", "Volume" and "#"', () {
      expect(volumeOf('Berserk, Vol. 43'), (name: 'Berserk', number: 43));
      expect(volumeOf('Berserk Volume 1'), (name: 'Berserk', number: 1));
      expect(volumeOf('Berserk: vol 2'), (name: 'Berserk', number: 2));
      expect(volumeOf('Saga #5'), (name: 'Saga', number: 5));
      expect(volumeOf('Chainsaw Man, Vol. 11'), (
        name: 'Chainsaw Man',
        number: 11,
      ));
    });

    test('is nothing for other titles', () {
      expect(volumeOf('Dracula'), isNull);
      expect(volumeOf('Volume 3'), isNull);
      expect(volumeOf('The Two Towers'), isNull);
    });
  });
}
