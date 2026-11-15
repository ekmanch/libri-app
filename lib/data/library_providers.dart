import 'dart:io';

import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart' show rootBundle;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../dev/demo_states.dart';
import '../dev/fake_github_api.dart';
import '../features/sync/sync_state.dart';
import 'covers/artist_photos.dart';
import 'covers/cover_files.dart';
import 'covers/cover_picture.dart';
import 'covers/cover_sources.dart';
import 'covers/cover_store.dart';
import 'github/github_api.dart';
import 'github/github_http_api.dart';
import 'library_codec.dart';
import 'lookup/iso_languages.dart';
import 'models/app_settings.dart';
import 'models/entry.dart';
import 'models/entry_kind.dart';
import 'models/library.dart';
import 'models/media_type.dart';
import 'operations/library_operation.dart';
import 'operations/settings_operations.dart';
import 'repository/fixture_library_repository.dart';
import 'repository/github_library_repository.dart';
import 'repository/library_repository.dart';
import 'repository/library_sync.dart';
import 'repository/local_library_repository.dart';
import 'storage/json_file.dart';
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
      covers: _coverStore(ref),
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
    covers: _coverStore(
      ref,
      remote: GitHubCoverRemote(
        api,
        branch: target.branch,
        libraryFile: target.file,
      ),
    ),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The owner's own covers (DESIGN.md section 10d), which belong to the
/// repository: the files in `covers/` beside the library file on GitHub,
/// or, with the library kept on the phone, the folder itself. A repository
/// without them (the fixture, most tests) has an empty list kept in
/// memory.
final coverStoreProvider = Provider<CoverStore>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  final covers = switch (repository) {
    GitHubLibraryRepository() => repository.covers,
    LocalLibraryRepository() => repository.covers,
    _ => null,
  };
  if (covers != null) return covers;
  final empty = CoverStore();
  ref.onDispose(empty.dispose);
  return empty;
});

/// The store for a library in the phone's data folder: this phone's copies
/// in `covers/` there, the list in `covers.json` under the cache folder and
/// the queue in `cover_changes.json`. [remote] is null for a library kept
/// on the phone.
CoverStore _coverStore(Ref ref, {CoverRemote? remote}) {
  final data = ref.watch(appDataDirectoryProvider).path;
  final cache = ref.watch(appCacheDirectoryProvider).path;
  final separator = Platform.pathSeparator;
  final store = CoverStore(
    directory: Directory('$data$separator$coversFolder'),
    remote: remote,
    listFile: JsonFile(File('$cache${separator}covers.json')),
    queueFile: JsonFile(File('$data${separator}cover_changes.json')),
  );
  // A photo replaced under its fixed name (an artist's) must not be drawn
  // from the decode of the old file.
  store.onCopyReplaced = () => PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  ref.onDispose(store.dispose);
  return store;
}

/// The cover files as they are now ([CoverStore.files]): rebuilt when one
/// is added, removed or listed.
final coverFilesProvider = Provider<List<CoverFile>>((ref) {
  final store = ref.watch(coverStoreProvider);
  void changed() => ref.invalidateSelf();
  store.addListener(changed);
  ref.onDispose(() => store.removeListener(changed));
  // The list of the last session shows before GitHub is asked again.
  store.load().ignore();
  return store.files;
});

/// The artists' photos in the library repo, `covers/artists/<slug>.jpg`,
/// by slug ([CoverStore.artistPhotos]; DESIGN.md section 10e).
final artistPhotoFilesProvider = Provider<Map<String, CoverFile>>((ref) {
  final store = ref.watch(coverStoreProvider);
  void changed() => ref.invalidateSelf();
  store.addListener(changed);
  ref.onDispose(() => store.removeListener(changed));
  store.load().ignore();
  return store.artistPhotos;
});

/// The photo picks a sync dropped for another device's photo, until the
/// owner has been told ([CoverStore.dropped]).
final droppedPhotosProvider = Provider<List<DroppedPhoto>>((ref) {
  final store = ref.watch(coverStoreProvider);
  void changed() => ref.invalidateSelf();
  store.addListener(changed);
  ref.onDispose(() => store.removeListener(changed));
  store.load().ignore();
  return store.dropped;
});

/// Everything saved by each artist, in the order their covers are lent to
/// an artist without a photo (`artistCoverOrder`): the albums most recently
/// added first, then the songs. By the artist's name in lower case, as the
/// artist list groups them, and from the whole library whatever a list is
/// filtered to.
final artistCoverEntriesProvider = Provider<Map<String, List<Entry>>>((ref) {
  final library = ref.watch(libraryProvider).value;
  if (library == null) return const {};
  final saved = <String, List<Entry>>{};
  for (final entry in library.entries) {
    if (entry.type != MediaType.music) continue;
    saved.putIfAbsent(artistCoverKey(entry.creator), () => []).add(entry);
  }
  return {
    for (final MapEntry(:key, value: entries) in saved.entries)
      key: [
        for (final i in artistCoverOrder([
          for (final entry in entries)
            (song: entry.kind == EntryKind.song, added: entry.added),
        ]))
          entries[i],
      ],
  };
});

/// The key of [artistCoverEntriesProvider] for an artist's name.
String artistCoverKey(String? name) {
  final trimmed = (name ?? '').trim().toLowerCase();
  return trimmed.isEmpty ? 'unknown artist' : trimmed;
}

/// Decodes, scales and encodes an uploaded cover. The tests and the walks
/// override it.
final coverPicturesProvider = Provider<CoverPictures>(
  (ref) => const EngineCoverPictures(),
);

/// Where an uploaded cover is picked from. The tests and the walks
/// override it.
final coverSourcesProvider = Provider<CoverSources>(
  (ref) => const PlatformCoverSources(),
);

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
