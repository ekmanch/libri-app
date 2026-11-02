import 'dart:io';

import '../models/entry_kind.dart';
import '../storage/json_file.dart';

/// What Libri learned about an anime, kept on the phone so the daily check
/// and the season screen need not ask again. Never in `library.json`.
///
/// - [kind]: series or movie, from AniList, and [checked], when that was
///   asked.
/// - [tmdb]: the TMDB show the anime's first entry matched, where its
///   episode titles come from (section 10c), and [tmdbChecked], when TMDB
///   was last asked; a match is kept for good, a miss asked again after a
///   while. A link from an older build has no [tmdbChecked].
/// - [resplit]: true while the anime's seasons in the library may still be
///   split as that TMDB show splits them (an older build took them from
///   there); the daily check re-splits them once and clears it.
typedef AnimeLink = ({
  EntryKind? kind,
  DateTime checked,
  String? tmdb,
  DateTime? tmdbChecked,
  bool resplit,
});

abstract class AnimeLinkStore {
  Future<AnimeLink?> read(int anilistId);

  Future<void> write(int anilistId, AnimeLink link);
}

/// For the tests and the fake.
class MemoryAnimeLinkStore implements AnimeLinkStore {
  final links = <int, AnimeLink>{};

  @override
  Future<AnimeLink?> read(int anilistId) async => links[anilistId];

  @override
  Future<void> write(int anilistId, AnimeLink link) async =>
      links[anilistId] = link;
}

/// `anime_links.json` under the cache folder:
/// `{"154587": {"kind": "series", "checked": "2026-10-20T08:00:00.000Z",
/// "tmdb": "tmdb:tv:209867", "tmdb_checked": "2026-11-02T08:00:00.000Z",
/// "resplit": false}}`. A link written by an older build has only `tmdb`,
/// `kind` and `checked`; its `tmdb` is the show its seasons came from, so
/// it reads as waiting for the re-split. A cleared cache only means asking
/// once more (and no re-split).
class FileAnimeLinkStore implements AnimeLinkStore {
  FileAnimeLinkStore(Directory cache)
    : _file = JsonFile(
        File('${cache.path}${Platform.pathSeparator}anime_links.json'),
      );

  final JsonFile _file;

  @override
  Future<AnimeLink?> read(int anilistId) async {
    final link = (await _file.read())?['$anilistId'];
    if (link is! Map<String, Object?>) return null;
    final checked = DateTime.tryParse(link['checked'] as String? ?? '');
    if (checked == null) return null;
    final kind = link['kind'];
    final tmdb = link['tmdb'] as String?;
    final resplit = link['resplit'];
    return (
      kind: EntryKind.values.where((k) => k.name == kind).firstOrNull,
      checked: checked,
      tmdb: tmdb,
      tmdbChecked: DateTime.tryParse(link['tmdb_checked'] as String? ?? ''),
      resplit: resplit is bool ? resplit : tmdb != null,
    );
  }

  @override
  Future<void> write(int anilistId, AnimeLink link) async {
    final json = await _file.read() ?? {};
    json['$anilistId'] = {
      'kind': link.kind?.name,
      'checked': link.checked.toUtc().toIso8601String(),
      'tmdb': link.tmdb,
      'tmdb_checked': link.tmdbChecked?.toUtc().toIso8601String(),
      'resplit': link.resplit,
    };
    await _file.write(json);
  }
}
