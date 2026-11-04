import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/season_span.dart';
import 'package:library_app/data/models/season_split.dart';

void main() {
  final today = DateTime(2026, 11, 3);

  // Hunter x Hunter as its sources split it: AniList's one entry of 148,
  // TMDB's three seasons, a production group split alike, a story-arc
  // group of six, and an "absolute" group of one long season.
  const one = SeasonSplit(
    ids: [SeasonSplit.anilistId],
    seasons: [
      SeasonSpan(season: 1, episodes: 148, released: Released(2011, 10, 2)),
    ],
  );
  const three = SeasonSplit(
    ids: [SeasonSplit.tmdbSeasonsId],
    seasons: [
      SeasonSpan(season: 1, episodes: 62, released: Released(2011, 10, 2)),
      SeasonSpan(season: 2, episodes: 74, released: Released(2012, 12, 15)),
      SeasonSpan(season: 3, episodes: 12, released: Released(2014, 7, 7)),
    ],
  );
  const production = SeasonSplit(
    ids: ['tmdb:group:prod'],
    seasons: [
      SeasonSpan(season: 1, episodes: 62, released: Released(2011, 10, 2)),
      SeasonSpan(season: 2, episodes: 74, released: Released(2013, 1, 20)),
      SeasonSpan(season: 3, episodes: 12, released: Released(2014, 7, 8)),
    ],
  );
  const arcs = SeasonSplit(
    ids: ['tmdb:group:arcs'],
    arcs: true,
    seasons: [
      SeasonSpan(
        season: 1,
        name: 'Hunter Exam',
        episodes: 26,
        released: Released(2011, 10, 2),
      ),
      SeasonSpan(
        season: 2,
        name: 'Heavens Arena',
        episodes: 12,
        released: Released(2012, 4, 15),
      ),
      SeasonSpan(
        season: 3,
        name: 'Phantom Troupe',
        episodes: 20,
        released: Released(2012, 7, 15),
      ),
      SeasonSpan(
        season: 4,
        name: 'Greed Island',
        episodes: 17,
        released: Released(2012, 12, 16),
      ),
      SeasonSpan(
        season: 5,
        name: 'Chimera Ant',
        episodes: 61,
        released: Released(2013, 4, 21),
      ),
      SeasonSpan(
        season: 6,
        name: 'Election',
        episodes: 12,
        released: Released(2014, 7, 8),
      ),
    ],
  );
  const absolute = SeasonSplit(
    ids: ['tmdb:group:abs'],
    seasons: [
      SeasonSpan(season: 1, episodes: 148, released: Released(2011, 10, 2)),
    ],
  );
  final moreArcs = SeasonSplit(
    ids: const ['tmdb:group:nine'],
    arcs: true,
    seasons: [for (var n = 1; n <= 9; n++) SeasonSpan(season: n, episodes: 10)],
  );

  group('distinct', () {
    test('splits alike are one, with every id, the first standing', () {
      final splits = SeasonSplit.distinct([
        one,
        three,
        production,
        arcs,
        absolute,
      ]);
      expect(splits.map((s) => s.id), [
        SeasonSplit.anilistId,
        SeasonSplit.tmdbSeasonsId,
        'tmdb:group:arcs',
      ]);
      expect(splits[0].ids, [SeasonSplit.anilistId, 'tmdb:group:abs']);
      expect(splits[1].ids, [SeasonSplit.tmdbSeasonsId, 'tmdb:group:prod']);
      // The first's dates stand.
      expect(splits[1].seasons[1].released, const Released(2012, 12, 15));
      expect(splits[1].has('tmdb:group:prod'), isTrue);
    });

    test('an arcs split alike to a plain one names its seasons', () {
      const plain = SeasonSplit(
        ids: ['tmdb:group:plain'],
        seasons: [
          SeasonSpan(season: 1, episodes: 5),
          SeasonSpan(season: 2, episodes: 7),
          SeasonSpan(season: 3),
        ],
      );
      const named = SeasonSplit(
        ids: ['tmdb:group:named'],
        arcs: true,
        seasons: [
          SeasonSpan(season: 1, name: 'A', episodes: 5),
          SeasonSpan(season: 2, name: 'B', episodes: 7),
        ],
      );
      final folded = SeasonSplit.distinct([plain, named]).single;
      expect(folded.arcs, isTrue);
      expect(folded.ids, ['tmdb:group:plain', 'tmdb:group:named']);
      expect(folded.names, {1: 'A', 2: 'B'});
      // The announced third season is kept.
      expect(folded.count, 3);
    });

    test('a shape unknown yet tells by the count alone', () {
      const a = SeasonSplit(ids: ['a'], seasons: [SeasonSpan(season: 1)]);
      const b = SeasonSplit(
        ids: ['b'],
        seasons: [SeasonSpan(season: 1), SeasonSpan(season: 2)],
      );
      expect(SeasonSplit.distinct([a, b]), hasLength(2));
      expect(
        SeasonSplit.distinct([
          a,
          a.copyWith(ids: ['c']),
        ]),
        hasLength(1),
      );
    });
  });

  group('automatic (owner\'s decision, 2026-11-04)', () {
    final long = one.copyWith(long: true);

    test('a long run takes the coarsest arcs split', () {
      expect(SeasonSplit.automatic([long, three, moreArcs, arcs]), arcs);
      // Among the arcs splits alone: no regular list, the first stands.
      expect(SeasonSplit.automatic([moreArcs, arcs]), moreArcs);
    });

    test('else the regular list, the chain\'s before TMDB\'s, arcs or not', () {
      expect(SeasonSplit.automatic([one, three, moreArcs, arcs]), one);
      expect(SeasonSplit.automatic([three, one, arcs]), one);
      expect(SeasonSplit.automatic([three, arcs]), three);
      expect(SeasonSplit.automatic([three, absolute]), three);
    });

    test('a long run without arcs keeps its regular list', () {
      expect(SeasonSplit.automatic([long, three]), long);
      expect(SeasonSplit.automatic([long]), long);
      expect(SeasonSplit.automatic([]), isNull);
    });

    test('shortlist keeps the automatic one and the first others', () {
      final many = [
        for (var i = 0; i < 9; i++) three.copyWith(ids: ['tmdb:group:$i']),
      ];
      final listed = SeasonSplit.shortlist([...many, long, arcs]);
      expect(listed, hasLength(SeasonSplit.maxListed));
      expect(listed.first, arcs);
      expect(listed.sublist(1), many.sublist(0, 5));
      expect(SeasonSplit.shortlist([one, three]), [one, three]);
    });
  });

  group('labels', () {
    test('a service is named beside the count, its seasons as it names '
        'them (owner\'s decision, 2026-11-04)', () {
      final netflix = SeasonSplit(
        ids: const ['tmdb:group:nf'],
        service: 'Netflix',
        seasons: const [
          SeasonSpan(season: 1, name: 'East Blue', episodes: 61),
          SeasonSpan(season: 2, name: 'Alabasta', episodes: 82),
        ],
      );
      expect(netflix.label, '2 seasons · Netflix');
      expect(netflix.detail, 'East Blue, Alabasta');
      expect(netflix.names, {1: 'East Blue', 2: 'Alabasta'});
      // Bare names dropped by the source: the counts tell.
      final bare = netflix.copyWith(
        seasons: const [
          SeasonSpan(season: 1, episodes: 61),
          SeasonSpan(season: 2, episodes: 82),
        ],
      );
      expect(bare.detail, '61 and 82 episodes');
      expect(bare.names, isEmpty);
      expect(
        arcs.copyWith(service: 'Crunchyroll').label,
        '6 seasons, one per arc · Crunchyroll',
      );
      // Folded with a plain split that stands first, the service carries.
      final folded = SeasonSplit.distinct([
        bare.copyWith(ids: const ['tmdb:group:plain'], service: null),
        netflix,
      ]).single;
      expect(folded.service, 'Netflix');
      expect(folded.names, {1: 'East Blue', 2: 'Alabasta'});
    });

    test('by shape alone', () {
      expect(one.label, 'One season');
      expect(one.detail, '148 episodes');
      expect(three.label, '3 seasons');
      expect(three.detail, 'By year: 62, 74 and 12 episodes');
      expect(arcs.label, '6 seasons, one per arc');
      expect(
        arcs.detail,
        'Hunter Exam, Heavens Arena, Phantom Troupe, Greed Island, '
        'Chimera Ant, Election',
      );
    });

    test('seasons in one year, and seasons still coming', () {
      const frieren = SeasonSplit(
        ids: [SeasonSplit.anilistId],
        seasons: [
          SeasonSpan(season: 1, episodes: 28, released: Released(2023, 9, 29)),
          SeasonSpan(season: 2, episodes: 10, released: Released(2026, 1, 16)),
          SeasonSpan(season: 3, released: Released(2027, 10)),
        ],
      );
      expect(frieren.label, '3 seasons');
      expect(frieren.detail, 'By year: 28 and 10 episodes, one more coming');
      const sameYear = SeasonSplit(
        ids: ['x'],
        seasons: [
          SeasonSpan(season: 1, episodes: 12, released: Released(2024, 1, 5)),
          SeasonSpan(season: 2, episodes: 12, released: Released(2024, 7, 5)),
        ],
      );
      expect(sameYear.detail, '12 and 12 episodes');
      const unknown = SeasonSplit(
        ids: ['y'],
        seasons: [SeasonSpan(season: 1), SeasonSpan(season: 2)],
      );
      expect(unknown.detail, 'Episode counts not known yet');
    });
  });

  group('fitting', () {
    const seasons = [
      Season(
        season: 1,
        released: Released(2011, 10, 2),
        status: EntryStatus.done,
      ),
      Season(
        season: 2,
        released: Released(2012, 12, 15),
        status: EntryStatus.done,
      ),
    ];

    test('the split that fits with the fewest seasons beyond', () {
      expect(SeasonSplit.fitting([one, three, arcs], seasons, today), three);
      // One season of 148 fits the plain list's first too, and the arcs':
      // the exact fit wins.
      expect(
        SeasonSplit.fitting([three, arcs, one], [seasons.first], today),
        one,
      );
    });

    test('a season out and dated otherwise does not fit', () {
      final moved = [
        seasons.first,
        seasons.last.copyWith(released: const Released(2013, 1, 20)),
      ];
      expect(three.fits(moved, today), isFalse);
      expect(production.fits(moved, today), isTrue);
      // A manual season, or one not out yet, is not held against a split.
      expect(
        three.fits([
          seasons.first,
          const Season(season: 2, released: Released(2027), manual: true),
        ], today),
        isTrue,
      );
      expect(
        three.fits([
          seasons.first,
          const Season(season: 2, released: Released(2027)),
        ], today),
        isTrue,
      );
      expect(three.fits([const Season(season: 7)], today), isFalse);
    });
  });

  group('seasonsFrom', () {
    test('statuses move with the episodes, split or merged', () {
      const inThree = [
        Season(season: 1, status: EntryStatus.done),
        Season(season: 2, status: EntryStatus.done),
        Season(season: 3, status: EntryStatus.inProgress),
      ];
      final inArcs = arcs.seasonsFrom(inThree, current: three, today: today);
      expect(inArcs.map((s) => s.status), [
        EntryStatus.done,
        EntryStatus.done,
        EntryStatus.done,
        // Greed Island: episodes 59 to 75, across seasons 1 and 2, both Done.
        EntryStatus.done,
        // Chimera Ant: episodes 76 to 136, in season 2 (Done), but 137 on
        // belong to Election.
        EntryStatus.done,
        EntryStatus.inProgress,
      ]);
      expect(inArcs.map((s) => s.season), [1, 2, 3, 4, 5, 6]);
      expect(inArcs.first.released, const Released(2011, 10, 2));
      // Back: season 2 of three spans Phantom Troupe (Done) to Chimera Ant
      // (Done) → Done; season 3 is Election → In progress.
      final back = three.seasonsFrom(inArcs, current: arcs, today: today);
      expect(back.map((s) => s.status), [
        EntryStatus.done,
        EntryStatus.done,
        EntryStatus.inProgress,
      ]);
      // Into one: Done and In progress together is In progress.
      final merged = one.seasonsFrom(inThree, current: three, today: today);
      expect(merged.single.status, EntryStatus.inProgress);
    });

    test('with no split to count by, the status of the same number', () {
      const byHand = [
        Season(season: 1, status: EntryStatus.done, manual: true),
        Season(season: 2, status: EntryStatus.want, manual: true),
      ];
      final moved = three.seasonsFrom(byHand, today: today);
      expect(moved.map((s) => s.status), [
        EntryStatus.done,
        EntryStatus.want,
        null,
      ]);
      expect(moved.every((s) => !s.isManual), isTrue);
      expect(moved.last.fresh, isNull);
      final marked = three.seasonsFrom(byHand, today: today, markNew: true);
      expect(marked.last.fresh, isTrue);
    });
  });

  test('a split survives a JSON round trip', () {
    expect(SeasonSplit.fromJson(arcs.toJson()), arcs);
    expect(arcs.toJson()['seasons'], isA<List<Object?>>());
    expect(SeasonSplit.fromJson(one.toJson()), one);
    expect(one.toJson()['arcs'], isFalse);
  });
}
