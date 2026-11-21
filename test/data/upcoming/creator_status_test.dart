import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/storage/json_file.dart';
import 'package:library_app/data/upcoming/creator_status.dart';

void main() {
  late Directory dir;
  late File file;
  late FileCreatorStatusStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('creator_status');
    file = File('${dir.path}/creator_status.json');
    store = FileCreatorStatusStore(JsonFile(file));
  });

  tearDown(() => dir.delete(recursive: true));

  Map<String, Object?> record(String kind, String id, {String? died}) => {
    'kind': kind,
    'id': id,
    'providerId': 'x:$id',
    if (died != null) 'inactive': {'reason': 'died', 'year': int.parse(died)},
    'checkedOn': '2026-11-12',
  };

  test('a file from before version 2 asks again who died: the records of '
      'authors, artists and studios with no reason go, once', () async {
    await file.writeAsString(
      jsonEncode({
        'creators': [
          record('authors', 'charles-dickens'),
          record('authors', 'bram-stoker', died: '1912'),
          record('artists', 'eva cassidy'),
          record('studios', 'pixar'),
          record('directors', 'clint-eastwood'),
          record('actors', 'aaron-paul'),
        ],
      }),
    );
    final read = await store.read();
    expect(read.keys, [
      'authors/bram-stoker',
      'directors/clint-eastwood',
      'actors/aaron-paul',
    ]);

    // Asked again and written: the file is version 2 and keeps the answer.
    final dickens = CreatorStatus(
      kind: FollowKind.authors,
      id: 'charles-dickens',
      providerId: 'openlibrary:author:OL24638A',
      checkedOn: DateTime(2026, 11, 21),
    );
    await store.write({...read, dickens.key: dickens});
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(json['version'], FileCreatorStatusStore.version);
    final again = await store.read();
    expect(again.length, 4);
    expect(again['authors/charles-dickens'], dickens);
  });
}
