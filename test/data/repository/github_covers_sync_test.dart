import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/github/git_blob.dart';
import 'package:library_app/data/github/github_api.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/operations/entry_operations.dart';
import 'package:library_app/data/repository/github_library_repository.dart';
import 'package:library_app/data/storage/json_file.dart';
import 'package:library_app/data/sync/sync_status.dart';
import 'package:library_app/dev/fake_github_api.dart';

import '../../helpers/sample_library.dart';

Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  late Directory dir;
  late FakeGitHubApi github;
  late CoverStore covers;
  late GitHubLibraryRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libri-cover-sync');
    github = FakeGitHubApi(
      files: {'library.json': encodeLibrary(sampleLibrary())},
    );
    final sep = Platform.pathSeparator;
    covers = CoverStore(
      directory: Directory('${dir.path}${sep}covers'),
      remote: GitHubCoverRemote(
        github,
        branch: 'main',
        libraryFile: 'library.json',
      ),
      listFile: JsonFile(File('${dir.path}${sep}covers.json')),
      queueFile: JsonFile(File('${dir.path}${sep}cover_changes.json')),
      log: (_) {},
    );
    repo = GitHubLibraryRepository(
      directory: dir,
      api: github,
      repository: 'ekmanch/library',
      path: 'library.json',
      branch: 'main',
      covers: covers,
      debounce: const Duration(hours: 1),
      log: (_) {},
    );
  });
  tearDown(() async {
    await repo.flush();
    repo.dispose();
    dir.deleteSync(recursive: true);
  });

  List<String> writes() => [
    for (final r in github.requests)
      if (r.startsWith('PUT') || r.startsWith('DELETE')) r,
  ];

  const path = 'movies/the-mummy-1999.abc1234.jpg';

  Future<void> upload() async {
    final data = bytes('picture');
    await covers.add(
      path,
      data,
      sha: gitBlobSha(data),
      summary: 'Add a cover for The Mummy',
    );
    await repo.apply(SetCover(mummy.id, coverFrom: 'repo:$path'));
  }

  test('the covers are listed at the first sync', () async {
    github.setBytes('covers/movies/old-poster.png', bytes('old'));
    await repo.load();
    await repo.flush();
    expect(covers.files.single.path, 'movies/old-poster.png');
  });

  test('the file reaches GitHub before the entry that points at it', () async {
    await repo.load();
    await repo.flush();
    github.requests.clear();
    await upload();
    // The cover file counts as a change waiting to be saved.
    expect(repo.status.pendingCount, 2);

    await repo.syncNow();
    expect(writes(), ['PUT covers/$path', 'PUT library.json']);
    expect(github.text('library.json'), contains('"cover_from": "repo:$path"'));
    expect(github.bytes('covers/$path'), bytes('picture'));
    expect(repo.status.pendingCount, 0);
    expect(repo.status.phase, SyncPhase.idle);
  });

  test('offline, both wait; the next sync sends the file first', () async {
    await repo.load();
    await repo.flush();
    await upload();
    github.failure = GitHubFailure.offline;
    await repo.syncNow();
    expect(repo.status.phase, SyncPhase.offline);
    expect(repo.status.pendingCount, 2);
    expect(github.text('library.json'), isNot(contains('cover_from')));

    github.failure = null;
    github.requests.clear();
    await repo.syncNow();
    expect(writes(), ['PUT covers/$path', 'PUT library.json']);
  });

  test('a save of the file that fails leaves the library unsaved', () async {
    await repo.load();
    await repo.flush();
    await upload();
    github.failNextPut = GitHubFailure.other;
    await repo.syncNow();
    expect(repo.status.phase, SyncPhase.failed);
    // The library never names a cover that is not there.
    expect(github.text('library.json'), isNot(contains('cover_from')));
    expect(github.bytes('covers/$path'), isNull);
    await repo.syncNow();
    expect(github.bytes('covers/$path'), isNotNull);
    expect(github.text('library.json'), contains('cover_from'));
  });

  test(
    'a deleted cover is removed after the library stops naming it',
    () async {
      github.setBytes('covers/$path', bytes('picture'));
      github.setFile(
        'library.json',
        encodeLibrary(
          sampleLibrary().copyWith(
            entries: [
              mummy.copyWith(coverFrom: 'repo:$path'),
              dirt,
            ],
          ),
        ),
      );
      await repo.load();
      await repo.flush();
      github.requests.clear();

      await repo.apply(SetCover(mummy.id));
      await covers.delete(path, summary: 'Delete a cover of The Mummy');
      await repo.syncNow();
      expect(writes(), ['PUT library.json', 'DELETE covers/$path']);
      expect(github.bytes('covers/$path'), isNull);
      expect(repo.status.pendingCount, 0);
    },
  );

  test(
    "a cover deleted on its own goes out without a library change",
    () async {
      github.setBytes('covers/movies/old-poster.png', bytes('old'));
      await repo.load();
      await repo.flush();
      github.requests.clear();
      await covers.delete(
        'movies/old-poster.png',
        summary: 'Delete the cover movies/old-poster.png',
      );
      expect(repo.status.pendingCount, 1);
      await repo.syncNow();
      expect(writes(), ['DELETE covers/movies/old-poster.png']);
      expect(repo.status.pendingCount, 0);
    },
  );

  test(
    "keeping GitHub's copy in a conflict drops the queued cover changes",
    () async {
      github.setBytes('covers/movies/old-poster.png', bytes('old'));
      await repo.load();
      await repo.flush();
      await repo.apply(SetRating(mummy.id, 3));
      await covers.delete('movies/old-poster.png', summary: 'Delete');
      github.setFile(
        'library.json',
        encodeLibrary(
          sampleLibrary().copyWith(entries: [mummy.copyWith(rating: 5), dirt]),
        ),
      );
      await repo.syncNow();
      expect(repo.status.phase, SyncPhase.conflict);
      expect(github.bytes('covers/movies/old-poster.png'), isNotNull);

      await repo.resolveConflict(keepMine: false);
      expect(covers.pendingCount, 0);
      expect(covers.files.single.path, 'movies/old-poster.png');
      expect(github.bytes('covers/movies/old-poster.png'), isNotNull);
    },
  );

  test(
    'a disconnect forgets the covers, and keeps the copies with the library',
    () async {
      github.setBytes('covers/movies/old-poster.png', bytes('old'));
      await repo.load();
      await repo.flush();
      final (file, _) = (await covers.fetch('movies/old-poster.png'))!;
      await repo.discard(keepLibrary: true);
      expect(file.existsSync(), isTrue);
      expect(covers.files, isEmpty);
    },
  );
}
