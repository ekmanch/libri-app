import '../sync/sync_status.dart';

/// The sync side of a repository that keeps the library on GitHub. The UI
/// reaches it for the banners (Library › Sync and errors), Settings › Library
/// connection and the refresh triggers; a repository without sync (the fixture)
/// simply does not implement it.
abstract interface class LibrarySync {
  SyncStatus get status;

  /// Every change of [status].
  Stream<SyncStatus> get statusChanges;

  /// Asks GitHub whether the file changed and, if it did, shows the new
  /// library with the pending changes applied on top. Pending changes are
  /// sent too. Never throws: failures show in [status].
  Future<void> checkForChanges();

  /// [checkForChanges] without waiting for the debounce: "Sync now" in
  /// Settings › Library connection and Retry on a banner.
  Future<void> syncNow();

  /// The file changed on both sides ([SyncPhase.conflict]): keep this
  /// phone's copy, which overwrites GitHub's, or take GitHub's, which
  /// drops the changes made here.
  Future<void> resolveConflict({required bool keepMine});

  /// Disconnect: stops syncing and removes the queue from the device. The
  /// cached library and the sync meta go too, unless [keepLibrary], which
  /// leaves `library.json` and its base (`sync.json`) in place for use without
  /// a sync (Settings › Disconnect: keep or delete), and for the comparison
  /// when the same file is connected again.
  Future<void> discard({bool keepLibrary = false});
}
