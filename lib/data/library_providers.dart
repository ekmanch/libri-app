import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../dev/demo_states.dart';
import '../dev/fake_github_api.dart';
import '../features/sync/sync_state.dart';
import 'github/github_api.dart';
import 'github/github_http_api.dart';
import 'library_codec.dart';
import 'lookup/iso_languages.dart';
import 'models/app_settings.dart';
import 'models/library.dart';
import 'operations/library_operation.dart';
import 'operations/settings_operations.dart';
import 'repository/fixture_library_repository.dart';
import 'repository/github_library_repository.dart';
import 'repository/library_repository.dart';
import 'repository/library_sync.dart';
import 'repository/local_library_repository.dart';
import 'sync/sync_status.dart';

/// The folder for the files Libri keeps on the device. Overridden in
/// `main`; there is no default on purpose, so a missing override fails
/// loudly.
final appDataDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'Override appDataDirectoryProvider in the root ProviderScope.',
  ),
);

/// The folder for the caches (images, track lists, the IGDB token). Also
/// overridden in `main`, with no default.
final appCacheDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError(
    'Override appCacheDirectoryProvider in the root ProviderScope.',
  ),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

typedef GitHubApiFactory = GitHubApi Function({
  required String token,
  required String repository,
});

/// Builds the GitHub client for a token and a repo. The FIRST_RUN dev
/// switch gets one in-memory fake repo per name, so the flow can be
/// walked without a real token and the file it creates is there after.
final gitHubApiFactoryProvider = Provider<GitHubApiFactory>((ref) {
  if (firstRunDemo) {
    final fakes = <String, FakeGitHubApi>{};
    return ({required token, required repository}) => fakes.putIfAbsent(
      repository,
      () => FakeGitHubApi.demoDeferred(
        () => rootBundle.loadString(FixtureLibraryRepository.assetPath),
        latency: FakeGitHubApi.demoLatency,
      ),
    );
  }
  return ({required token, required repository}) => GitHubHttpApi(
    ref.watch(httpClientProvider),
    token: token,
    repository: repository,
    // When the token expires, for Library › Token expires soon. The connection
    // keeps it only for the token in use.
    onTokenExpiration: (expires) => ref
        .read(libraryConnectionProvider.notifier)
        .recordTokenExpiry(token: token, expires: expires),
  );
});

/// The repository for this run of the app: the library on GitHub, built from
/// the connection and the token, and rebuilt when either changes; or the
/// `library.json` kept on the phone after a disconnect (Settings › Disconnect:
/// keep or delete), with no sync. Tests override it with a fixture.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final (target, local) = ref.watch(
    libraryConnectionProvider.select((c) => (c.target, c.keptLocally)),
  );
  if (local) {
    final directory = ref.watch(appDataDirectoryProvider);
    final repository = LocalLibraryRepository(
      File('${directory.path}${Platform.pathSeparator}library.json'),
      // The file is there after a disconnect; should it be gone, start
      // empty rather than fail.
      seed: () async => encodeLibrary(const Library()),
      settingsFile: File(
        '${directory.path}${Platform.pathSeparator}settings.json',
      ),
    );
    ref.onDispose(repository.dispose);
    return repository;
  }
  final token = ref.watch(tokenProvider);
  if (target == null || token == null) return const _Disconnected();
  final api = ref.watch(gitHubApiFactoryProvider)(
    token: token,
    repository: target.repository,
  );
  final repository = GitHubLibraryRepository(
    directory: ref.watch(appDataDirectoryProvider),
    api: api,
    repository: target.repository,
    path: target.file,
    branch: target.branch,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The library as it is now, updated after every applied operation.
/// Disposed when nothing shows it (after a disconnect), so a reconnect
/// starts clean.
final libraryProvider = StreamProvider.autoDispose<Library>(
  (ref) => ref.watch(libraryRepositoryProvider).watch(),
);

/// The settings kept with the library (`settings.json`), updated after every
/// applied settings operation. Screens read `.value ?? AppSettings.defaults`
/// while it loads.
final appSettingsProvider = StreamProvider.autoDispose<AppSettings>(
  (ref) => ref.watch(libraryRepositoryProvider).watchSettings(),
);

/// The phone's system languages, as locale codes in the phone's order
/// ("sv-SE", "en"): what Settings › Books › Languages you read starts from,
/// and the Suggested group of its sheet. The tests override it.
final systemLanguagesProvider = Provider<List<String>>(
  (ref) => [
    for (final locale in PlatformDispatcher.instance.locales)
      locale.toLanguageTag(),
  ],
);

/// The languages the owner reads (DESIGN.md 10c), as ISO 639-1 codes: the
/// list in `settings.json`, or until the first run has written one, the
/// phone's languages plus English ([defaultReadingLanguages]).
final readingLanguagesProvider = Provider.autoDispose<Set<String>>((ref) {
  final settings = ref.watch(appSettingsProvider).value;
  return readingLanguages(settings, ref.watch(systemLanguagesProvider));
});

/// [readingLanguagesProvider] for a [settings] already in hand.
Set<String> readingLanguages(
  AppSettings? settings,
  List<String> systemLanguages,
) => {...settings?.languages ?? defaultReadingLanguages(systemLanguages)};

/// The sync side of the repository, or null when it has none.
final librarySyncProvider = Provider<LibrarySync?>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository is LibrarySync ? repository as LibrarySync : null;
});

/// The sync state for the banners (Library › Sync and errors) and Settings ›
/// Library connection.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final sync = ref.watch(librarySyncProvider);
  if (sync == null) {
    yield SyncStatus.idle;
    return;
  }
  yield sync.status;
  yield* sync.statusChanges;
});

/// Stands in while there is no connection. Nothing watches it then.
class _Disconnected implements LibraryRepository {
  const _Disconnected();

  static final _error = StateError('Not connected to a library');

  @override
  Future<Library> load() => Future.error(_error);

  @override
  Stream<Library> watch() => Stream.error(_error);

  @override
  Future<Library> apply(LibraryOperation operation) => Future.error(_error);

  @override
  Future<AppSettings> loadSettings() => Future.error(_error);

  @override
  Stream<AppSettings> watchSettings() => Stream.error(_error);

  @override
  Future<AppSettings> applySettings(SettingsOperation operation) =>
      Future.error(_error);
}
