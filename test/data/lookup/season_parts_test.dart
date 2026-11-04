import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/season_parts.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/storage/json_file.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('season_parts'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('parts round-trip through the file; a bad one is left out', () async {
    final file = JsonFile(File('${dir.path}/season_parts.json'));
    const part = ComingPart(
      entryId: 'anime/frieren',
      season: 3,
      part: 2,
      released: Released(2027, 1),
    );
    await FileComingPartsStore(file).write([part]);
    expect(await FileComingPartsStore(file).read(), [part]);
    expect(part.key, 'anime/frieren#3.2');
    await file.write({
      'parts': [
        part.toJson(),
        {'entry_id': 'x'},
      ],
    });
    expect(await FileComingPartsStore(file).read(), [part]);
  });
}
