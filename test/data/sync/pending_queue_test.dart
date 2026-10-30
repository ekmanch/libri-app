import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/sync/pending_queue.dart';

import '../../helpers/sample_library.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('libri-pending-');
    file = File('${dir.path}/pending.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'settings operations queue beside the library\'s and are told apart',
    () async {
      final queue = PendingQueue(file);
      await queue.load();
      await queue.add(
        SetStatus(mummy.id, EntryStatus.want),
        'Mark The Mummy as want',
      );
      await queue.add(
        const SetFollow(
          FollowKind.authors,
          'j-k-rowling',
          name: 'J. K. Rowling',
          on: false,
          defaultOn: true,
        ),
        'Unfollow J. K. Rowling',
      );
      await queue.markInFlight(
        InFlight(
          ids: [2],
          blobSha: 'abc',
          message: 'Unfollow J. K. Rowling',
          startedAt: DateTime.utc(2026, 10, 30, 8),
          path: 'settings.json',
        ),
      );

      final again = PendingQueue(file);
      await again.load();
      expect(again.libraryOperations.map((o) => o.id), [1]);
      expect(again.settingsOperations.map((o) => o.id), [2]);
      expect(again.settingsOperations.single.settings, isA<SetFollow>());
      expect(again.settingsOperations.single.library, isNull);
      expect(again.libraryOperations.single.settings, isNull);
      expect(again.inFlight?.path, 'settings.json');
      // A record from before settings.json names no file.
      expect(
        InFlight.fromJson({
          'ids': [1],
          'blobSha': 'x',
          'message': 'm',
          'startedAt': '2026-10-30T08:00:00.000Z',
        }).path,
        isNull,
      );
    },
  );

  test('starts empty without a file', () async {
    final queue = PendingQueue(file);
    await queue.load();
    expect(queue.isEmpty, isTrue);
    expect(queue.inFlight, isNull);
    expect(file.existsSync(), isFalse);
  });

  test('added operations get rising ids and survive a restart', () async {
    final queue = PendingQueue(file);
    await queue.load();
    final a = await queue.add(
      SetStatus(mummy.id, EntryStatus.want),
      'Mark The Mummy as want',
    );
    final b = await queue.add(const SetRating('x', 3), 'Rate x 3 of 10');
    expect([a.id, b.id], [1, 2]);

    final again = PendingQueue(file);
    await again.load();
    expect(again.operations.map((o) => o.id), [1, 2]);
    expect(again.operations.first.operation, isA<SetStatus>());
    expect(again.operations.first.summary, 'Mark The Mummy as want');
    expect(again.operations.last.operation, isA<SetRating>());
    // Ids never repeat, even after the earlier ones are gone.
    await again.remove([1, 2]);
    final c = await again.add(const DeleteEntry('y'), 'Delete y');
    expect(c.id, 3);
    expect(again.length, 1);
  });

  test('the in-flight record is kept and cleared with its ids', () async {
    final queue = PendingQueue(file);
    await queue.load();
    await queue.add(const SetRating('x', 3), 'Rate x 3 of 10');
    await queue.add(const SetRating('x', 4), 'Rate x 4 of 10');
    final inFlight = InFlight(
      ids: const [1, 2],
      blobSha: 's' * 40,
      message: 'Rate x 4 of 10',
      startedAt: DateTime.utc(2026, 10, 13, 20),
    );
    await queue.markInFlight(inFlight);

    final again = PendingQueue(file);
    await again.load();
    expect(again.inFlight, inFlight);
    await again.remove([1]);
    expect(again.inFlight, inFlight, reason: 'one of its ids is still queued');
    await again.remove([2]);
    expect(again.inFlight, isNull);
    expect(again.isEmpty, isTrue);
  });

  test('quick changes are all written, with no .tmp file left', () async {
    final queue = PendingQueue(file);
    await queue.load();
    await Future.wait([
      queue.add(const SetRating('x', 1), 'Rate x 1 of 10'),
      queue.add(const SetRating('x', 2), 'Rate x 2 of 10'),
      queue.add(const SetRating('x', 3), 'Rate x 3 of 10'),
    ]);
    await queue.flush();
    expect(dir.listSync().map((f) => f.path.split('/').last), ['pending.json']);
    final again = PendingQueue(file);
    await again.load();
    expect(again.length, 3);
  });

  test(
    'an unreadable file is renamed aside and the queue starts empty',
    () async {
      file.writeAsStringSync('{"operations": [{"id": 1, "op": "teleport"}]}');
      final queue = PendingQueue(file);
      await queue.load();
      expect(queue.isEmpty, isTrue);
      expect(file.existsSync(), isFalse);
      expect(
        dir.listSync().map((f) => f.path),
        contains(endsWith('.unreadable')),
      );
    },
  );

  test('delete removes the file and forgets everything', () async {
    final queue = PendingQueue(file);
    await queue.load();
    await queue.add(const SetRating('x', 1), 'Rate x 1 of 10');
    await queue.delete();
    expect(file.existsSync(), isFalse);
    expect(queue.isEmpty, isTrue);
  });
}
