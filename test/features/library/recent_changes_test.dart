import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/preferences/preferences_store.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/library/recent_changes.dart';

import '../../helpers/sample_library.dart';

void main() {
  final now = DateTime(2026, 10, 28, 9, 30);
  setUp(() => seasonClock = () => now);
  tearDown(() => seasonClock = DateTime.now);

  test('update stamps changed entries, keeps the rest, drops the gone', () {
    final library = sampleLibrary();
    final before = {
      mummy.id: DateTime(2026, 10, 1),
      dirt.id: DateTime(2026, 10, 2),
      'movies/gone': DateTime(2026, 9, 1),
    };
    final changed = library.copyWith(
      entries: [
        for (final e in library.entries)
          e.id == mummy.id ? e.copyWith(status: EntryStatus.want) : e,
      ],
    );
    final after = RecentChanges.update(
      before,
      previous: library,
      next: changed,
      now: now,
    );
    expect(after, {mummy.id: now, dirt.id: DateTime(2026, 10, 2)});

    // The first load has nothing to compare with: only pruning.
    final pruned = RecentChanges.update(
      before,
      previous: null,
      next: library,
      now: now,
    );
    expect(pruned, {
      mummy.id: DateTime(2026, 10, 1),
      dirt.id: DateTime(2026, 10, 2),
    });
    // Nothing to change keeps the same map, so nothing is saved.
    expect(
      identical(
        RecentChanges.update(
          pruned,
          previous: library,
          next: library,
          now: now,
        ),
        pruned,
      ),
      isTrue,
    );
  });

  test('to and from JSON, skipping what does not parse', () {
    final json = RecentChanges.toJson({mummy.id: now});
    expect(json, {mummy.id: '2026-10-28T09:30:00.000'});
    expect(RecentChanges.fromJson({...json, 'x': 'soon', 'y': 3}), {
      mummy.id: now,
    });
  });

  test('a change applied to the library is stamped and saved', () async {
    final store = MemoryPreferencesStore();
    final container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(
            loadJson: () async => encodeLibrary(sampleLibrary()),
          ),
        ),
        recentChangesStoreProvider.overrideWithValue(store),
        initialRecentChangesProvider.overrideWithValue({
          'movies/gone': DateTime(2026, 9, 1),
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(recentChangesProvider, (_, _) {});
    await container.read(libraryProvider.future);
    await Future<void>.delayed(Duration.zero);
    // The first library only prunes the stamp of an entry that is gone.
    expect(container.read(recentChangesProvider), isEmpty);
    expect(store.saved, isEmpty);

    // Dirt is Done in the sample; wanting it again is a change.
    expect(dirt.status, EntryStatus.done);
    await container
        .read(libraryRepositoryProvider)
        .apply(SetStatus(dirt.id, EntryStatus.want));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(recentChangesProvider), {dirt.id: now});
    expect(store.saved, {dirt.id: now.toIso8601String()});
  });
}
