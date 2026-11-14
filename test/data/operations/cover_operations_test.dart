import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/operations/entry_operations.dart';
import 'package:library_app/data/operations/operation_json.dart';

import '../../helpers/sample_library.dart';

void main() {
  const path = 'repo:movies/the-mummy-1999.a3f9c2e.jpg';

  test('SetCover picks one of your own files, and Keep mine stays with it', () {
    final library = sampleLibrary();
    final picked = SetCover(mummy.id, coverFrom: path).apply(library);
    expect(picked.entryById(mummy.id)!.coverFrom, path);
    expect(picked.entryById(mummy.id)!.coverKeepMine, isNull);
    expect(
      SetCover(mummy.id, coverFrom: path).summary(library),
      'Use your own cover for The Mummy',
    );

    final kept = SetCover(
      mummy.id,
      coverFrom: path,
      keepMine: true,
    ).apply(picked);
    expect(kept.entryById(mummy.id)!.coverKeepMine, isTrue);
    expect(
      SetCover(mummy.id, coverFrom: path, keepMine: true).summary(picked),
      'Keep your own cover for The Mummy',
    );

    // An online cover drops it, as does the match's own.
    final online = SetCover(
      mummy.id,
      coverFrom: 'tmdb:movie:1',
      keepMine: true,
    ).apply(kept);
    expect(online.entryById(mummy.id)!.coverFrom, 'tmdb:movie:1');
    expect(online.entryById(mummy.id)!.coverKeepMine, isNull);
    final match = SetCover(mummy.id).apply(kept);
    expect(match.entryById(mummy.id)!.coverFrom, isNull);
    expect(match.entryById(mummy.id)!.coverKeepMine, isNull);
    expect(SetCover(mummy.id).summary(kept), 'Change the cover of The Mummy');

    // Nothing to change, or no such entry: the same library.
    expect(identical(SetCover(mummy.id).apply(library), library), isTrue);
    expect(
      identical(const SetCover('movies/gone').apply(library), library),
      isTrue,
    );
  });

  test('SetCover goes through the queue as JSON', () {
    final operation = SetCover(mummy.id, coverFrom: path, keepMine: true);
    final json = encodeOperation(operation);
    expect(json['op'], 'setCover');
    final decoded = decodeOperation(json) as SetCover;
    expect(decoded.entryId, mummy.id);
    expect(decoded.coverFrom, path);
    expect(decoded.keepMine, isTrue);
  });

  test('saving an entry for other reasons keeps cover_keep_mine', () {
    final library = Library(
      entries: [mummy.copyWith(coverFrom: path, coverKeepMine: true)],
    );
    final rated = SetRating(mummy.id, 7).apply(library);
    expect(rated.entryById(mummy.id)!.coverKeepMine, isTrue);
    final edited = UpdateEntry(library.entries.single.copyWith(note: 'Again'))
        .apply(library);
    expect(edited.entryById(mummy.id)!.coverKeepMine, isTrue);
    // But never without one of your own covers beside it.
    final cleared = UpdateEntry(
      library.entries.single.copyWith(coverFrom: null),
    ).apply(library);
    expect(cleared.entryById(mummy.id)!.coverKeepMine, isNull);
  });

  test(
    'cover_keep_mine is written right after cover_from, only while true',
    () {
      final library = Library(
        entries: [
          mummy.copyWith(
            source: 'tmdb:movie:564',
            coverFrom: path,
            coverKeepMine: true,
          ),
          dirt,
        ],
      );
      final text = encodeLibrary(library);
      expect(
        text,
        contains(
          '"source": "tmdb:movie:564",\n'
          '      "cover_from": "$path",\n'
          '      "cover_keep_mine": true',
        ),
      );
      expect('cover_keep_mine'.allMatches(text), hasLength(1));
      expect(decodeLibrary(text), library);
      expect(encodeLibrary(decodeLibrary(text)), text);
    },
  );
}
