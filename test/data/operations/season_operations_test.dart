import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';

import '../../helpers/sample_library.dart';

final wednesday = Entry(
  id: 'shows/wednesday-2022',
  type: MediaType.shows,
  title: 'Wednesday',
  released: const Released(2022, 11, 23),
  status: EntryStatus.inProgress,
  added: DateTime(2026, 1, 2),
  seasons: const [
    Season(
      season: 1,
      released: Released(2022, 11, 23),
      status: EntryStatus.done,
    ),
    Season(season: 2, released: Released(2025, 8, 6), fresh: true),
  ],
);

Library withShow([Entry? show]) {
  final library = sampleLibrary();
  return library.copyWith(entries: [...library.entries, show ?? wednesday]);
}

Entry showIn(Library library) => library.entryById(wednesday.id)!;

void main() {
  group('Season in the file', () {
    test('writes season, released and status, and new only while true', () {
      expect(wednesday.seasons![0].toJson(), {
        'season': 1,
        'released': '2022-11-23',
        'status': 'done',
      });
      expect(wednesday.seasons![1].toJson(), {
        'season': 2,
        'released': '2025-08-06',
        'status': null,
        'new': true,
      });
      expect(const Season(season: 3).toJson(), {
        'season': 3,
        'released': null,
        'status': null,
      });
    });

    test('a show with seasons re-encodes byte-identically', () {
      final text = encodeLibrary(withShow());
      expect(text, contains('"seasons": [\n'));
      expect(encodeLibrary(decodeLibrary(text)), text);
    });

    test('seasons are omitted when absent, and come last', () {
      expect(mummy.toJson().containsKey('seasons'), isFalse);
      expect(wednesday.toJson().keys.last, 'seasons');
    });

    test('the year counts from the first season', () {
      expect(wednesday.copyWith(released: const Released(2024)).year, 2022);
      expect(wednesday.copyWith(seasons: null).year, 2022);
    });

    test('New needs the mark and no status', () {
      expect(wednesday.hasNewSeason, isTrue);
      expect(
        const Season(season: 2, fresh: true, status: EntryStatus.want).isNew,
        isFalse,
      );
      expect(const Season(season: 2).isNew, isFalse);
    });
  });

  group('SetSeasonStatus', () {
    test('sets one season and clears its New mark', () {
      final result = SetSeasonStatus(
        wednesday.id,
        2,
        EntryStatus.inProgress,
      ).apply(withShow());
      final seasons = showIn(result).seasons!;
      expect(seasons[1].status, EntryStatus.inProgress);
      expect(seasons[1].fresh, isNull);
      expect(seasons[0], wednesday.seasons![0]);
      expect(showIn(result).status, EntryStatus.inProgress);
      expect(showIn(result).hasNewSeason, isFalse);
    });

    test('clearing to Not set keeps a season New', () {
      final result = SetSeasonStatus(wednesday.id, 2, null).apply(withShow());
      expect(showIn(result).seasons![1].isNew, isTrue);
      final cleared = SetSeasonStatus(wednesday.id, 1, null).apply(result);
      expect(showIn(cleared).seasons![0].status, isNull);
    });

    test('a missing show or season leaves the library unchanged', () {
      final library = withShow();
      expect(
        SetSeasonStatus(wednesday.id, 9, EntryStatus.done).apply(library),
        library,
      );
      expect(
        const SetSeasonStatus('nope', 1, EntryStatus.done).apply(library),
        library,
      );
      expect(
        SetSeasonStatus(mummy.id, 1, EntryStatus.done).apply(library),
        library,
      );
    });
  });

  group('MarkSeasonsDone', () {
    final southPark = Entry(
      id: 'shows/south-park-1997',
      type: MediaType.shows,
      title: 'South Park',
      status: EntryStatus.want,
      added: DateTime(2026, 10, 18),
      seasons: [for (var n = 1; n <= 5; n++) Season(season: n)],
    );

    test('marks every earlier season Done and nothing else', () {
      final library = withShow(southPark);
      final result = MarkSeasonsDone(southPark.id, 4).apply(library);
      final seasons = result.entryById(southPark.id)!.seasons!;
      expect(
        [for (final s in seasons) s.status],
        [EntryStatus.done, EntryStatus.done, EntryStatus.done, null, null],
      );
      expect(result.entryById(southPark.id)!.status, EntryStatus.want);
      expect(
        MarkSeasonsDone(southPark.id, 4).summary(library),
        'Mark South Park seasons 1–3 as done',
      );
      expect(
        MarkSeasonsDone(southPark.id, 2).summary(library),
        'Mark South Park season 1 as done',
      );
    });
  });

  group('AddSeasons', () {
    const third = Season(season: 3, released: Released(2026, 10, 30));

    test('adds only seasons above the highest, at the end', () {
      final result = AddSeasons(wednesday.id, const [
        Season(season: 1),
        Season(season: 2),
        third,
      ]).apply(withShow());
      expect([for (final s in showIn(result).seasons!) s.season], [1, 2, 3]);
      expect(showIn(result).seasons![1], wednesday.seasons![1]);
    });

    test('a removed middle season never comes back', () {
      final gap = wednesday.copyWith(seasons: [wednesday.seasons![1]]);
      final result = AddSeasons(wednesday.id, [
        const Season(season: 1),
        wednesday.seasons![1],
      ]).apply(withShow(gap));
      expect([for (final s in showIn(result).seasons!) s.season], [2]);
    });

    test('applies once: a second run after a conflict adds nothing', () {
      const op = AddSeasons('shows/wednesday-2022', [third]);
      final once = op.apply(withShow());
      expect(op.apply(once), once);
    });

    test('fills in a show that had none', () {
      final result = AddSeasons(wednesday.id, const [
        Season(season: 2),
        Season(season: 1),
      ]).apply(withShow(wednesday.copyWith(seasons: null)));
      expect([for (final s in showIn(result).seasons!) s.season], [1, 2]);
    });

    test('summarizes the seasons it adds', () {
      expect(
        const AddSeasons('shows/wednesday-2022', [third]).summary(withShow()),
        'Add season 3 of Wednesday',
      );
      expect(seasonsPhrase([1, 2, 3, 4]), 'seasons 1–4');
      expect(seasonsPhrase([2, 4, 5]), 'seasons 2, 4 and 5');
    });
  });

  test('season operations survive a JSON round trip', () {
    final library = withShow();
    for (final operation in <LibraryOperation>[
      SetSeasonStatus(wednesday.id, 2, EntryStatus.dnf),
      SetSeasonStatus(wednesday.id, 1, null),
      MarkSeasonsDone(wednesday.id, 2),
      AddSeasons(wednesday.id, const [
        Season(season: 3, released: Released(2026, 10), fresh: true),
      ]),
    ]) {
      final decoded = decodeOperation(encodeOperation(operation));
      expect(decoded.apply(library), operation.apply(library));
      expect(decoded.summary(library), operation.summary(library));
    }
  });
}
