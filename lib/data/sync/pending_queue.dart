import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../operations/library_operation.dart';
import '../operations/operation_json.dart';
import '../operations/settings_operations.dart';
import '../storage/atomic_file.dart';

/// An operation waiting to be saved to GitHub, with the id that names it
/// in `pending.json` and its summary, taken when it was applied so the
/// commit message names what the user saw. The operation is a
/// [LibraryOperation] (`library.json`) or a [SettingsOperation]
/// (`settings.json`); each file is saved from its own.
@immutable
class PendingOperation {
  const PendingOperation(this.id, this.operation, this.summary)
    : assert(
        operation is LibraryOperation || operation is SettingsOperation,
        'a pending operation changes the library or the settings',
      );

  final int id;
  final Object operation;
  final String summary;

  /// The operation when it changes the library, else null.
  LibraryOperation? get library => switch (operation) {
    final LibraryOperation op => op,
    _ => null,
  };

  /// The operation when it changes the settings, else null.
  SettingsOperation? get settings => switch (operation) {
    final SettingsOperation op => op,
    _ => null,
  };
}

/// A save that was started: which operations it carries, the blob sha of
/// the content sent and the commit message, so that after a crash or a
/// lost response the app can tell whether it landed instead of saving the
/// same change twice.
@immutable
class InFlight {
  const InFlight({
    required this.ids,
    required this.blobSha,
    required this.message,
    required this.startedAt,
    this.path,
  });

  final List<int> ids;
  final String blobSha;
  final String message;
  final DateTime startedAt;

  /// The file the save was of: null (a record from before `settings.json`)
  /// means the library file.
  final String? path;

  Map<String, Object?> toJson() => {
    'ids': ids,
    'blobSha': blobSha,
    'message': message,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (path != null) 'path': path,
  };

  static InFlight fromJson(Map<String, Object?> json) => InFlight(
    ids: (json['ids'] as List<Object?>)
        .cast<num>()
        .map((n) => n.toInt())
        .toList(),
    blobSha: json['blobSha'] as String,
    message: json['message'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    path: json['path'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is InFlight &&
      listEquals(other.ids, ids) &&
      other.blobSha == blobSha &&
      other.message == message &&
      other.startedAt == startedAt &&
      other.path == path;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(ids), blobSha, message, startedAt, path);
}

/// The operations not yet saved to GitHub, kept in `pending.json` so that
/// edits made offline survive a restart. An operation is added before the
/// cache applies it and removed only after the save that carries it
/// succeeds. Every change is written atomically, one write after another.
class PendingQueue {
  PendingQueue(this.file);

  final File file;
  static const _version = 1;
  static const _encoder = JsonEncoder.withIndent('  ');

  final List<PendingOperation> _operations = [];
  InFlight? _inFlight;
  int _next = 1;
  bool _loaded = false;
  Future<void> _writing = Future.value();

  List<PendingOperation> get operations => List.unmodifiable(_operations);

  /// The queued changes to the library, in order.
  List<PendingOperation> get libraryOperations =>
      List.unmodifiable(_operations.where((o) => o.library != null));

  /// The queued changes to the settings, in order.
  List<PendingOperation> get settingsOperations =>
      List.unmodifiable(_operations.where((o) => o.settings != null));

  InFlight? get inFlight => _inFlight;
  int get length => _operations.length;
  bool get isEmpty => _operations.isEmpty;
  bool get isNotEmpty => _operations.isNotEmpty;

  /// Reads the file. A missing file is an empty queue; a file that cannot
  /// be read is renamed aside with an `.unreadable` suffix, never
  /// overwritten, and the queue starts empty.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (!await file.exists()) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final operations = (json['operations'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(
            (o) => PendingOperation(
              (o['id'] as num).toInt(),
              decodeOperation(
                Map.of(o)
                  ..remove('id')
                  ..remove('summary'),
              ),
              o['summary'] as String? ?? '',
            ),
          )
          .toList();
      final inFlight = json['inFlight'];
      _operations.addAll(operations);
      _inFlight = inFlight is Map<String, Object?>
          ? InFlight.fromJson(inFlight)
          : null;
      _next = (json['next'] as num?)?.toInt() ?? _nextAfter(operations);
    } on Object {
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      await file.rename('${file.path}.$stamp.unreadable');
    }
  }

  static int _nextAfter(List<PendingOperation> operations) =>
      operations.fold(0, (max, o) => o.id > max ? o.id : max) + 1;

  Future<PendingOperation> add(Object operation, String summary) {
    final pending = PendingOperation(_next++, operation, summary);
    _operations.add(pending);
    return _save().then((_) => pending);
  }

  Future<void> markInFlight(InFlight inFlight) {
    _inFlight = inFlight;
    return _save();
  }

  Future<void> clearInFlight() {
    _inFlight = null;
    return _save();
  }

  /// Drops the operations with these ids. The in-flight record goes once
  /// none of the operations it carried are queued any more.
  Future<void> remove(Iterable<int> ids) {
    final gone = ids.toSet();
    _operations.removeWhere((o) => gone.contains(o.id));
    final queued = _operations.map((o) => o.id).toSet();
    if (_inFlight != null && !_inFlight!.ids.any(queued.contains)) {
      _inFlight = null;
    }
    return _save();
  }

  /// Forgets everything and removes the file (Disconnect).
  Future<void> delete() {
    _operations.clear();
    _inFlight = null;
    _next = 1;
    final deletion = _writing.then((_) async {
      if (await file.exists()) await file.delete();
    });
    _writing = deletion.catchError((Object _) {});
    return deletion;
  }

  Map<String, Object?> toJson() => {
    'version': _version,
    'next': _next,
    'inFlight': _inFlight?.toJson(),
    'operations': [
      for (final o in _operations)
        {'id': o.id, 'summary': o.summary, ...encodeOperation(o.operation)},
    ],
  };

  Future<void> _save() {
    final write = _writing.then((_) async {
      final text = '${_encoder.convert(toJson())}\n';
      await writeAtomically(file, text);
    });
    _writing = write.catchError((Object _) {});
    return write;
  }

  /// Waits for every pending write.
  Future<void> flush() => _writing;
}
