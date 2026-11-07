import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/repository/library_sync.dart';

/// When the app asks GitHub for changes on its own (DESIGN.md section 9):
/// when it comes to the foreground, unless a check was made in the last
/// [guard]; every [interval] while it stays there, and nothing at all
/// while it is hidden; and on a tab switch when the last check is older
/// than [interval]. Pull-to-refresh and "Sync now" go to the sync
/// directly, and a save checks on its own first. The checks are
/// conditional requests, so an unchanged file costs a 304 and a few bytes.
class SyncScheduler {
  SyncScheduler({
    required this._sync,
    this.interval = const Duration(seconds: 30),
    this.guard = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Read on every use: the repository, and its sync, can be rebuilt
  /// (a replaced token).
  final LibrarySync? Function() _sync;
  final Duration interval;

  /// How recent a check may be for coming back to the foreground to skip
  /// asking again, so a quick switch away and back does not ask twice.
  final Duration guard;
  final DateTime Function() _now;

  AppLifecycleListener? _lifecycle;
  Timer? _timer;

  /// Starts listening. The first check is the repository's own, on load.
  void start() {
    _lifecycle = AppLifecycleListener(onResume: _onResume, onHide: _onHide);
    _startTimer();
  }

  void dispose() {
    _lifecycle?.dispose();
    _timer?.cancel();
  }

  /// Whether the last answer from GitHub is older than [interval].
  bool get isStale => _olderThan(interval);

  /// Whether the last answer from GitHub is older than [guard].
  bool get isPastGuard => _olderThan(guard);

  bool _olderThan(Duration age) {
    final checked = _sync()?.status.lastChecked;
    return checked == null || _now().difference(checked) >= age;
  }

  /// A tab switch: checks only when the last one is old.
  void onTabSwitch() {
    if (isStale) unawaited(_check());
  }

  void _onResume() {
    if (isPastGuard) unawaited(_check());
    _startTimer();
  }

  void _onHide() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(_check()));
  }

  Future<void> _check() async {
    await _sync()?.checkForChanges();
  }
}
