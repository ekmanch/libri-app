import 'package:flutter/foundation.dart';

/// How far a run of the checks has come (Settings › Upcoming releases:
/// "Checking 184 of 423…" with Stop while [running]).
@immutable
class CheckProgress {
  const CheckProgress({this.running = false, this.done = 0, this.total = 0});

  static const idle = CheckProgress();

  final bool running;

  /// Items asked about so far, and the items the run set out to ask about.
  final int done;
  final int total;

  CheckProgress copyWith({bool? running, int? done, int? total}) =>
      CheckProgress(
        running: running ?? this.running,
        done: done ?? this.done,
        total: total ?? this.total,
      );

  @override
  bool operator ==(Object other) =>
      other is CheckProgress &&
      other.running == running &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(running, done, total);

  @override
  String toString() => 'CheckProgress($done of $total, running: $running)';
}

/// What a check reports to while it runs, and how it is told to stop. A
/// check calls [tick] after each item it asked about and looks at
/// [cancelled] before the next; a cancelled check ends without recording
/// its day, so the next open takes it up again.
class CheckControl {
  CheckControl({this.onTick, bool Function()? cancelled})
    : _cancelled = cancelled ?? (() => false);

  /// A control nothing listens to: the default for a check run on its own.
  static final none = CheckControl();

  final void Function()? onTick;
  final bool Function() _cancelled;

  bool get cancelled => _cancelled();

  void tick() => onTick?.call();
}
