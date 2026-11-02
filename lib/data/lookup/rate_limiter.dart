import 'dart:async';
import 'dart:collection';

/// Keeps at least [minGap] between the starts of the actions run through
/// it, in order, with [run]'s urgent actions (what a screen is waiting for)
/// ahead of the rest (the daily checks). AniList allows about 30 requests a
/// minute, IGDB 4 a second; a scroll through a photo view must not burst
/// past that.
class RateLimiter {
  RateLimiter(this.minGap, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration minGap;
  final DateTime Function() _now;

  final _urgent = Queue<Completer<void>>();
  final _waiting = Queue<Completer<void>>();
  bool _pumping = false;
  DateTime? _nextAllowed;

  /// Holds every request back for [duration] from now, whatever the gap:
  /// a provider that answered 429 asked for a pause, and the rest of its
  /// queue waits with the request that got it.
  void holdFor(Duration duration) {
    final until = _now().add(duration);
    final next = _nextAllowed;
    if (next == null || until.isAfter(next)) _nextAllowed = until;
  }

  /// Runs [action] once the gap since the last start has passed and every
  /// action queued before it has started; an [urgent] one only waits for
  /// the urgent ones before it.
  Future<T> run<T>(Future<T> Function() action, {bool urgent = false}) {
    final turn = Completer<void>();
    (urgent ? _urgent : _waiting).add(turn);
    _pump();
    return turn.future.then((_) => action());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_urgent.isNotEmpty || _waiting.isNotEmpty) {
        // Waits first, then picks: an urgent action queued during the wait
        // goes next.
        while (true) {
          final next = _nextAllowed;
          final wait = next == null ? Duration.zero : next.difference(_now());
          if (wait <= Duration.zero) break;
          await Future<void>.delayed(wait);
        }
        final turn = _urgent.isNotEmpty
            ? _urgent.removeFirst()
            : _waiting.removeFirst();
        _nextAllowed = _now().add(minGap);
        turn.complete();
      }
    } finally {
      _pumping = false;
    }
  }
}
