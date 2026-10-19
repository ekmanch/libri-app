import 'dart:convert';
import 'dart:io';

import '../models/released.dart';
import '../storage/atomic_file.dart';
import 'episode_info.dart';

/// A season's episodes as stored, with when they were fetched.
typedef StoredEpisodes = ({DateTime fetched, List<EpisodeInfo> episodes});

/// Where fetched episodes are kept, by the show's lookup id and the season
/// number. On the phone only, never in `library.json`.
abstract class EpisodeStore {
  Future<StoredEpisodes?> read(String showSource, int season);
  Future<void> write(
    String showSource,
    int season,
    List<EpisodeInfo> episodes, {
    required DateTime fetched,
  });

  /// Drops every show's episodes but those of [keepSources].
  Future<void> prune(Set<String> keepSources);
}

/// For the tests, the walks and the FIRST_RUN demo.
class MemoryEpisodeStore implements EpisodeStore {
  final _seasons = <(String, int), StoredEpisodes>{};

  @override
  Future<StoredEpisodes?> read(String showSource, int season) async =>
      _seasons[(showSource, season)];

  @override
  Future<void> write(
    String showSource,
    int season,
    List<EpisodeInfo> episodes, {
    required DateTime fetched,
  }) async {
    _seasons[(showSource, season)] = (
      fetched: fetched,
      episodes: List.unmodifiable(episodes),
    );
  }

  @override
  Future<void> prune(Set<String> keepSources) async {
    _seasons.removeWhere((key, _) => !keepSources.contains(key.$1));
  }
}

/// One JSON file per show under `<cache>/episodes/`, named after the id
/// ("tmdb-tv-1399.json"), with its fetched seasons by number.
class FileEpisodeStore implements EpisodeStore {
  FileEpisodeStore(this.directory);

  final Directory directory;

  static const _encoder = JsonEncoder.withIndent('  ');

  Directory get _episodes =>
      Directory('${directory.path}${Platform.pathSeparator}episodes');

  static String fileNameFor(String showSource) =>
      '${showSource.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')}.json';

  File _file(String showSource) => File(
    '${_episodes.path}${Platform.pathSeparator}${fileNameFor(showSource)}',
  );

  /// The file's seasons, or none when it is missing, unreadable or for
  /// another show.
  Future<Map<String, Object?>> _seasons(String showSource) async {
    final file = _file(showSource);
    try {
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?> || json['source'] != showSource) {
        return {};
      }
      return {...json['seasons'] as Map<String, Object?>? ?? const {}};
    } on Object {
      return {};
    }
  }

  @override
  Future<StoredEpisodes?> read(String showSource, int season) async {
    final stored = (await _seasons(showSource))['$season'];
    if (stored is! Map<String, Object?>) return null;
    final fetched = DateTime.tryParse(stored['fetched'] as String? ?? '');
    if (fetched == null) return null;
    return (
      fetched: fetched,
      episodes: [
        for (final item in stored['episodes'] as List<Object?>? ?? const [])
          if (item is Map<String, Object?> && item['number'] is int)
            (
              number: item['number'] as int,
              title: item['title'] as String?,
              aired: Released.tryParse(item['aired'] as String? ?? ''),
              runtime: item['runtime'] as int?,
            ),
      ],
    );
  }

  @override
  Future<void> write(
    String showSource,
    int season,
    List<EpisodeInfo> episodes, {
    required DateTime fetched,
  }) async {
    final seasons = await _seasons(showSource);
    seasons['$season'] = {
      'fetched': fetched.toUtc().toIso8601String(),
      'episodes': [
        for (final e in episodes)
          {
            'number': e.number,
            'title': e.title,
            'aired': e.aired?.toString(),
            'runtime': e.runtime,
          },
      ],
    };
    await writeAtomically(
      _file(showSource),
      '${_encoder.convert({'source': showSource, 'seasons': seasons})}\n',
    );
  }

  @override
  Future<void> prune(Set<String> keepSources) async {
    if (!await _episodes.exists()) return;
    final keep = {for (final s in keepSources) fileNameFor(s)};
    await for (final entity in _episodes.list()) {
      if (entity is File && !keep.contains(entity.uri.pathSegments.last)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // The next prune gets it.
        }
      }
    }
  }
}
