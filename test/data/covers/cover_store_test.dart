import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/covers/artist_photos.dart';
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

  CoverStore store({
    bool remote = true,
    String libraryFile = 'library.json',
    String device = '',
  }) {
    final sep = Platform.pathSeparator;
    final root = device.isEmpty ? dir.path : '${dir.path}$sep$device';
    return CoverStore(
      directory: Directory('$root${sep}covers'),
      remote: remote
          ? GitHubCoverRemote(github, branch: 'main', libraryFile: libraryFile)
          : null,
      listFile: JsonFile(File('$root${sep}covers.json')),
      queueFile: JsonFile(File('$root${sep}cover_changes.json')),
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

  group('artist photos (DESIGN.md 10e)', () {
    const adele = 'covers/artists/adele.jpg';
    const record = 'covers/artists/_missing.json';
    const noMatch =
        '{\n  "version": 1,\n  "backfilled": "2026-11-15",\n  "artists": {\n'
        '    "adele": {"name": "Adele", "tried": "2026-11-15", '
        '"reason": "no-match"}\n  }\n}\n';

    Future<void> put(
      CoverStore covers,
      String picture, {
      bool picked = true,
      String name = 'Adele',
    }) => covers.putArtistPhoto(
      name,
      bytes(picture),
      picked: picked,
      summary: 'Set the photo of $name',
    );

    test('the artists folder is no title\'s: listed apart, by slug, with '
        'the record and its backfilled day', () async {
      github.setBytes('covers/movies/the-mummy-1999.jpg', bytes('a'));
      github.setBytes(adele, bytes('photo'));
      github.setFile(record, noMatch.replaceFirst('"adele"', '"burial"'));
      final covers = store();
      expect(covers.backfilled, isNull);
      await covers.refresh();
      expect(covers.files.map((f) => f.path), ['movies/the-mummy-1999.jpg']);
      expect(covers.artistPhotos.keys, ['adele']);
      expect(covers.artistPhoto('ADELE')!.sha, gitBlobSha(bytes('photo')));
      expect(covers.artistPhoto('!!!'), isNull);
      expect(covers.backfilled, DateTime.utc(2026, 11, 15));
      expect(covers.missing.artists.keys, ['burial']);

      // The record of the last session is read without asking again.
      final again = store();
      await again.load();
      expect(again.backfilled, DateTime.utc(2026, 11, 15));
      expect(again.artistPhotos.keys, ['adele']);
    });

    test('a record in another form is left alone and nothing is fetched '
        'by it', () async {
      github.setFile(record, '{"version": 2, "backfilled": "2026-11-15"}');
      final covers = store();
      await covers.refresh();
      expect(covers.backfilled, isNull);
      expect(covers.missing.artists, isEmpty);
    });

    test(
      'a pick shows at once from the phone\'s copy and is saved under the '
      'fixed name; a second pick before the push replaces the first',
      () async {
        final covers = store();
        await covers.refresh();
        var replaced = 0;
        covers.onCopyReplaced = () => replaced++;
        await put(covers, 'first');
        expect(covers.artistPhoto('Adele')!.sha, gitBlobSha(bytes('first')));
        expect(covers.readyFile('artists/adele.jpg'), isNotNull);
        expect(covers.files, isEmpty);
        expect(replaced, 0);
        await put(covers, 'second');
        expect(replaced, 1);
        expect(covers.pendingCount, 1);
        await covers.pushFiles();
        expect(writes(), ['PUT $adele']);
        expect(github.bytes(adele), bytes('second'));
        expect(covers.pendingCount, 0);
        expect(covers.dropped, isEmpty);
        final commits = await github.commits(adele, branch: 'main');
        expect(commits.first.message, 'Set the photo of Adele');
      },
    );

    test(
      'two devices pick before syncing: the first to push wins, the '
      'other\'s pick is dropped and said, and GitHub\'s file is shown',
      () async {
        final phone = store(device: 'phone');
        final desktop = store(device: 'desktop');
        await phone.refresh();
        await desktop.refresh();
        await put(desktop, 'the desktop\'s');
        await put(phone, 'the phone\'s');
        await desktop.pushFiles();
        github.requests.clear();

        await phone.pushFiles();
        expect(writes(), isEmpty);
        expect(github.bytes(adele), bytes('the desktop\'s'));
        expect(phone.pendingCount, 0);
        expect(phone.dropped.single.name, 'Adele');
        expect(phone.dropped.single.removal, isFalse);
        expect(
          phone.artistPhoto('Adele')!.sha,
          gitBlobSha(bytes('the desktop\'s')),
        );
        // The phone's own copy is gone, so GitHub's is fetched.
        expect(phone.readyFile('artists/adele.jpg'), isNull);
        final (file, _) = (await phone.fetch('artists/adele.jpg'))!;
        expect(file.readAsBytesSync(), bytes('the desktop\'s'));

        // Told once, and kept over a restart until then.
        final restarted = store(device: 'phone');
        await restarted.load();
        expect(restarted.dropped.single.name, 'Adele');
        await restarted.clearDropped();
        expect(restarted.dropped, isEmpty);

        // Picking again, now over a file this phone has seen, goes through.
        await put(phone, 'the phone\'s again');
        expect(phone.dropped, isEmpty);
        await phone.pushFiles();
        expect(github.bytes(adele), bytes('the phone\'s again'));
      },
    );

    test('a fetched photo dropped the same way is not said', () async {
      final phone = store(device: 'phone');
      await phone.refresh();
      github.setBytes(adele, bytes('the desktop\'s'));
      await put(phone, 'fetched', picked: false);
      await phone.pushFiles();
      expect(writes(), isEmpty);
      expect(phone.dropped, isEmpty);
      expect(github.bytes(adele), bytes('the desktop\'s'));
    });

    test('a pick over a photo this phone listed replaces it', () async {
      github.setBytes(adele, bytes('fetched'));
      final covers = store();
      await covers.refresh();
      await put(covers, 'mine');
      await covers.pushFiles();
      expect(github.bytes(adele), bytes('mine'));
      expect(covers.dropped, isEmpty);
    });

    test('a push whose answer was lost is not sent twice', () async {
      final covers = store();
      await covers.refresh();
      await put(covers, 'mine');
      github.setBytes(adele, bytes('mine'));
      await covers.pushFiles();
      expect(writes(), isEmpty);
      expect(covers.pendingCount, 0);
      expect(covers.dropped, isEmpty);
    });

    test('Use automatic removes the file; a refused one is said the same '
        'way', () async {
      github.setBytes(adele, bytes('mine'));
      final covers = store();
      await covers.refresh();
      await covers.removeArtistPhoto(
        'Adele',
        summary: 'Remove the photo of Adele',
      );
      expect(covers.artistPhoto('Adele'), isNull);
      await covers.pushFiles();
      expect(writes(), ['DELETE $adele']);
      expect(github.bytes(adele), isNull);
      expect(covers.dropped, isEmpty);

      // Changed on another device first: it stays.
      github.setBytes(adele, bytes('mine'));
      await covers.refresh();
      await covers.removeArtistPhoto(
        'Adele',
        summary: 'Remove the photo of Adele',
      );
      github.setBytes(adele, bytes('another device\'s'));
      github.requests.clear();
      await covers.pushFiles();
      expect(writes(), isEmpty);
      expect(covers.dropped.single.removal, isTrue);
      expect(covers.dropped.single.name, 'Adele');
      expect(
        covers.artistPhoto('Adele')!.sha,
        gitBlobSha(bytes('another device\'s')),
      );
    });

    test('a pick and then Use automatic before the push sends nothing '
        'when GitHub had no file', () async {
      final covers = store();
      await covers.refresh();
      await put(covers, 'mine');
      await covers.removeArtistPhoto(
        'Adele',
        summary: 'Remove the photo of Adele',
      );
      await covers.pushFiles();
      expect(writes(), isEmpty);
      expect(covers.pendingCount, 0);
    });

    test('the record is merged per artist with GitHub\'s copy: the '
        'desktop\'s cases (missing_merge)', () async {
      final fixture = jsonDecode(
        File('test/fixtures/artist_photos.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final cases = (fixture['missing_merge']! as List)
          .cast<Map<String, Object?>>();
      for (final (i, c) in cases.indexed) {
        final about = '${c['about']}';
        github = FakeGitHubApi();
        final theirs = c['theirs'] as String?;
        if (theirs != null) github.setFile(record, theirs);
        for (final slug in (c['files']! as List).cast<String>()) {
          github.setBytes('covers/artists/$slug.jpg', bytes(slug));
        }
        final covers = store(device: 'case$i');
        await covers.refresh();
        for (final edit in c['edits']! as List) {
          await covers.recordMissing(
            MissingEdit.fromJson(edit)!,
            summary: 'Record artists without a photo',
          );
        }
        github.requests.clear();
        // `library` lists the slugs of the library's artists; a case
        // without it has everyone in the library.
        await covers.pushFiles(
          artists: (c['library'] as List?)?.cast<String>().toSet(),
        );
        // With nothing to record the store never reads the record, so a
        // file in another layout is only rewritten along with an edit.
        final written = (c['edits']! as List).isEmpty
            ? null
            : c['written'] as String?;
        expect(github.text(record), written ?? theirs, reason: about);
        expect(
          writes(),
          written == null ? isEmpty : ['PUT $record'],
          reason: about,
        );
        expect(covers.pendingCount, 0, reason: about);
      }
    });

    test(
      'the record shows with the queued edits on top, before any push',
      () async {
        github.setFile(record, noMatch);
        final covers = store();
        await covers.refresh();
        await covers.recordMissing(
          MissingSet(
            'burial',
            TriedArtist(
              name: 'Burial',
              tried: DateTime.utc(2026, 11, 16),
              reason: MissingReason.noPhoto,
            ),
          ),
          summary: 'Record Burial as having no photo',
        );
        expect(covers.missing.artists.keys, ['adele', 'burial']);
        expect(covers.pendingCount, 1);
        await covers.pushFiles();
        expect(covers.missing.artists.keys, ['adele', 'burial']);
        final commits = await github.commits(record, branch: 'main');
        expect(commits.first.message, 'Record Burial as having no photo');
      },
    );

    test('a photo for an artist on the record takes them off it, with no '
        'edit of its own', () async {
      github.setFile(record, noMatch);
      final covers = store();
      await covers.refresh();
      await put(covers, 'mine');
      // Off the record here at once, since the artist has a file.
      expect(covers.missing.artists, isEmpty);
      await covers.pushFiles();
      expect(writes(), ['PUT $adele', 'PUT $record']);
      expect(github.text(record), contains('"artists": {}'));
      expect(github.text(record), contains('"backfilled": "2026-11-15"'));
    });

    test('with the library on the phone a photo and the record are '
        'written at once', () async {
      final covers = store(remote: false);
      await covers.load();
      await covers.recordMissing(
        MissingSet(
          'adele',
          TriedArtist(
            name: 'Adele',
            tried: DateTime.utc(2026, 11, 15),
            reason: MissingReason.noMatch,
          ),
        ),
        summary: '',
      );
      expect(covers.missing.artists.keys, ['adele']);
      expect(covers.pendingCount, 0);
      await put(covers, 'mine');
      expect(covers.artistPhoto('Adele'), isNotNull);
      expect(covers.missing.artists, isEmpty);
      expect(covers.files, isEmpty);
      final sep = Platform.pathSeparator;
      expect(
        File('${dir.path}${sep}covers${sep}artists${sep}_missing.json')
            .readAsStringSync(),
        '{\n  "version": 1,\n  "artists": {}\n}\n',
      );
    });
  });
}
