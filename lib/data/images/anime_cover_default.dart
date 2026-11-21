import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_providers.dart';
import '../lookup/lookup_failure.dart';
import '../lookup/lookup_providers.dart';
import '../lookup/lookup_service.dart';
import '../models/entry.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../operations/entry_operations.dart';
import '../repository/library_repository.dart';

/// Anime covers come from TMDB by default (owner's decision, 2026-11-21,
/// shared with the desktop; DESIGN.md section 10): an anime with a `tmdb`
/// link whose TMDB show has a poster shows that poster, stored on the
/// entry as `"cover_from": "tmdb:tv:<id>"`. The rule is standing: every
/// anime with a link and no `cover_from` is checked, since only a request
/// to TMDB says whether the show has a poster.

/// Whether [entry] is waiting for the check: an anime with a `tmdb` link
/// and no `cover_from` (a picked cover, AniList's own included, and one of
/// the owner's files all have one).
bool wantsTmdbCover(Entry entry) =>
    entry.type == MediaType.anime &&
    entry.tmdb != null &&
    entry.coverFrom == null;

/// The `cover_from` of an anime whose `tmdb` link went from [oldTmdb] to
/// [newTmdb]: one equal to the old link follows the new one, and goes
/// with a link that was cleared (the anime became a movie). Any other
/// cover, AniList's picked one and another match's included, is left as
/// it is.
String? coverFromAfterTmdbChange(
  String? coverFrom, {
  required String? oldTmdb,
  required String? newTmdb,
}) => coverFrom != null && coverFrom == oldTmdb && oldTmdb != newTmdb
    ? newTmdb
    : coverFrom;

/// Does the check: one request to TMDB per waiting anime, then a
/// `SetCover` that only lands while the entry still has no `cover_from`.
class AnimeCoverDefault {
  AnimeCoverDefault({required this.lookups, required this.repository});

  final LookupService lookups;
  final LibraryRepository repository;

  /// The TMDB shows that answered with no poster this session: their
  /// anime keep AniList's cover, and are asked about again next session.
  final _noPoster = <String>{};
  bool _running = false;

  bool get isRunning => _running;

  /// Checks every anime of [library] that [wantsTmdbCover]; returns how
  /// many got TMDB's poster. A lookup that could not be made (offline,
  /// not set up, rate limited) ends the run, and the next one asks again.
  Future<int> run(Library library) async {
    if (_running) return 0;
    _running = true;
    var written = 0;
    try {
      for (final entry in library.entries.where(wantsTmdbCover)) {
        final tmdb = entry.tmdb!;
        if (_noPoster.contains(tmdb)) continue;
        final source = lookups.sourceOf(tmdb);
        if (source == null || !source.isConfigured) return written;
        final String? poster;
        try {
          poster = await source.coverUrl(tmdb, type: MediaType.anime);
        } on LookupException {
          return written;
        }
        if (poster == null) {
          _noPoster.add(tmdb);
          continue;
        }
        await repository.apply(
          SetCover(entry.id, coverFrom: tmdb, ifNone: true),
        );
        written++;
      }
    } finally {
      _running = false;
    }
    return written;
  }
}

final animeCoverDefaultProvider = Provider<AnimeCoverDefault>(
  (ref) => AnimeCoverDefault(
    lookups: ref.watch(lookupServiceProvider),
    repository: ref.watch(libraryRepositoryProvider),
  ),
);

/// Runs the check while the app is open: a little after the library
/// loads and after every change to it. The app shell watches it so it
/// runs. Does nothing unless `main` overrides it with
/// [startAnimeCoverCheck], so no test asks anyone.
final animeCoverCheckProvider = Provider<void>((ref) {});

/// How long after a change the check looks again.
const animeCoverCheckDelay = Duration(seconds: 5);

/// The real check, for the root scope in `main`.
void startAnimeCoverCheck(Ref ref) {
  Timer? timer;
  var disposed = false;
  ref.listen(libraryProvider, (_, next) {
    final library = next.value;
    if (library == null || !library.entries.any(wantsTmdbCover)) return;
    timer?.cancel();
    timer = Timer(animeCoverCheckDelay, () {
      final now = ref.read(libraryProvider).value;
      if (now == null || disposed) return;
      unawaited(ref.read(animeCoverDefaultProvider).run(now));
    });
  }, fireImmediately: true);
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
}
