import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';

void main() {
  final file = File(FixtureLibraryRepository.assetPath);
  FixtureLibraryRepository repository() =>
      FixtureLibraryRepository(loadJson: file.readAsString);

  test('the fixture is complete and consistent', () async {
    final library = await repository().load();

    expect(library.version, 2);
    for (final type in MediaType.values) {
      expect(
        library.entriesOfType(type).length,
        greaterThanOrEqualTo(8),
        reason: type.name,
      );
    }
    expect(
      library.entries.map((e) => e.id).toSet().length,
      library.entries.length,
    );
    expect(library.plans.map((p) => p.id), [
      'halloween-2026',
      'christmas-2026',
      'halloween-2025',
    ]);

    final music = library.entriesOfType(MediaType.music);
    expect(
      music.where((e) => e.kind == EntryKind.album && e.tracks != null),
      isNotEmpty,
    );
    expect(
      music.where((e) => e.kind == EntryKind.song && e.album != null),
      isNotEmpty,
    );
    expect(
      music.where((e) => e.kind == EntryKind.song && e.album == null),
      isNotEmpty,
    );
    expect(music.where((e) => e.creator == 'Various Artists'), isNotEmpty);
    expect(music.where((e) => e.creator!.startsWith('The ')), isNotEmpty);
    expect(music.where((e) => RegExp(r'^\d').hasMatch(e.creator!)), isNotEmpty);

    expect(
      library.entries.where((e) => !e.isReleasedOn(DateTime(2026, 10, 10))),
      isNotEmpty,
    );
    expect(library.entries.where((e) => e.seasonalOnly), isNotEmpty);
    expect(
      library.entries.map((e) => e.status).toSet(),
      EntryStatus.values.toSet(),
    );
    for (final entry in library.entries) {
      expect(
        EntryStatus.optionsForEntry(entry),
        contains(entry.status),
        reason: entry.id,
      );
    }

    for (final plan in library.plans) {
      expect(plan.items, isNotEmpty);
      for (final item in plan.items) {
        expect(library.entryById(item.entry), isNotNull, reason: item.entry);
      }
    }
    final halloween = library.planById('halloween-2026')!;
    expect(
      halloween.items.where((i) => i.when?.isSingleDay == true),
      isNotEmpty,
    );
    expect(
      halloween.items.where((i) => i.when?.isSingleDay == false),
      isNotEmpty,
    );
    expect(halloween.items.where((i) => i.repeat), isNotEmpty);
    expect(halloween.items.where((i) => i.done), isNotEmpty);

    expect(library.usedTags, library.allTags);
  });

  test('ids follow the slug scheme', () async {
    final library = await repository().load();
    final pattern = RegExp(r'^[a-z]+/[a-z0-9]+(-[a-z0-9]+)*$');
    for (final entry in library.entries) {
      expect(entry.id, matches(pattern));
      expect(entry.id, startsWith('${entry.type.name}/'));
    }
  });

  test('apply changes only the in-memory copy', () async {
    final before = await file.readAsString();
    final repo = repository();
    final changed = await repo.apply(
      const SetStatus('movies/hereditary-2018', EntryStatus.done),
    );
    expect(
      changed.entryById('movies/hereditary-2018')!.status,
      EntryStatus.done,
    );
    expect(repo.current, changed);
    expect(
      (await repo.load()).entryById('movies/hereditary-2018')!.status,
      EntryStatus.done,
    );
    expect(await file.readAsString(), before);

    // A fresh repository starts from the file again.
    final fresh = await repository().load();
    expect(fresh.entryById('movies/hereditary-2018')!.status, EntryStatus.want);
  });

  test('watch emits the current library first, then every change', () async {
    final repo = repository();
    final seen = <int>[];
    final sub = repo.watch().listen((lib) {
      seen.add(lib.entryById('movies/hereditary-2018')!.rating ?? 0);
    });
    await repo.load();
    await Future<void>.delayed(Duration.zero);
    await repo.apply(const SetRating('movies/hereditary-2018', 6));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    repo.dispose();
    expect(seen, [0, 6]);
  });
}
