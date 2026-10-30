import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/repository/local_library_repository.dart';
import 'package:library_app/data/settings_codec.dart';

import '../../helpers/sample_library.dart';

void main() {
  late Directory dir;
  late File file;
  final seedText = encodeLibrary(sampleLibrary());

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libri-local-');
    file = File('${dir.path}/library.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  LocalLibraryRepository repository({bool settings = false}) =>
      LocalLibraryRepository(
        file,
        seed: () async => seedText,
        settingsFile: settings ? File('${dir.path}/settings.json') : null,
      );

  test('settings live in settings.json beside the library', () async {
    final repo = repository(settings: true);
    expect(await repo.loadSettings(), AppSettings.defaults);
    final settingsFile = File('${dir.path}/settings.json');
    expect(settingsFile.readAsStringSync(), emptySettingsText);
    await repo.applySettings(const SetTimelineDefault(true));
    await repo.flush();
    expect(
      settingsFile.readAsStringSync(),
      contains('"timeline_default": true'),
    );

    final reopened = repository(settings: true);
    expect((await reopened.loadSettings()).timelineDefault, isTrue);
    final emitted = <AppSettings>[];
    final sub = reopened.watchSettings().listen(emitted.add);
    await reopened.applySettings(const SetDefaultPlatform(null));
    await pumpEventQueue();
    await sub.cancel();
    expect(emitted.map((s) => s.defaultPlatform), ['PC', null]);
    await reopened.delete();
    expect(settingsFile.existsSync(), isFalse);
  });

  test('without a settings file the settings stay in memory', () async {
    final repo = repository();
    await repo.applySettings(const SetTimelineDefault(true));
    expect((await repo.loadSettings()).timelineDefault, isTrue);
    expect(File('${dir.path}/settings.json').existsSync(), isFalse);
  });

  test('a new install starts from the seed and writes it out', () async {
    final library = await repository().load();
    expect(library, sampleLibrary());
    expect(file.readAsStringSync(), seedText);
  });

  test('changes survive a restart, written in the canonical form', () async {
    final first = repository();
    await first.apply(SetStatus(mummy.id, EntryStatus.want));
    await first.apply(const SetRating('music/dirt-alice-in-chains', null));

    final reopened = await repository().load();
    expect(reopened.entryById(mummy.id)!.status, EntryStatus.want);
    expect(reopened.entryById(dirt.id)!.rating, isNull);
    expect(file.readAsStringSync(), encodeLibrary(reopened));
  });

  test('an existing file is read, not replaced by the seed', () async {
    final edited = sampleLibrary().copyWith(entries: [mummy]);
    file.writeAsStringSync(encodeLibrary(edited));
    expect(await repository().load(), edited);
  });

  test('changes applied quickly are all written, newest last', () async {
    final repo = repository();
    await repo.load();
    await Future.wait([
      repo.apply(SetStatus(mummy.id, EntryStatus.want)),
      repo.apply(const SetRating('movies/the-mummy-1999', 3)),
      repo.apply(SetStatus(mummy.id, EntryStatus.dnf)),
    ]);
    final saved = decodeLibrary(file.readAsStringSync()).entryById(mummy.id)!;
    expect(saved.status, EntryStatus.dnf);
    expect(saved.rating, 3);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('an operation that changes nothing emits and writes nothing', () async {
    final repo = repository();
    final library = await repo.load();
    file.deleteSync();
    final emitted = <Object>[];
    final sub = repo.watch().skip(1).listen(emitted.add);
    final result = await repo.apply(const DeleteEntry('movies/missing'));
    await pumpEventQueue();
    await sub.cancel();
    expect(result, same(library));
    expect(emitted, isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('an unreadable file is kept aside and the seed is used', () async {
    file.writeAsStringSync('{ not json');
    final library = await repository().load();
    expect(library, sampleLibrary());
    final aside = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.unreadable'))
        .toList();
    expect(aside, hasLength(1));
    expect(aside.single.readAsStringSync(), '{ not json');
    expect(file.readAsStringSync(), seedText);
  });

  test('replace swaps in a whole library, emits it and writes it', () async {
    final repo = repository();
    await repo.load();
    final emitted = <Object>[];
    final sub = repo.watch().skip(1).listen(emitted.add);
    await pumpEventQueue(); // The stream is on the changes now.
    final edited = sampleLibrary().copyWith(entries: [mummy]);
    await repo.replace(edited);
    await repo.replace(edited); // The same again: nothing happens.
    await pumpEventQueue();
    await sub.cancel();
    expect(emitted, [edited]);
    expect(repo.current, edited);
    expect(file.readAsStringSync(), encodeLibrary(edited));
  });

  test('delete removes the file', () async {
    final repo = repository();
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await repo.delete();
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });
}
