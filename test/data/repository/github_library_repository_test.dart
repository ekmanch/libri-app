import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/github/github_api.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/repository/github_library_repository.dart';
import 'package:library_app/data/repository/local_library_repository.dart';
import 'package:library_app/data/sync/sync_status.dart';
import 'package:library_app/dev/fake_github_api.dart';

import '../../helpers/sample_library.dart';

void main() {
  late Directory dir;
  late FakeGitHubApi github;
  final seedText = encodeLibrary(sampleLibrary());
  const debounce = Duration(milliseconds: 20);
  final logged = <String>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libri-github-');
    github = FakeGitHubApi(files: {'library.json': seedText});
    logged.clear();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  GitHubLibraryRepository repository({
    String name = 'ekmanch/library',
    String path = 'library.json',
  }) => GitHubLibraryRepository(
    directory: dir,
    api: github,
    repository: name,
    path: path,
    branch: 'main',
    debounce: debounce,
    log: logged.add,
  );

  /// GitHub's file as someone else would leave it: Dirt rated 5.
  final ratedElsewhere = encodeLibrary(
    sampleLibrary().copyWith(entries: [mummy, dirt.copyWith(rating: 5)]),
  );

  /// Lets the debounce fire and every sync finish.
  Future<void> settle(GitHubLibraryRepository repo) async {
    await Future<void>.delayed(debounce * 2);
    await repo.flush();
  }

  String pendingFile() => File('${dir.path}/pending.json').readAsStringSync();

  test('a new install downloads the file and checks once', () async {
    final repo = repository();
    expect(await repo.load(), sampleLibrary());
    await repo.flush();
    expect(File('${dir.path}/library.json').readAsStringSync(), seedText);
    expect(File('${dir.path}/sync.json').existsSync(), isTrue);
    expect(github.requests, [
      'GET library.json',
      startsWith('GET library.json "'), // Conditional: answered 304.
    ]);
    expect(repo.status.phase, SyncPhase.idle);
    expect(repo.status.lastSynced, isNotNull);
    expect(repo.status.pendingCount, 0);
    repo.dispose();
  });

  test('watching alone loads the queue and checks, like the UI', () async {
    final repo = repository();
    final emitted = <Object>[];
    final sub = repo.watch().listen(emitted.add);
    await pumpEventQueue();
    await repo.flush();
    await sub.cancel();
    expect(emitted, [sampleLibrary()]);
    expect(github.requests, hasLength(2));
    expect(repo.status.lastChecked, isNotNull);
    repo.dispose();
  });

  test('a restart shows the cache and only checks', () async {
    final first = repository();
    await first.load();
    await first.flush();
    first.dispose();
    github.requests.clear();

    final second = repository();
    expect(await second.load(), sampleLibrary());
    await second.flush();
    expect(github.requests, [startsWith('GET library.json "')]);
    second.dispose();
  });

  test('edits made within the debounce go out as one commit', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    final statuses = <SyncPhase>[];
    final sub = repo.statusChanges.listen((s) => statuses.add(s.phase));

    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await repo.apply(SetRating(mummy.id, 3));
    await repo.apply(SetPlanStarted(halloweenPlan.id, true));
    expect(repo.status.pendingCount, 3);
    expect(github.putCount, 0, reason: 'nothing goes out before the pause');
    await settle(repo);
    await sub.cancel();

    expect(github.putCount, 1);
    final library = await repo.load();
    expect(github.text('library.json'), encodeLibrary(library));
    expect(
      github.commits('library.json', branch: 'main'),
      completion([
        isA<CommitInfo>().having(
          (c) => c.message,
          'message',
          'Mark The Mummy as want and 2 other changes\n\n'
              '- Mark The Mummy as want\n'
              '- Rate The Mummy 3 of 10\n'
              '- Start Halloween 2026',
        ),
        isA<CommitInfo>(),
      ]),
    );
    expect(repo.status.pendingCount, 0);
    expect(repo.status.phase, SyncPhase.idle);
    expect(statuses, contains(SyncPhase.saving));
    expect(pendingFile(), contains('"operations": []'));
    repo.dispose();
  });

  test('one edit is committed with its summary', () async {
    final repo = repository();
    await repo.load();
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);
    final commits = await github.commits('library.json', branch: 'main');
    expect(commits.first.message, 'Mark The Mummy as want');
    repo.dispose();
  });

  test('a file changed only on GitHub is pulled', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    final emitted = <Object>[];
    final sub = repo.watch().skip(1).listen(emitted.add);
    await pumpEventQueue();

    // Someone rates Dirt on another device.
    github.setFile('library.json', ratedElsewhere);
    await repo.checkForChanges();
    await sub.cancel();

    final pulled = decodeLibrary(ratedElsewhere);
    expect(await repo.load(), pulled);
    expect(emitted.last, pulled);
    expect(github.putCount, 0);
    expect(repo.status.phase, SyncPhase.idle);
    expect(repo.status.lastSynced, isNotNull);
    repo.dispose();
  });

  test('changed on both sides, the sync stops at a conflict', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.setFile('library.json', ratedElsewhere);
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);

    expect(repo.status.phase, SyncPhase.conflict);
    expect(repo.status.pendingCount, 1);
    // Nothing moved: GitHub keeps its file, the phone keeps its edit.
    expect(github.putCount, 0);
    expect(github.text('library.json'), ratedElsewhere);
    final mine = await repo.load();
    expect(mine.entryById(mummy.id)!.status, EntryStatus.want);
    expect(mine.entryById(dirt.id)!.rating, isNot(5));
    expect(logged, contains(contains('waiting for a choice')));

    // Another check changes nothing either.
    await repo.checkForChanges();
    expect(repo.status.phase, SyncPhase.conflict);
    expect(github.putCount, 0);
    repo.dispose();
  });

  test(
    'a save refused for a stale sha is checked, not retried blindly',
    () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      await repo.apply(SetStatus(mummy.id, EntryStatus.want));
      // GitHub refuses the sha, yet the file turns out unchanged (a
      // spurious 409): no conflict, and the queue waits for the next round.
      github.failNextPut = GitHubFailure.conflict;
      await settle(repo);
      expect(github.putCount, 1);
      expect(repo.status.phase, SyncPhase.idle);
      expect(repo.status.pendingCount, 1);
      expect(logged, contains(contains('changed under the save')));

      await repo.syncNow();
      expect(github.putCount, 2);
      expect(repo.status.pendingCount, 0);
      expect(
        decodeLibrary(github.text('library.json')!).entryById(mummy.id)!.status,
        EntryStatus.want,
      );
      repo.dispose();
    },
  );

  test('"Keep mine" writes the phone\'s copy over GitHub\'s', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.setFile('library.json', ratedElsewhere);
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);
    expect(repo.status.phase, SyncPhase.conflict);

    await repo.resolveConflict(keepMine: true);
    expect(repo.status.phase, SyncPhase.idle);
    expect(repo.status.pendingCount, 0);
    expect(github.putCount, 1);
    final saved = decodeLibrary(github.text('library.json')!);
    expect(saved, await repo.load());
    expect(saved.entryById(mummy.id)!.status, EntryStatus.want);
    expect(saved.entryById(dirt.id)!.rating, isNot(5));
    final commits = await github.commits(
      'library.json',
      branch: 'main',
      limit: 1,
    );
    expect(commits.single.message, startsWith("Keep this phone's copy"));
    expect(commits.single.message, contains('Mark The Mummy as want'));
    // Back in step: the next check is quiet.
    await repo.checkForChanges();
    expect(repo.status.phase, SyncPhase.idle);
    expect(github.putCount, 1);
    repo.dispose();
  });

  test('"Keep GitHub\'s" takes its file and drops the queue', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.setFile('library.json', ratedElsewhere);
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);
    expect(repo.status.phase, SyncPhase.conflict);

    await repo.resolveConflict(keepMine: false);
    expect(repo.status.phase, SyncPhase.idle);
    expect(repo.status.pendingCount, 0);
    expect(github.putCount, 0);
    expect(await repo.load(), decodeLibrary(ratedElsewhere));
    expect(pendingFile(), isNot(contains('Mark The Mummy')));
    repo.dispose();
  });

  test('offline edits wait in the queue and go out after a restart', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.failure = GitHubFailure.offline;
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);
    expect(repo.status.phase, SyncPhase.offline);
    expect(repo.status.pendingCount, 1);
    expect(github.putCount, 0);
    expect(pendingFile(), contains('"op": "setStatus"'));
    repo.dispose();

    github.failure = null;
    final again = repository();
    expect(
      (await again.load()).entryById(mummy.id)!.status,
      EntryStatus.want,
      reason: 'the cache has the edit',
    );
    await again.syncNow();
    expect(github.putCount, 1);
    expect(
      decodeLibrary(github.text('library.json')!).entryById(mummy.id)!.status,
      EntryStatus.want,
    );
    expect(again.status.phase, SyncPhase.idle);
    expect(again.status.pendingCount, 0);
    again.dispose();
  });

  test('a refused token is a token problem and keeps the queue', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.failure = GitHubFailure.unauthorized;
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);
    expect(repo.status.phase, SyncPhase.tokenProblem);
    expect(repo.status.pendingCount, 1);
    repo.dispose();
  });

  test('a rate limit is a failure that Retry sends again', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.failure = GitHubFailure.rateLimited;
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await settle(repo);
    expect(repo.status.phase, SyncPhase.failed);
    github.failure = null;
    await repo.syncNow();
    expect(repo.status.phase, SyncPhase.idle);
    expect(github.putCount, 1);
    repo.dispose();
  });

  group('a 404 is "not found", not a failed save', () {
    test('a deleted file; a restored one syncs again', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.deleteFile('library.json');
      await repo.apply(SetStatus(mummy.id, EntryStatus.want));
      await settle(repo);
      expect(repo.status.phase, SyncPhase.notFound);
      expect(repo.status.missing, MissingPart.file);
      expect(repo.status.pendingCount, 1);
      expect(logged, contains('Not found on GitHub: the file.'));

      github.setFile('library.json', seedText);
      await repo.syncNow();
      expect(repo.status.phase, SyncPhase.idle);
      expect(repo.status.pendingCount, 0);
      expect(github.putCount, 1);
      repo.dispose();
    });

    test('a deleted branch', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.deleteBranch('main');
      await repo.apply(SetStatus(mummy.id, EntryStatus.want));
      await settle(repo);
      expect(repo.status.phase, SyncPhase.notFound);
      expect(repo.status.missing, MissingPart.branch);
      expect(repo.status.pendingCount, 1);
      expect(github.putCount, 0);
      repo.dispose();
    });

    test('a repo that is gone, or that the token no longer sees', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.failure = GitHubFailure.notFound;
      await repo.checkForChanges();
      expect(repo.status.phase, SyncPhase.notFound);
      expect(repo.status.missing, MissingPart.repository);
      repo.dispose();
    });

    test('going offline while asking what is gone is offline', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.deleteFile('library.json');
      github.failAfter = 1;
      github.failure = GitHubFailure.offline;
      await repo.checkForChanges();
      expect(repo.status.phase, SyncPhase.offline);
      repo.dispose();
    });
  });

  group('a save whose answer was lost', () {
    test('that landed is not sent twice', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.loseNextPutResponse = GitHubFailure.offline;
      await repo.apply(SetStatus(mummy.id, EntryStatus.want));
      await settle(repo);
      expect(repo.status.phase, SyncPhase.offline);
      expect(pendingFile(), contains('"inFlight": {'));
      repo.dispose();

      final again = repository();
      await again.load();
      await again.syncNow();
      expect(github.putCount, 1);
      expect(again.status.phase, SyncPhase.idle);
      expect(again.status.pendingCount, 0);
      expect(logged, contains(contains('landed')));
      again.dispose();
    });

    test('that did not land is sent again', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.failNextPut = GitHubFailure.offline;
      await repo.apply(SetStatus(mummy.id, EntryStatus.want));
      await settle(repo);
      repo.dispose();

      final again = repository();
      await again.load();
      await again.syncNow();
      expect(github.putCount, 2);
      expect(
        decodeLibrary(github.text('library.json')!).entryById(mummy.id)!.status,
        EntryStatus.want,
      );
      expect(again.status.pendingCount, 0);
      again.dispose();
    });

    test('that landed under a later change is found in the commits', () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      github.loseNextPutResponse = GitHubFailure.offline;
      await repo.apply(SetStatus(mummy.id, EntryStatus.want));
      await settle(repo);
      repo.dispose();
      // Then another device rates Dirt.
      final later = decodeLibrary(github.text('library.json')!);
      github.setFile(
        'library.json',
        encodeLibrary(
          later.copyWith(
            entries: [later.entries.first, dirt.copyWith(rating: 5)],
          ),
        ),
      );

      final again = repository();
      await again.load();
      await again.syncNow();
      expect(github.putCount, 1);
      expect(again.status.pendingCount, 0);
      final library = await again.load();
      expect(library.entryById(mummy.id)!.status, EntryStatus.want);
      expect(library.entryById(dirt.id)!.rating, 5);
      again.dispose();
    });
  });

  test('an operation that changes nothing is not queued', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    await repo.apply(const DeleteEntry('movies/missing'));
    await settle(repo);
    expect(repo.status.pendingCount, 0);
    expect(github.putCount, 0);
    expect(File('${dir.path}/pending.json').existsSync(), isFalse);
    repo.dispose();
  });

  test('an operation that is not allowed throws and is not queued', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    await expectLater(
      () => repo.apply(SetStatus(mummy.id, EntryStatus.inProgress)),
      throwsArgumentError,
    );
    expect(repo.status.pendingCount, 0);
    repo.dispose();
  });

  test('a cache that differs with nothing queued is pushed', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    repo.dispose();
    // Edits made while the library was kept on the phone (D16), with no
    // queue to say what they were.
    final mine = sampleLibrary().copyWith(entries: [mummy]);
    File('${dir.path}/library.json').writeAsStringSync(encodeLibrary(mine));

    final again = repository();
    expect(await again.load(), mine);
    await settle(again);
    expect(github.putCount, 1);
    expect(decodeLibrary(github.text('library.json')!), mine);
    final commits = await github.commits(
      'library.json',
      branch: 'main',
      limit: 1,
    );
    expect(commits.single.message, 'Save the changes made on this phone');
    expect(again.status.phase, SyncPhase.idle);
    again.dispose();
  });

  test('a kept library connected to the same file again is compared', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    await repo.discard(keepLibrary: true);
    repo.dispose();
    // Edited on the phone meanwhile, through the local repository.
    final local = LocalLibraryRepository(
      File('${dir.path}/library.json'),
      seed: () async => seedText,
    );
    await local.apply(SetStatus(mummy.id, EntryStatus.want));
    await local.flush();
    local.dispose();

    // Only the phone changed: pushed.
    final again = repository();
    await again.load();
    await settle(again);
    expect(github.putCount, 1);
    expect(
      decodeLibrary(github.text('library.json')!).entryById(mummy.id)!.status,
      EntryStatus.want,
    );
    again.dispose();
  });

  test('a base written for another file does not count', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    await repo.discard(keepLibrary: true);
    repo.dispose();
    final local = LocalLibraryRepository(
      File('${dir.path}/library.json'),
      seed: () async => seedText,
    );
    await local.apply(SetStatus(mummy.id, EntryStatus.want));
    await local.flush();
    local.dispose();

    // Connected to another repo: no base, so GitHub's copy is taken.
    github.setFile('library.json', ratedElsewhere);
    final other = repository(name: 'ekmanch/other');
    await other.load();
    await settle(other);
    expect(github.putCount, 0);
    expect(await other.load(), decodeLibrary(ratedElsewhere));
    expect(logged, contains(contains('no base')));
    other.dispose();
  });

  test('discard removes the cache, the queue and the meta', () async {
    final repo = repository();
    await repo.load();
    github.failure = GitHubFailure.offline;
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await repo.discard();
    await Future<void>.delayed(debounce * 2);
    expect(dir.listSync(), isEmpty);
    expect(github.putCount, 0);
    repo.dispose();
  });

  test('discard keeping the library leaves it and its base', () async {
    final repo = repository();
    await repo.load();
    await repo.flush();
    github.failure = GitHubFailure.offline;
    await repo.apply(SetStatus(mummy.id, EntryStatus.want));
    await repo.discard(keepLibrary: true);
    await Future<void>.delayed(debounce * 2);
    expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      'library.json',
      'sync.json',
    });
    expect(github.putCount, 0);
    repo.dispose();
  });

  test(
    'the queue survives without a sync meta, costing one download',
    () async {
      final repo = repository();
      await repo.load();
      await repo.flush();
      repo.dispose();
      File('${dir.path}/sync.json').deleteSync();
      github.requests.clear();

      final again = repository();
      await again.load();
      await again.apply(SetStatus(mummy.id, EntryStatus.want));
      await settle(again);
      expect(github.requests.first, 'GET library.json');
      expect(github.putCount, 1);
      expect(again.status.pendingCount, 0);
      again.dispose();
    },
  );

  test(
    'pending.json keeps the queue even when the first load is offline',
    () async {
      github.failure = GitHubFailure.offline;
      final repo = repository();
      await expectLater(repo.load(), throwsA(isA<GitHubException>()));
      expect(repo.status.phase, SyncPhase.offline);
      repo.dispose();
    },
  );
}
