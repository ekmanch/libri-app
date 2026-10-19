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
    expect(normalizeTag('Rock & Roll'), 'rock-roll');
    expect(normalizeTag('Dr. Who'), 'dr-who');
    expect(normalizeTag('sci.fi'), 'sci-fi');
    expect(normalizeTag('2..5d'), '2-5d');
    expect(normalizeTag('v2.'), 'v2');
    expect(normalizeTag('Nesbø'), 'nesbo');
    expect(normalizeTag("Hitchcock's"), 'hitchcocks');
    expect(normalizeTag('Sci-Fi & Fantasy'), 'sci-fi-fantasy');
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
  });
}
