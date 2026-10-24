import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/platform_names.dart';

void main() {
  test('platform aliases become one spelled-out name', () {
    for (final alias in [
      'PS5',
      'ps5',
      'PS 5',
      'Playstation 5',
      'playstation5',
    ]) {
      expect(normalizePlatform(alias), 'PlayStation 5', reason: alias);
    }
    expect(normalizePlatform('XSX'), 'Xbox Series X|S');
    expect(normalizePlatform('Nintendo Switch'), 'Switch');
    expect(normalizePlatform('nintendo switch 2'), 'Switch 2');
    expect(
      normalizePlatform('Super Nintendo Entertainment System'),
      'Super Nintendo',
    );
    expect(normalizePlatform('SNES'), 'Super Nintendo');
    expect(normalizePlatform('windows'), 'PC');
    expect(normalizePlatform('steam deck'), 'Steam Deck');
    // Unknown names keep their spelling, with spaces tidied.
    expect(normalizePlatform('  Amiga   500 '), 'Amiga 500');
  });
}
