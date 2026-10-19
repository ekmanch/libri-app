import 'package:flutter/foundation.dart';

/// What the sync is doing right now.
enum SyncPhase {
  /// Nothing in progress and the last contact with GitHub went fine.
  idle,

  /// Asking GitHub whether the file changed.
  checking,

  /// A commit is on its way.
  saving,

  /// The last call found no connection; the queue waits.
  offline,

  /// The last save or check failed for another reason (rate limit, a
  /// server error, too many conflicts); Retry sends it again.
  failed,

  /// GitHub refused the token.
  tokenProblem,

  /// The file changed on GitHub and on this phone since they last
  /// matched. Nothing moves until a side is picked
  /// ([LibrarySync.resolveConflict]).
  conflict,

  /// GitHub answered 404: the file, its branch or the whole repo is gone,
  /// or the token no longer sees the repo ([SyncStatus.missing] says
  /// which). Nothing syncs until the connection is fixed; the checks go
  /// on, so a restored file or branch is picked up again.
  notFound,
}

/// What a 404 turned out to be about.
enum MissingPart { repository, branch, file }

/// The sync state the banners (Library › Sync and errors) and Settings ›
/// Library connection show.
@immutable
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSynced,
    this.lastChecked,
    this.pendingCount = 0,
    this.remoteChangedAt,
    this.missing,
  });

  static const idle = SyncStatus();

  final SyncPhase phase;

  /// When the phone's copy last matched GitHub: after a download with
  /// nothing pending, or a successful save.
  final DateTime? lastSynced;

  /// When GitHub last answered a check, for the "every 5 minutes" rule.
  final DateTime? lastChecked;

  /// Operations not yet saved to GitHub.
  final int pendingCount;

  /// The date of GitHub's last commit on the file, looked up when a conflict is
  /// found (Library › Conflict: keep which copy? says "GitHub: last commit …").
  final DateTime? remoteChangedAt;

  /// What is gone, while the phase is [SyncPhase.notFound].
  final MissingPart? missing;

  bool get hasPending => pendingCount > 0;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSynced,
    DateTime? lastChecked,
    int? pendingCount,
    DateTime? remoteChangedAt,
    MissingPart? missing,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSynced: lastSynced ?? this.lastSynced,
    lastChecked: lastChecked ?? this.lastChecked,
    pendingCount: pendingCount ?? this.pendingCount,
    remoteChangedAt: remoteChangedAt ?? this.remoteChangedAt,
    missing: missing ?? this.missing,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSynced == lastSynced &&
      other.lastChecked == lastChecked &&
      other.pendingCount == pendingCount &&
      other.remoteChangedAt == remoteChangedAt &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(
    phase,
    lastSynced,
    lastChecked,
    pendingCount,
    remoteChangedAt,
    missing,
  );

  @override
  String toString() =>
      'SyncStatus(${phase.name}, pending: $pendingCount, '
      'synced: $lastSynced, checked: $lastChecked)';
}
