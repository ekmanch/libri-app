import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/platform_release.dart';
import 'package:library_app/data/models/released.dart';

void main() {
  const consoles = Released(2026, 11, 19);
  const byPlatform = <String, Released?>{
    'PlayStation 5': consoles,
    'Xbox Series X|S': consoles,
    'PC': Released(2027, 3),
    'Switch 2': null,
  };

  group('datedPlatforms', () {
    test('the default platform alone when the entry names it', () {
      expect(datedPlatforms(['PS5', 'pc'], 'PC'), ['PC']);
      expect(datedPlatforms(['PlayStation 5', 'PC'], 'ps5'), ['PlayStation 5']);
    });

    test('else every platform of the entry, spelled out', () {
      expect(datedPlatforms(['PS5', 'Switch 2'], 'PC'), [
        'PlayStation 5',
        'Switch 2',
      ]);
      expect(datedPlatforms(['PS5'], null), ['PlayStation 5']);
      expect(datedPlatforms(const [], 'PC'), isEmpty);
    });
  });

  group('releaseOn', () {
    test('the first release among the platforms', () {
      expect(releaseOn(byPlatform, ['PC']), (
        listed: true,
        released: const Released(2027, 3),
      ));
      expect(releaseOn(byPlatform, ['pc', 'PS5']), (
        listed: true,
        released: consoles,
      ));
    });

    test('a platform listed without a date is not known yet', () {
      expect(releaseOn(byPlatform, ['Switch 2']), (
        listed: true,
        released: null,
      ));
      // A dated one beside it still counts.
      expect(releaseOn(byPlatform, ['Switch 2', 'PC']).released?.year, 2027);
    });

    test('platforms the lookup does not list, or none, are not listed', () {
      expect(releaseOn(byPlatform, ['Linux']).listed, isFalse);
      expect(releaseOn(byPlatform, const []).listed, isFalse);
      expect(releaseOn(const {}, ['PC']).listed, isFalse);
    });
  });
}
