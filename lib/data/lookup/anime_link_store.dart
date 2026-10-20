import 'dart:io';

import '../models/entry_kind.dart';
import '../storage/json_file.dart';

/// What Libri learned about an anime from AniList, kept on the phone so the
/// daily check and the season screen need not ask again: its kind (series
/// or movie), the TMDB show its seasons come from when one was found, and
/// when it was last checked. Never in `library.json`.
typedef AnimeLink = ({String? tmdb, EntryKind? kind, DateTime checked});

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
/// `{"154587": {"tmdb": "tmdb:tv:209867", "kind": "series", "checked":
/// "2026-10-20T08:00:00.000Z"}}`. A cleared cache only means asking once
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
      tmdb: link['tmdb'] as String?,
      kind: EntryKind.values.where((k) => k.name == kind).firstOrNull,
      checked: checked,
    );
  }

  @override
  Future<void> write(int anilistId, AnimeLink link) async {
    final json = await _file.read() ?? {};
    json['$anilistId'] = {
      'tmdb': link.tmdb,
      'kind': link.kind?.name,
      'checked': link.checked.toUtc().toIso8601String(),
    };
    await _file.write(json);
  }
}
