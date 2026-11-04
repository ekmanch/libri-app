import 'dart:io';

import '../models/season_split.dart';
import '../storage/json_file.dart';

/// The splits a show's sources offer, as last read, with when.
typedef StoredSplits = ({DateTime fetched, List<SeasonSplit> splits});

/// Where the splits of each show's seasons are kept, by the show's lookup
/// id and TMDB show (`SeasonSplitService.keyOf`). On the phone only, never
/// in `library.json`.
abstract class SeasonSplitStore {
  Future<StoredSplits?> read(String key);

  Future<void> write(String key, List<SeasonSplit> splits, DateTime fetched);
}

/// For the tests, the walks and the FIRST_RUN demo.
class MemorySeasonSplitStore implements SeasonSplitStore {
  final splits = <String, StoredSplits>{};

  @override
  Future<StoredSplits?> read(String key) async => splits[key];

  @override
  Future<void> write(
    String key,
    List<SeasonSplit> splits,
    DateTime fetched,
  ) async {
    this.splits[key] = (fetched: fetched, splits: List.unmodifiable(splits));
  }
}

/// `season_splits.json` under the cache folder: `{"version": 2,
/// "anilist:11061|tmdb:tv:46298": {"fetched": "2026-11-03T08:00:00.000Z",
/// "splits": [...]}}`. Version 2 since 2026-11-04: what the build of the
/// day before stored (AniList's chain with its parts unfolded, every TMDB
/// group) is dropped once, by [version]. A cleared cache only means
/// reading the splits again.
class FileSeasonSplitStore implements SeasonSplitStore {
  FileSeasonSplitStore(Directory cache)
    : _file = JsonFile(
        File('${cache.path}${Platform.pathSeparator}season_splits.json'),
      );

  final JsonFile _file;

  static const version = 2;

  /// The file's contents when they are this version's, else empty.
  Future<Map<String, Object?>> _current() async {
    final json = await _file.read();
    return json != null && json['version'] == version ? json : {};
  }

  @override
  Future<StoredSplits?> read(String key) async {
    final stored = (await _current())[key];
    if (stored is! Map<String, Object?>) return null;
    final fetched = DateTime.tryParse(stored['fetched'] as String? ?? '');
    if (fetched == null) return null;
    try {
      return (
        fetched: fetched,
        splits: [
          for (final item in stored['splits'] as List<Object?>? ?? const [])
            if (item is Map<String, Object?>) SeasonSplit.fromJson(item),
        ],
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(
    String key,
    List<SeasonSplit> splits,
    DateTime fetched,
  ) async {
    final json = await _current();
    json['version'] = version;
    json[key] = {
      'fetched': fetched.toUtc().toIso8601String(),
      'splits': [for (final s in splits) s.toJson()],
    };
    await _file.write(json);
  }
}
