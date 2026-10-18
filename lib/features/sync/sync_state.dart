import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/token_store.dart';
import '../../data/library_providers.dart';
import '../../data/repository/library_sync.dart';
import '../../data/storage/connection_store.dart';
import '../../data/sync/sync_status.dart';
import '../../dev/demo_states.dart';

/// The banner at the top of the Library and Plans screens (A12).
enum SyncBanner {
  saving,
  offline,
  couldNotSave,
  tokenProblem,
  conflict,
  notFound;

  String get title => switch (this) {
    saving => 'Saving your change',
    offline => 'You are offline',
    couldNotSave => 'Could not save to GitHub',
    tokenProblem => 'GitHub refused the token',
    conflict => 'Changed here and on GitHub',
    notFound => 'Library not found on GitHub',
  };

  /// The second line. For [notFound] the card says what is gone instead,
  /// when the sync state knows ([missingDetail]).
  String get body => switch (this) {
    saving => 'Sending it to GitHub.',
    offline =>
      'Showing the library as it was last loaded. '
          'Changes are saved when you are back online.',
    couldNotSave => 'Your change is kept on this phone.',
    tokenProblem => 'It may have expired.',
    conflict => 'Pick which copy to keep.',
    notFound => 'Nothing syncs until you reconnect.',
  };

  /// The button on the right; null for a banner without one.
  String? get actionLabel => switch (this) {
    couldNotSave => 'Retry',
    tokenProblem || notFound => 'Fix',
    conflict => 'Choose',
    _ => null,
  };

  bool get isError =>
      this == couldNotSave ||
      this == tokenProblem ||
      this == conflict ||
      this == notFound;

  /// The value of the SYNC_BANNER dart-define, or null.
  static SyncBanner? fromDemo(String name) => switch (name) {
    'saving' => saving,
    'offline' => offline,
    'failed' => couldNotSave,
    'token' => tokenProblem,
    'conflict' => conflict,
    'missing' => notFound,
    _ => null,
  };

  /// The banner for a sync state: none while idle or checking.
  static SyncBanner? forStatus(SyncStatus status) => switch (status.phase) {
    SyncPhase.saving => saving,
    SyncPhase.offline => offline,
    SyncPhase.failed => couldNotSave,
    SyncPhase.tokenProblem => tokenProblem,
    SyncPhase.conflict => conflict,
    SyncPhase.notFound => notFound,
    SyncPhase.idle || SyncPhase.checking => null,
  };
}

/// What a 404 means for this connection, as the banner (A12) and D6 say
/// it: "library.json is gone from owner/repo on main."
String missingDetail(MissingPart missing, LibraryConnection connection) =>
    switch (missing) {
      MissingPart.repository =>
        '${connection.repository} is gone, or the token no longer sees it.',
      MissingPart.branch =>
        'The branch ${connection.branch} is gone from '
            '${connection.repository}.',
      MissingPart.file =>
        '${connection.file} is gone from ${connection.repository} on '
            '${connection.branch}.',
    };

/// A banner set by hand (tests, the screenshots) that wins over the real
/// state until [SyncBannerNotifier.follow]. [_noOverride] means none.
final _bannerOverrideProvider = NotifierProvider<_BannerOverride, Object?>(
  _BannerOverride.new,
);

const _noOverride = Object();

class _BannerOverride extends Notifier<Object?> {
  @override
  Object? build() => _noOverride;

  void set(Object? value) => state = value;
}

/// The banner to show: one forced by hand, else the SYNC_BANNER
/// dart-define, else the one for the real sync state.
class SyncBannerNotifier extends Notifier<SyncBanner?> {
  @override
  SyncBanner? build() {
    final override = ref.watch(_bannerOverrideProvider);
    if (override != _noOverride) return override as SyncBanner?;
    final demo = SyncBanner.fromDemo(syncBannerDemo);
    if (demo != null) return demo;
    final status = ref.watch(syncStatusProvider).value;
    return status == null ? null : SyncBanner.forStatus(status);
  }

  /// Forces a banner, until [follow].
  void show(SyncBanner banner) =>
      ref.read(_bannerOverrideProvider.notifier).set(banner);

  /// Forces no banner, until [follow].
  void clear() => ref.read(_bannerOverrideProvider.notifier).set(null);

  /// Back to the real sync state.
  void follow() => ref.read(_bannerOverrideProvider.notifier).set(_noOverride);
}

final syncBannerProvider = NotifierProvider<SyncBannerNotifier, SyncBanner?>(
  SyncBannerNotifier.new,
);

/// Where the library file is: a repo, a path and a branch.
@immutable
class ConnectionTarget {
  const ConnectionTarget({
    required this.repository,
    required this.file,
    required this.branch,
  });

  /// "owner/repo".
  final String repository;

  /// Path of the data file inside the repo.
  final String file;
  final String branch;

  @override
  bool operator ==(Object other) =>
      other is ConnectionTarget &&
      other.repository == repository &&
      other.file == file &&
      other.branch == branch;

  @override
  int get hashCode => Object.hash(repository, file, branch);
}

/// What the app knows about its library file on GitHub (D6), kept in
/// `connection.json`. The token is in the secure storage, not here.
@immutable
class LibraryConnection {
  const LibraryConnection({
    required this.connected,
    this.keptLocally = false,
    this.repository = 'ekmanch/library',
    this.file = 'library.json',
    this.branch = 'main',
  }) : assert(!(connected && keptLocally));

  /// The first run, with the last repo and file as hints for F3.
  static const disconnected = LibraryConnection(connected: false);

  final bool connected;

  /// Disconnected, but the library stayed on the phone (D16, "Keep it on
  /// this phone"): the app shows and edits `library.json` without a sync
  /// until a repo is connected again.
  final bool keptLocally;

  /// Whether the app opens on the library rather than the first run.
  bool get showsLibrary => connected || keptLocally;

  /// "owner/repo".
  final String repository;

  /// Path of the data file inside the repo.
  final String file;
  final String branch;

  /// Where to sync, or null until connected.
  ConnectionTarget? get target => connected
      ? ConnectionTarget(repository: repository, file: file, branch: branch)
      : null;

  LibraryConnection copyWith({
    bool? connected,
    bool? keptLocally,
    String? repository,
    String? file,
    String? branch,
  }) => LibraryConnection(
    connected: connected ?? this.connected,
    keptLocally: keptLocally ?? this.keptLocally,
    repository: repository ?? this.repository,
    file: file ?? this.file,
    branch: branch ?? this.branch,
  );

  Map<String, Object?> toJson() => {
    'repository': repository,
    'file': file,
    'branch': branch,
    if (keptLocally) 'local': true,
  };

  /// A stored connection counts as connected, unless it was kept locally
  /// (D16); the token is checked apart.
  static LibraryConnection fromJson(Map<String, Object?> json) {
    final local = json['local'] == true;
    return LibraryConnection(
      connected: !local,
      keptLocally: local,
      repository: json['repository'] as String? ?? 'ekmanch/library',
      file: json['file'] as String? ?? 'library.json',
      branch: json['branch'] as String? ?? 'main',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryConnection &&
      other.connected == connected &&
      other.keptLocally == keptLocally &&
      other.repository == repository &&
      other.file == file &&
      other.branch == branch;

  @override
  int get hashCode =>
      Object.hash(connected, keptLocally, repository, file, branch);
}

/// True once the library was deleted from the phone in this run of the
/// app (D16): the first run then starts at the welcome screen (F2), not
/// the splash.
class StartOverNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set() => state = true;
}

final startOverProvider = NotifierProvider<StartOverNotifier, bool>(
  StartOverNotifier.new,
);

/// Where the token is kept. Memory outside the running app; `main`
/// overrides it with the secure storage.
final tokenStoreProvider = Provider<TokenStore>((ref) => MemoryTokenStore());

/// Where the connection is kept. Memory outside the running app; `main`
/// overrides it with `connection.json`.
final connectionStoreProvider = Provider<ConnectionStore>(
  (ref) => MemoryConnectionStore(),
);

/// The connection as read at startup. Outside the running app the default
/// counts as connected, so a test or a capture lands on the library.
final initialConnectionProvider = Provider<LibraryConnection>(
  (ref) => const LibraryConnection(connected: true),
);

/// The token as read at startup; null when there is none or the secure
/// storage could not be read, which means the first run.
final initialTokenProvider = Provider<String?>((ref) => null);

class TokenNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(initialTokenProvider);

  Future<void> set(String token) async {
    await ref.read(tokenStoreProvider).write(token);
    state = token;
  }

  Future<void> clear() async {
    await ref.read(tokenStoreProvider).delete();
    state = null;
  }
}

/// The GitHub token in use, or null when disconnected.
final tokenProvider = NotifierProvider<TokenNotifier, String?>(
  TokenNotifier.new,
);

class LibraryConnectionNotifier extends Notifier<LibraryConnection> {
  @override
  LibraryConnection build() => firstRunDemo
      ? LibraryConnection.disconnected
      : ref.watch(initialConnectionProvider);

  /// The end of the first run (F8) or a replaced token (D6): keeps the
  /// token and the connection on the device, then the app opens the
  /// library.
  Future<void> connect({
    required String repository,
    required String file,
    required String branch,
    required String token,
  }) async {
    final connection = LibraryConnection(
      connected: true,
      repository: repository,
      file: file,
      branch: branch,
    );
    await ref.read(tokenProvider.notifier).set(token);
    await ref.read(connectionStoreProvider).save(connection.toJson());
    state = connection;
  }

  /// A new token for the same connection (D6).
  Future<void> replaceToken(String token) =>
      ref.read(tokenProvider.notifier).set(token);

  /// Disconnect (D15, D16). The [sync] stops, the queue, the sync meta and
  /// the token leave the device, and GitHub is never touched. With
  /// [keepLibrary] the cached `library.json` stays and the app keeps
  /// showing it without a sync; otherwise the file goes too and the app
  /// starts over at the welcome screen (F2).
  ///
  /// The caller passes the sync: the sync provider depends on this one,
  /// so reading it from here is a circular dependency.
  Future<void> disconnect({
    required bool keepLibrary,
    LibrarySync? sync,
  }) async {
    if (keepLibrary) {
      // The sync finishes its writes before the local repository takes
      // the file over.
      await sync?.discard(keepLibrary: true);
      state = state.copyWith(connected: false, keptLocally: true);
    } else {
      final discarding = sync?.discard();
      ref.read(startOverProvider.notifier).set();
      state = state.copyWith(connected: false, keptLocally: false);
      await discarding;
    }
    await ref.read(tokenProvider.notifier).clear();
    final store = ref.read(connectionStoreProvider);
    if (keepLibrary) {
      await store.save(state.toJson());
    } else {
      await store.clear();
    }
  }
}

final libraryConnectionProvider =
    NotifierProvider<LibraryConnectionNotifier, LibraryConnection>(
      LibraryConnectionNotifier.new,
    );
