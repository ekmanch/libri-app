import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/artwork_resolver.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/season_split_service.dart';
import 'package:library_app/data/lookup/season_split_store.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/season_span.dart';
import 'package:library_app/data/models/season_split.dart';
import 'package:library_app/dev/fake_lookup.dart';

/// The stored splits serve while they are young, unless they are stale
/// for the entry (owner's report, 2026-11-04: a list stored by the build
/// that did not fold Bleach's parts said five seasons where the entry
/// had two).
void main() {
  final now = DateTime(2026, 11, 4, 12);
  setUp(() => seasonClock = () => now);
  tearDown(() => seasonClock = DateTime.now);

  // Bleach as the sources split it now: the original and the Thousand-Year
  // Blood War folded; and as a build without ARM stored it: five.
  const folded = SeasonSplit(
    ids: [SeasonSplit.anilistId],
    seasons: [
      SeasonSpan(season: 1, episodes: 366, released: Released(2004, 10, 5)),
      SeasonSpan(season: 2, episodes: 50, released: Released(2022, 10, 11)),
    ],
  );
  const unfolded = SeasonSplit(
    ids: [SeasonSplit.anilistId],
    seasons: [
      SeasonSpan(season: 1, episodes: 366, released: Released(2004, 10, 5)),
      SeasonSpan(season: 2, episodes: 13, released: Released(2022, 10, 11)),
      SeasonSpan(season: 3, episodes: 13, released: Released(2023, 7, 8)),
      SeasonSpan(season: 4, episodes: 14, released: Released(2024, 10, 5)),
      SeasonSpan(season: 5, episodes: 10, released: Released(2026, 7, 25)),
    ],
  );
  const announced = SeasonSplit(
    ids: [SeasonSplit.anilistId],
    seasons: [
      SeasonSpan(season: 1, episodes: 366, released: Released(2004, 10, 5)),
      SeasonSpan(season: 2, episodes: 50, released: Released(2022, 10, 11)),
      SeasonSpan(season: 3, released: Released(2027, 10)),
    ],
  );

  Entry bleach({String? from = SeasonSplit.anilistId, bool byHand = false}) =>
      Entry(
        id: 'anime/bleach',
        type: MediaType.anime,
        title: 'Bleach',
        status: EntryStatus.done,
        added: DateTime(2026, 11, 4),
        source: 'anilist:269',
        kind: EntryKind.series,
        seasonsFrom: from,
        seasons: [
          Season(
            season: 1,
            released: const Released(2004, 10, 5),
            status: EntryStatus.done,
            manual: byHand ? true : null,
          ),
          Season(
            season: 2,
            released: const Released(2022, 10, 11),
            status: EntryStatus.done,
            manual: byHand ? true : null,
          ),
        ],
      );

  ({
    SeasonSplitService service,
    FakeLookupSource fake,
    MemorySeasonSplitStore store,
  })
  build() {
    final fake = FakeLookupSource(
      splitsBySource: {
        'anilist:269': const [folded],
      },
    );
    final lookups = LookupService([fake]);
    final store = MemorySeasonSplitStore();
    return (
      service: SeasonSplitService(
        lookups: lookups,
        store: store,
        resolver: ArtworkResolver(lookups: lookups),
      ),
      fake: fake,
      store: store,
    );
  }

  test('a young list serves; a stale one is read again and stored', () async {
    final b = build();
    final key = SeasonSplitService.keyFor('anilist:269', null);
    await b.store.write(key, const [announced], now);
    expect(await b.service.load(bleach()), const [announced]);
    expect(b.fake.calls, isEmpty);

    await b.store.write(key, const [unfolded], now);
    expect(await b.service.load(bleach()), const [folded]);
    expect(b.fake.calls, ['splits:anilist:269']);
    expect(b.store.splits[key]!.splits, const [folded]);
  });

  test('isStale: only the split the entry names, never seasons by hand', () {
    final today = DateTime(2026, 11, 4);
    expect(
      SeasonSplitService.isStale(bleach(), const [unfolded], today),
      isTrue,
    );
    expect(
      SeasonSplitService.isStale(bleach(), const [announced], today),
      isFalse,
    );
    expect(
      SeasonSplitService.isStale(bleach(), const [folded], today),
      isFalse,
    );
    expect(
      SeasonSplitService.isStale(bleach(from: 'tmdb:seasons'), const [
        unfolded,
      ], today),
      isFalse,
    );
    expect(
      SeasonSplitService.isStale(bleach(from: null), const [unfolded], today),
      isFalse,
    );
    expect(
      SeasonSplitService.isStale(bleach(from: null, byHand: true), const [
        unfolded,
      ], today),
      isFalse,
    );
    expect(unfolded.staleFor(const [], today), isTrue);
  });

  test('refresh reads again however young the list', () async {
    final b = build();
    final key = SeasonSplitService.keyFor('anilist:269', null);
    await b.store.write(key, const [announced], now);
    expect(await b.service.load(bleach(), refresh: true), const [folded]);
    expect(b.fake.calls, ['splits:anilist:269']);
  });
}
