import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/cover_store.dart';
import 'package:library_app/data/github/git_blob.dart';
import 'package:library_app/data/github/github_api.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/storage/json_file.dart';
import 'package:library_app/dev/fake_github_api.dart';

import '../../helpers/sample_library.dart';

Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  late Directory dir;
  late FakeGitHubApi github;
  late DateTime now;
  final logged = <String>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libri-covers');
    github = FakeGitHubApi();
    now = DateTime(2026, 11, 14, 12);
    logged.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  CoverStore store({bool remote = true, String libraryFile = 'library.json'}) {
    final sep = Platform.pathSeparator;
    return CoverStore(
      directory: Directory('${dir.path}${sep}covers'),
      remote: remote
          ? GitHubCoverRemote(github, branch: 'main', libraryFile: libraryFile)
          : null,
      listFile: JsonFile(File('${dir.path}${sep}covers.json')),
      queueFile: JsonFile(File('${dir.path}${sep}cover_changes.json')),
      now: () => now,
      log: logged.add,
    );
  }

  List<String> writes() => [
    for (final r in github.requests)
      if (r.startsWith('PUT') || r.startsWith('DELETE')) r,
  ];

  test('the list is the files under covers/ beside the library file', () async {
    github.setBytes('data/covers/movies/the-mummy-1999.jpg', bytes('a'));
    github.setBytes('covers/movies/elsewhere.jpg', bytes('b'));
    github.setFile('data/library.json', '{}');
    final covers = store(libraryFile: 'data/library.json');
    expect(covers.isStale, isTrue);
    await covers.refresh();
    expect(covers.files.single.path, 'movies/the-mummy-1999.jpg');
    expect(covers.files.single.sha, gitBlobSha(bytes('a')));
    expect(covers.isStale, isFalse);
    // Trusted for a minute; Pick a cover asks again after it.
    github.requests.clear();
    await covers.refresh(ifStale: true);
    expect(github.requests, isEmpty);
    now = now.add(const Duration(seconds: 61));
    await covers.refresh(ifStale: true);
    expect(github.requests, ['GET tree']);
  });

  test('a failed listing keeps the last list', () async {
    github.setBytes('covers/movies/a.jpg', bytes('a'));
    final covers = store();
    await covers.refresh();
    github.failure = GitHubFailure.offline;
    await covers.refresh();
    expect(covers.files, hasLength(1));
    // And a new session starts from it.
    await covers.flush();
    final next = store();
    await next.load();
    expect(next.files.single.path, 'movies/a.jpg');
  });

  test(
    'a copy is fetched when shown, and again when the blob changes',
    () async {
      github.setBytes('covers/movies/a.jpg', bytes('first'));
      final covers = store();
      await covers.refresh();
      expect(covers.readyFile('movies/a.jpg'), isNull);
      final (file, fresh) = (await covers.fetch('movies/a.jpg'))!;
      expect(fresh, isTrue);
      expect(file.readAsBytesSync(), bytes('first'));
      expect(covers.readyFile('movies/a.jpg')!.path, file.path);
      expect((await covers.fetch('movies/a.jpg'))!.$2, isFalse);
      // Replaced on GitHub under the same name.
      github.setBytes('covers/movies/a.jpg', bytes('second'));
      await covers.refresh();
      expect(covers.readyFile('movies/a.jpg'), isNull);
      await covers.fetch('movies/a.jpg');
      expect(file.readAsBytesSync(), bytes('second'));
      expect(await covers.fetch('movies/nothing.jpg'), isNull);
    },
  );

  test('a failed fetch waits before it is tried again', () async {
    github.setBytes('covers/movies/a.jpg', bytes('a'));
    final covers = store();
    await covers.refresh();
    github.failure = GitHubFailure.offline;
    expect(await covers.fetch('movies/a.jpg'), isNull);
    github.failure = null;
    expect(await covers.fetch('movies/a.jpg'), isNull);
    now = now.add(const Duration(minutes: 2));
    expect(await covers.fetch('movies/a.jpg'), isNotNull);
  });

  test('an upload shows at once and is saved before the library', () async {
    final covers = store();
    await covers.refresh();
    var queued = 0;
    covers.onQueued = () => queued++;
    final data = bytes('picture');
    final sha = gitBlobSha(data);
    await covers.add(
      'movies/the-mummy-1999.abc1234.jpg',
      data,
      sha: sha,
      summary: 'Add a cover for The Mummy',
    );
    expect(queued, 1);
    expect(covers.pendingCount, 1);
    expect(covers.files.single.sha, sha);
    // From the phone's own copy, before it has reached GitHub.
    expect(covers.readyFile('movies/the-mummy-1999.abc1234.jpg'), isNotNull);
    expect(writes(), isEmpty);

    await covers.pushFiles();
    expect(writes(), ['PUT covers/movies/the-mummy-1999.abc1234.jpg']);
    expect(github.bytes('covers/movies/the-mummy-1999.abc1234.jpg'), data);
    expect(covers.pendingCount, 0);
    final commits = await github.commits(
      'covers/movies/the-mummy-1999.abc1234.jpg',
      branch: 'main',
    );
    expect(commits.first.message, 'Add a cover for The Mummy');
  });

  test(
    'the queue survives a restart, and a save sent twice does nothing',
    () async {
      final first = store();
      await first.refresh();
      final data = bytes('picture');
      await first.add(
        'movies/a.abc1234.jpg',
        data,
        sha: gitBlobSha(data),
        summary: 'Add a cover for A',
      );
      await first.flush();

      // The save lands, the answer is lost, the app restarts.
      github.setBytes('covers/movies/a.abc1234.jpg', data);
      final second = store();
      await second.load();
      expect(second.pendingCount, 1);
      github.requests.clear();
      await second.pushFiles();
      expect(writes(), isEmpty);
      expect(second.pendingCount, 0);
    },
  );

  test(
    'a removal waits for the library, and never takes a cover in use',
    () async {
      github.setBytes('covers/movies/the-mummy-1999.jpg', bytes('a'));
      github.setBytes('covers/movies/old-poster.png', bytes('b'));
      final covers = store();
      await covers.refresh();
      await covers.fetch('movies/old-poster.png');
      await covers.delete(
        'movies/old-poster.png',
        summary: 'Delete the cover movies/old-poster.png',
      );
      await covers.delete(
        'movies/the-mummy-1999.jpg',
        summary: 'Delete a cover of The Mummy',
      );
      // Gone from the list and the phone at once.
      expect(covers.files, isEmpty);
      expect(covers.readyFile('movies/old-poster.png'), isNull);
      expect(covers.pendingCount, 2);

      await covers.pushFiles();
      expect(writes(), isEmpty);
      // The library still shows one of them (a conflict went GitHub's way).
      final library = Library(
        entries: [mummy.copyWith(coverFrom: 'repo:movies/the-mummy-1999.jpg')],
      );
      await covers.pushRemovals(library);
      expect(writes(), ['DELETE covers/movies/old-poster.png']);
      expect(covers.pendingCount, 0);
      expect(covers.files.single.path, 'movies/the-mummy-1999.jpg');
      expect(logged.single, contains('still shows it'));
    },
  );

  test('an upload deleted before it left is never sent', () async {
    final covers = store();
    await covers.refresh();
    final data = bytes('picture');
    await covers.add(
      'movies/a.abc1234.jpg',
      data,
      sha: gitBlobSha(data),
      summary: 'Add a cover for A',
    );
    await covers.delete('movies/a.abc1234.jpg', summary: 'Delete a cover of A');
    expect(covers.pendingCount, 0);
    expect(covers.files, isEmpty);
    await covers.pushFiles();
    await covers.pushRemovals(const Library());
    expect(writes(), isEmpty);
  });

  test(
    'a move puts the file at its new place first, then removes the old',
    () async {
      github.setBytes('covers/movies/the-mummy-1999.jpg', bytes('a'));
      final covers = store();
      await covers.refresh();
      await covers.move(
        'movies/the-mummy-1999.jpg',
        'shows/the-mummy-1999.jpg',
        summary: 'Move a cover of The Mummy to shows',
      );
      expect(covers.files.single.path, 'shows/the-mummy-1999.jpg');
      expect(covers.files.single.sha, gitBlobSha(bytes('a')));

      // The phone had no copy: the bytes come from GitHub.
      await covers.pushFiles();
      expect(writes(), ['PUT covers/shows/the-mummy-1999.jpg']);
      expect(github.bytes('covers/movies/the-mummy-1999.jpg'), isNotNull);
      expect(covers.pendingCount, 1);
      await covers.pushRemovals(
        Library(
          entries: [mummy.copyWith(coverFrom: 'repo:shows/the-mummy-1999.jpg')],
        ),
      );
      expect(writes().last, 'DELETE covers/movies/the-mummy-1999.jpg');
      expect(github.bytes('covers/movies/the-mummy-1999.jpg'), isNull);
      expect(github.bytes('covers/shows/the-mummy-1999.jpg'), bytes('a'));
      expect(covers.pendingCount, 0);
      expect(covers.files.single.path, 'shows/the-mummy-1999.jpg');
    },
  );

  test('an upload moved before it left is saved at its new place', () async {
    final covers = store();
    await covers.refresh();
    final data = bytes('picture');
    await covers.add(
      'movies/a.abc1234.jpg',
      data,
      sha: gitBlobSha(data),
      summary: 'Add a cover for A',
    );
    await covers.move(
      'movies/a.abc1234.jpg',
      'shows/a.abc1234.jpg',
      summary: 'Move a cover of A to shows',
    );
    expect(covers.readyFile('shows/a.abc1234.jpg'), isNotNull);
    await covers.pushFiles();
    await covers.pushRemovals(const Library());
    expect(writes(), ['PUT covers/shows/a.abc1234.jpg']);
  });

  test("dropping the queue gives GitHub's list back", () async {
    github.setBytes('covers/movies/a.jpg', bytes('a'));
    final covers = store();
    await covers.refresh();
    await covers.delete('movies/a.jpg', summary: 'Delete');
    expect(covers.files, isEmpty);
    await covers.dropPending();
    expect(covers.files.single.path, 'movies/a.jpg');
    expect(covers.pendingCount, 0);
  });

  test('copies of files gone from GitHub are dropped', () async {
    github.setBytes('covers/movies/a.jpg', bytes('a'));
    final covers = store();
    await covers.refresh();
    final (file, _) = (await covers.fetch('movies/a.jpg'))!;
    github.deleteFile('covers/movies/a.jpg');
    await covers.refresh();
    expect(covers.files, isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('with the library on the phone the folder is the whole list', () async {
    final covers = store(remote: false);
    await covers.load();
    expect(covers.files, isEmpty);
    final data = bytes('picture');
    await covers.add(
      'movies/a.abc1234.jpg',
      data,
      sha: gitBlobSha(data),
      summary: 'Add a cover for A',
    );
    // Nothing is queued: there is nowhere to send it.
    expect(covers.pendingCount, 0);
    expect(covers.files.single.path, 'movies/a.abc1234.jpg');
    await covers.flush();
    final next = store(remote: false);
    await next.load();
    expect(next.files.single.sha, gitBlobSha(data));
    expect(next.readyFile('movies/a.abc1234.jpg'), isNotNull);
    await next.delete('movies/a.abc1234.jpg', summary: 'Delete');
    expect(next.files, isEmpty);
    expect(github.requests, isEmpty);
  });

  test('clearing forgets the list, and the copies when asked', () async {
    github.setBytes('covers/movies/a.jpg', bytes('a'));
    final covers = store();
    await covers.refresh();
    final (file, _) = (await covers.fetch('movies/a.jpg'))!;
    await covers.clear(deleteFiles: false);
    expect(covers.files, isEmpty);
    expect(file.existsSync(), isTrue);
    await covers.clear(deleteFiles: true);
    expect(file.existsSync(), isFalse);
  });
}
