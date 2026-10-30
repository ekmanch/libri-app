import 'dart:async';
import 'dart:io';

import '../storage/atomic_file.dart';

/// A value kept in one file on the device in its canonical text form, so it
/// survives a restart: `settings.json` next to the cached `library.json`.
/// The file is written after every change that alters the value.
///
/// On the first start there is no file yet; it is created from [seed]. A
/// file that cannot be read is never overwritten: it is renamed aside with
/// an `.unreadable` suffix and the value starts again from [seed]. The same
/// rules as `LocalLibraryRepository`, for any value.
class LocalCache<T> {
  LocalCache(
    this.file, {
    required this.seed,
    required this.encode,
    required this.decode,
  });

  final File file;

  /// The text for a new install.
  final Future<String> Function() seed;
  final String Function(T value) encode;
  final T Function(String text) decode;

  final _changes = StreamController<T>.broadcast();
  Future<T>? _loading;
  T? _value;
  bool _loaded = false;

  /// The text last written (or read), to skip writes that change nothing.
  String? _written;

  /// Writes run one after another, in the order the changes were applied.
  Future<void> _writing = Future.value();

  Future<T> load() async {
    if (_loaded) return _value as T;
    _loading ??= _read();
    final loaded = await _loading!;
    // An update may have run while the file was loading; keep its result.
    if (!_loaded) {
      _value = loaded;
      _loaded = true;
    }
    return _value as T;
  }

  Future<T> _read() async {
    if (await file.exists()) {
      final text = await file.readAsString();
      try {
        final value = decode(text);
        _written = text;
        return value;
      } on Object {
        await file.rename(_asidePath());
      }
    }
    final value = decode(await seed());
    await _save(value);
    return value;
  }

  String _asidePath() {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${file.path}.$stamp.unreadable';
  }

  /// The current value first, then every change. The changes are listened
  /// to before the load completes, so a change made meanwhile is not lost
  /// between the first value and the subscription.
  Stream<T> watch() {
    final controller = StreamController<T>();
    var started = false;
    final subscription = _changes.stream.listen((value) {
      if (started) controller.add(value);
    });
    controller.onCancel = subscription.cancel;
    if (_loaded) {
      // Buffered until the listener comes: the value as of now, then the
      // changes after it.
      controller.add(_value as T);
      started = true;
      return controller.stream;
    }
    load().then(
      (value) {
        if (controller.isClosed) return;
        // The newest value: a change since the load resolved is in it.
        controller.add(_loaded ? _value as T : value);
        started = true;
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      },
    );
    return controller.stream;
  }

  /// Applies [change] to the current value, shows the result at once and
  /// returns when the file is written. A failed write is rethrown here; the
  /// change stays in memory and is written with the next one.
  Future<T> update(T Function(T current) change) async {
    await load();
    // Read after the await: another change may have landed meanwhile, and
    // this one must build on it.
    final current = _value as T;
    final next = change(current);
    if (next == current) return current;
    _set(next);
    await _save(next);
    return next;
  }

  /// Swaps in a whole value, e.g. a fresh copy from GitHub, shows it at once
  /// and returns when the file is written. Nothing happens when it is the
  /// value already held.
  Future<T> replace(T value) async {
    await load();
    if (value == _value) return value;
    _set(value);
    await _save(value);
    return value;
  }

  void _set(T value) {
    _value = value;
    _loaded = true;
    _changes.add(value);
  }

  /// Removes the file (Disconnect). The in-memory value stays until the
  /// cache is disposed.
  Future<void> delete() {
    final deletion = _writing.then((_) async {
      if (await file.exists()) await file.delete();
      _written = null;
    });
    _writing = deletion.catchError((Object _) {});
    return deletion;
  }

  Future<void> _save(T value) {
    final write = _writing.then((_) async {
      // A later change may already be in memory; write the newest.
      final text = encode(_loaded ? _value as T : value);
      if (text == _written) return;
      await writeAtomically(file, text);
      _written = text;
    });
    // Keep the chain going after a failure; the caller still sees it.
    _writing = write.catchError((Object _) {});
    return write;
  }

  /// The current in-memory value, if loaded.
  T? get current => _loaded ? _value : null;

  /// Waits for every pending write.
  Future<void> flush() => _writing;

  void dispose() => _changes.close();
}
