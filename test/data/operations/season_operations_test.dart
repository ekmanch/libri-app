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

final today = DateTime(2026, 10, 18);

void main() {
  setUp(() => seasonClock = () => today);
  tearDown(() => seasonClock = DateTime.now);

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

    test('New needs the mark, no status and the season out', () {
      expect(wednesday.hasNewSeasonOn(today), isTrue);
      expect(
        const Season(
          season: 2,
          fresh: true,
          status: EntryStatus.want,
        ).isNewOn(today),
        isFalse,
      );
      expect(const Season(season: 2).isNewOn(today), isFalse);
      const coming = Season(season: 3, released: Released(2027), fresh: true);
      expect(coming.isNewOn(today), isFalse);
      expect(coming.isNewOn(DateTime(2028)), isTrue);
    });

    test('manual is written only while true, after new', () {
      expect(const Season(season: 3, fresh: true, manual: true).toJson().keys, [
        'season',
        'released',
        'status',
        'new',
        'manual',
      ]);
    });
  });

  group('the show status from its seasons', () {
    EntryStatus status(List<EntryStatus?> statuses, {Released? last}) =>
        Season.showStatus([
          for (final (i, s) in statuses.indexed)
            Season(
              season: i + 1,
              released: i == statuses.length - 1 && last != null
                  ? last
                  : Released(2020 + i),
              status: s,
            ),
        ], today);
    const want = EntryStatus.want,
        watching = EntryStatus.inProgress,
        done = EntryStatus.done,
        dnf = EntryStatus.dnf;

    test('follows the rule in order', () {
      expect(status([done, watching, dnf]), watching);
      expect(status([done, dnf]), dnf);
      expect(status([done, done]), done);
      expect(status([done, want]), watching);
      expect(status([want, want]), want);
      expect(status([null, null]), want);
      expect(status([done, null]), done);
    });

    test('a season not out yet does not count', () {
      expect(status([done, want], last: const Released(2027)), done);
      expect(status([done, want], last: const Released(2026, 10, 1)), watching);
    });

    test('one season is that season\'s status, out or not', () {
      expect(status([null]), want);
      expect(status([done], last: const Released(2027)), done);
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
      expect(showIn(result).hasNewSeasonOn(today), isFalse);
    });

    test('clearing to Not set keeps a season New', () {
      final result = SetSeasonStatus(wednesday.id, 2, null).apply(withShow());
      expect(showIn(result).seasons![1].isNewOn(today), isTrue);
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
      // The show's status follows: three Done, the rest not set.
      expect(result.entryById(southPark.id)!.status, EntryStatus.done);
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

  group('the other season operations', () {
    test('SetSeasons puts the seasons back and the status with them', () {
      final done = MarkSeasonsDone(wednesday.id, 3).apply(withShow());
      final back = SetSeasons(wednesday.id, wednesday.seasons!).apply(done);
      expect(showIn(back).seasons, wednesday.seasons);
      expect(showIn(back).status, EntryStatus.done);
    });

    test('RemoveSeason drops one season; KeepSeason marks it manual', () {
      final removed = RemoveSeason(wednesday.id, 2).apply(withShow());
      expect([for (final s in showIn(removed).seasons!) s.season], [1]);
      expect(
        RemoveSeason(wednesday.id, 2).summary(withShow()),
        'Remove season 2 of Wednesday',
      );
      final kept = KeepSeason(wednesday.id, 2).apply(withShow());
      expect(showIn(kept).seasons![1].isManual, isTrue);
    });

    test('RefreshShowStatus writes what the seasons give', () {
      final stale = wednesday.copyWith(status: EntryStatus.want);
      final fixed = RefreshShowStatus(wednesday.id).apply(withShow(stale));
      expect(showIn(fixed).status, EntryStatus.done);
      expect(
        RefreshShowStatus(wednesday.id).summary(withShow()),
        'Update the status of Wednesday from its seasons',
      );
    });

    test('SetStatus on a show sets the seasons that are out', () {
      final coming = wednesday.copyWith(
        seasons: [
          ...wednesday.seasons!,
          const Season(season: 3, released: Released(2027)),
        ],
      );
      final result = SetStatus(
        wednesday.id,
        EntryStatus.done,
      ).apply(withShow(coming));
      final seasons = showIn(result).seasons!;
      expect(
        [for (final s in seasons) s.status],
        [EntryStatus.done, EntryStatus.done, null],
      );
      expect(seasons[1].fresh, isNull);
      expect(showIn(result).status, EntryStatus.done);
    });

    test('SetStatus on a one-season show is that season\'s status', () {
      final single = wednesday.copyWith(
        seasons: const [Season(season: 1, released: Released(2027))],
      );
      final result = SetStatus(
        wednesday.id,
        EntryStatus.want,
      ).apply(withShow(single));
      expect(showIn(result).seasons!.single.status, EntryStatus.want);
      expect(showIn(result).status, EntryStatus.want);
    });

    test('UpdateEntry and AddEntry write the status the seasons give', () {
      final edited = UpdateEntry(wednesday.copyWith(status: EntryStatus.dnf))
          .apply(withShow());
      expect(showIn(edited).status, EntryStatus.done);
      final added = AddEntry(
        wednesday.copyWith(id: 'shows/other', status: EntryStatus.dnf),
      ).apply(sampleLibrary());
      expect(added.entries.last.status, EntryStatus.done);
    });
  });

  group('the move to seasons', () {
    const out1 = Season(season: 1, released: Released(2020));
    const out2 = Season(season: 2, released: Released(2022));
    const coming = Season(season: 3, released: Released(2027));

    List<EntryStatus?> statuses(List<Season> seasons) => [
      for (final s in seasons) s.status,
    ];

    test('Want or Done goes to every season out', () {
      expect(
        statuses(
          carryOverStatus(const [out1, out2, coming], EntryStatus.done, today),
        ),
        [EntryStatus.done, EntryStatus.done, null],
      );
      expect(
        statuses(
          carryOverStatus(const [out1, out2, coming], EntryStatus.want, today),
        ),
        [EntryStatus.want, EntryStatus.want, null],
      );
    });

    test('In progress or DNF goes to the latest out, earlier ones Done', () {
      expect(
        statuses(
          carryOverStatus(
            const [out1, out2, coming],
            EntryStatus.inProgress,
            today,
          ),
        ),
        [EntryStatus.done, EntryStatus.inProgress, null],
      );
      expect(
        statuses(
          carryOverStatus(const [out1, out2, coming], EntryStatus.dnf, today),
        ),
        [EntryStatus.done, EntryStatus.dnf, null],
      );
    });

    test('seasons with any status are left alone; one season takes it', () {
      final set = [out1.copyWith(status: EntryStatus.want), out2];
      expect(carryOverStatus(set, EntryStatus.done, today), set);
      expect(
        statuses(carryOverStatus(const [coming], EntryStatus.done, today)),
        [EntryStatus.done],
      );
    });

    Entry oldShow(String slug, {String? source, List<Season>? seasons}) =>
        Entry(
          id: 'shows/$slug',
          type: MediaType.shows,
          title: slug,
          released: const Released(2019, 5),
          status: EntryStatus.inProgress,
          added: DateTime(2026),
          source: source,
          seasons: seasons,
        );

    test('a show without seasons gets a manual Season 1', () {
      final result = const MoveShowsToSeasons().apply(
        Library(entries: [oldShow('by-hand')]),
      );
      final show = result.entries.single;
      expect(show.released, isNull);
      expect(show.seasons, const [
        Season(
          season: 1,
          released: Released(2019, 5),
          status: EntryStatus.inProgress,
          manual: true,
        ),
      ]);
      expect(show.status, EntryStatus.inProgress);
      expect(needsSeasonMove(show), isFalse);
    });

    test('a show with seasons drops its date and carries its status', () {
      final result = const MoveShowsToSeasons().apply(
        Library(
          entries: [
            oldShow('fetched', seasons: const [out1, out2]),
          ],
        ),
      );
      final show = result.entries.single;
      expect(show.released, isNull);
      expect(statuses(show.seasons!), [
        EntryStatus.done,
        EntryStatus.inProgress,
      ]);
    });

    test('a linked show without seasons waits for the daily check', () {
      final linked = oldShow('linked', source: 'tmdb:tv:1');
      expect(needsSeasonMove(linked), isFalse);
      final library = Library(entries: [linked, mummy]);
      expect(const MoveShowsToSeasons().apply(library), library);
      expect(
        const MoveShowsToSeasons().summary(library),
        'Move show dates and statuses into seasons',
      );
    });
  });

  test('season operations survive a JSON round trip', () {
    final library = withShow();
    for (final operation in <LibraryOperation>[
      SetSeasonStatus(wednesday.id, 2, EntryStatus.dnf),
      SetSeasonStatus(wednesday.id, 1, null),
      MarkSeasonsDone(wednesday.id, 2),
      SetSeasons(wednesday.id, const [Season(season: 1)]),
      RemoveSeason(wednesday.id, 2),
      KeepSeason(wednesday.id, 2),
      RefreshShowStatus(wednesday.id),
      const MoveShowsToSeasons(),
      SetSeasonDates(wednesday.id, const [
        Season(season: 2, released: Released(2025, 8)),
      ]),
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
