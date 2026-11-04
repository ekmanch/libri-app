import 'dart:io';

import '../models/entry_kind.dart';
import '../storage/json_file.dart';

/// What Libri learned about an anime, kept on the phone so the daily check
/// and the season screen need not ask again. Never in `library.json`.
///
/// - [kind]: series or movie, from AniList, and [checked], when that was
///   asked.
/// - [tmdb]: the TMDB show the anime's first entry matched, where its
///   episode titles and the other splits of its seasons come from (section
///   10c), and [tmdbChecked], when TMDB was last asked; a match is kept for
///   good, a miss asked again after a while. A link from an older build
///   has no [tmdbChecked].
/// - [tvdb] and [tvdbSeason]: ARM's map of the entry to a TVDB show and
///   season (null for a long run), and [armChecked], when ARM was asked;
///   null on a link from before ARM, which is asked. A row is kept for
///   good; no row is asked again after a while.
typedef AnimeLink = ({
  EntryKind? kind,
  DateTime checked,
  String? tmdb,
  DateTime? tmdbChecked,
  int? tvdb,
  int? tvdbSeason,
  DateTime? armChecked,
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
/// "tvdb": 424536, "tvdb_season": 1, "arm_checked":
/// "2026-11-04T08:00:00.000Z"}}`.
/// A `resplit` key an older build wrote is ignored (checks no longer
/// re-split anything, section 10c). A cleared cache only means asking once
/// more.
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
    return (
      kind: EntryKind.values.where((k) => k.name == kind).firstOrNull,
      checked: checked,
      tmdb: link['tmdb'] as String?,
      tmdbChecked: DateTime.tryParse(link['tmdb_checked'] as String? ?? ''),
      tvdb: (link['tvdb'] as num?)?.toInt(),
      tvdbSeason: (link['tvdb_season'] as num?)?.toInt(),
      armChecked: DateTime.tryParse(link['arm_checked'] as String? ?? ''),
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
      'tvdb': link.tvdb,
      'tvdb_season': link.tvdbSeason,
      'arm_checked': link.armChecked?.toUtc().toIso8601String(),
    };
    await _file.write(json);
  }
}
