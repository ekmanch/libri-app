import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/features/entry/similar_tags.dart';

void main() {
  test('normalizeTag cleans up what was typed', () {
    expect(normalizeTag('  #Sci Fi  '), 'sci-fi');
    expect(normalizeTag('stop__motion'), 'stop-motion');
    expect(normalizeTag('--odd--'), 'odd');
    expect(normalizeTag('#'), '');
  });

  test('normalizeTag keeps a tag to the data repo\'s rule', () {
    expect(normalizeTag('2.5D'), '2.5d');
    expect(normalizeTag('Dr. Who'), 'dr-who');
    expect(normalizeTag('sci.fi'), 'sci-fi');
    expect(normalizeTag('2..5d'), '2-5d');
    expect(normalizeTag('v2.'), 'v2');
    expect(normalizeTag('Nesbø'), 'nesbo');
    expect(normalizeTag("Hitchcock's"), 'hitchcocks');
  });

  group('a tag with "&"', () {
    test('a valid tag is kept as it is', () {
      for (final tag in ['r&b', 'drum&bass', '2.5d', 'a&b&c', '90s&00s']) {
        expect(normalizeTag(tag), tag);
      }
    });

    test('what the rule forbids is cleaned up', () {
      expect(normalizeTag('&rb'), 'rb');
      expect(normalizeTag('rb&'), 'rb');
      expect(normalizeTag('r&&b'), 'r&b');
      expect(normalizeTag('r-&b'), 'r&b');
      expect(normalizeTag('r&-b'), 'r&b');
      expect(normalizeTag('r-&-b'), 'r&b');
      expect(normalizeTag('r--&&--b'), 'r&b');
      expect(normalizeTag('-&-rb-&-'), 'rb');
      expect(normalizeTag('&'), '');
      // The desktop's cases (`normalize_tag` in libri-kde's `text.rs`).
      expect(normalizeTag('drum -&bass'), 'drum&bass');
      expect(normalizeTag('r & & b'), 'r&b');
      expect(normalizeTag('&rb&'), 'rb');
      expect(normalizeTag('- & r&b & -'), 'r&b');
      expect(normalizeTag('2.5&3'), '2.5&3');
      // Never next to a dot: the dot is not between two digits.
      expect(normalizeTag('2.&5'), '2&5');
      expect(normalizeTag('2&.5'), '2&5');
      expect(normalizeTag('2.5&d'), '2.5&d');
    });

    test('typing drops the spaces around it', () {
      expect(normalizeTag('r & b'), 'r&b');
      expect(normalizeTag('rock & roll'), 'rock&roll');
      expect(normalizeTag('R&B'), 'r&b');
      expect(normalizeTag('#R & B'), 'r&b');
      expect(normalizeTag('Sci-Fi & Fantasy'), 'sci-fi&fantasy');
      expect(normalizeTag('Drum  &  Bass music'), 'drum&bass-music');
      // A typed "and" stays a word.
      expect(normalizeTag('rock and roll'), 'rock-and-roll');
    });

    test('rnb, r-and-b and r-b are look-alikes of r&b, as on the desktop', () {
      for (final close in ['rnb', 'r-and-b', 'r-b']) {
        expect(findSimilarTag('r&b', [close]), close);
        expect(findSimilarTag(close, ['r&b']), 'r&b');
      }
      expect(findSimilarTag('R & B', ['r&b']), isNull);
      // Without an "&" on either side only the older checks apply.
      expect(findSimilarTag('rnb', ['r-b']), 'r-b');
      expect(findSimilarTag('rnb', ['r-and-b']), isNull);
      expect(findSimilarTag('r-b', ['r-and-b']), isNull);
    });

    test('an "&" is read as "and" or as nothing', () {
      expect(
        findSimilarTag('drum-and-bass', ['drums', 'drum&bass']),
        'drum&bass',
      );
      expect(findSimilarTag('drum&bass', ['drum-bass']), 'drum-bass');
      expect(findSimilarTag('drumnbass', ['drum&bass']), 'drum&bass');
      expect(findSimilarTag('drum-n-bass', ['drum&bass']), isNull);
      expect(findSimilarTag('rock&roll', ['rock', 'pop']), isNull);
    });

    test('contains a query typed with or without the spaces', () {
      expect(tagContains('r&b', 'r&b'), isTrue);
      expect(tagContains('r&b', 'r & b'), isTrue);
      expect(tagContains('r&b', 'r &'), isTrue);
      expect(tagContains('drum&bass', 'm & b'), isTrue);
      expect(tagContains('r&b', 'r & c'), isFalse);
      expect(tagContains('rock', '&'), isFalse);
      expect(tagContains('horror', 'orr'), isTrue);
    });

    test('a lookup\'s genre with "&" is the library\'s tags, or one tag', () {
      const library = {'scifi', 'fantasy', 'soul', 'funk', 'r&b', 'hiphop'};
      expect(canonicalTag('R&B'), 'r&b');
      expect(libraryTags('R&B', library), ['r&b']);
      expect(libraryTags('Sci-Fi & Fantasy', library), ['scifi', 'fantasy']);
      expect(libraryTags('Soul & Funk', library), ['soul', 'funk']);
      expect(libraryTags('R&B Soul', library), ['r&b', 'soul']);
      expect(libraryTags('Rap & Hip Hop', library), ['hiphop']);
      // A word the library has no tag for keeps the name whole.
      expect(libraryTags('Drum & Bass', library), ['drum&bass']);
    });
  });

  test('a dot counts like a hyphen in the similar check', () {
    expect(findSimilarTag('25d', ['2.5d']), '2.5d');
    expect(findSimilarTag('2-5d', ['2.5d']), '2.5d');
    expect(findSimilarTag('2.5d', ['2.5d']), isNull);
  });

  group('findSimilarTag', () {
    const tags = ['horror', 'scifi', 'cozy', 'ghibli', 'fantasy', 'rpg'];

    test('same once hyphens are ignored', () {
      expect(findSimilarTag('sci-fi', tags), 'scifi');
    });

    test('singular versus plural', () {
      expect(findSimilarTag('horrors', tags), 'horror');
      expect(findSimilarTag('fantasies', tags), 'fantasy');
    });

    test('one letter different, two for six letters or more', () {
      expect(findSimilarTag('cosy', tags), 'cozy');
      expect(findSimilarTag('jrpg', tags), 'rpg');
      expect(findSimilarTag('fantasie', tags), 'fantasy');
      expect(findSimilarTag('horrr', tags), 'horror');
    });

    test('two neighboring letters swapped', () {
      expect(findSimilarTag('ghilbi', tags), 'ghibli');
    });

    test('nothing close, or the same tag, gives null', () {
      expect(findSimilarTag('gothic', tags), isNull);
      expect(findSimilarTag('horror', tags), isNull);
      expect(findSimilarTag('cz', tags), isNull);
      expect(findSimilarTag('', tags), isNull);
    });

    test('prefers the hyphen match over an edit', () {
      expect(findSimilarTag('sci-fi', ['scify', 'scifi']), 'scifi');
    });
  });

  test('canonicalTag maps a lookup\'s synonyms to the library\'s spelling', () {
    expect(canonicalTag('Science Fiction'), 'scifi');
    expect(canonicalTag('sci-fi'), 'scifi');
    expect(canonicalTag('#Horror tales'), 'horror');
    expect(canonicalTag('Role-playing RPG'), 'rpg');
    expect(canonicalTag('grunge'), 'grunge');
    expect(canonicalTag('Rap/Hip Hop'), 'hiphop');
    expect(canonicalTag('Alternativmusik'), 'alternative');
    expect(canonicalTag('Filmmusik'), 'movie-music');
    expect(canonicalTag('Film Scores'), 'movie-music');
    expect(canonicalTag('Electro'), 'electronic');
  });

  test('libraryTags turns a genre made of the library\'s tags into them', () {
    const library = {'indie', 'pop', 'rock', 'electronic', 'hack-and-slash'};
    expect(libraryTags('Indie Pop', library), ['indie', 'pop']);
    expect(libraryTags('Indie Rock/Rock pop', library), [
      'indie',
      'rock',
      'pop',
    ]);
    expect(libraryTags('Electro Pop', library), ['electronic', 'pop']);
    expect(libraryTags('Hack and slash rock', library), [
      'hack-and-slash',
      'rock',
    ]);
    expect(libraryTags('Rock', library), ['rock']);
    // A word the library has no tag for keeps the name whole.
    expect(libraryTags('Indie Folk', library), ['indie-folk']);
    expect(libraryTags('Grunge', library), ['grunge']);
    // A tag like the whole name wins over its parts.
    expect(libraryTags('Pop Rock', {...library, 'poprock'}), ['pop-rock']);
  });
}
