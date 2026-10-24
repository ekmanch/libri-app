import 'dart:convert';
import 'dart:io';

import '../storage/atomic_file.dart';
import 'lookup_source.dart';

/// A series as stored, with when it was fetched and the entry's series name
/// it was asked for ([asked], null when the entry had none or the list was
/// stored before the name was kept).
typedef StoredSeries = ({DateTime fetched, SeriesParts series, String? asked});

/// Where a fetched series (its name and parts) is kept, by the lookup id of
/// the entry it was fetched for. On the phone only, never in `library.json`.
abstract class SeriesStore {
  Future<StoredSeries?> read(String source);

  Future<void> write(
    String source,
    SeriesParts series, {
    required DateTime fetched,
    String? asked,
  });

  /// Drops every series but those of [keepSources].
  Future<void> prune(Set<String> keepSources);
}

/// For the tests, the walks and the FIRST_RUN demo.
class MemorySeriesStore implements SeriesStore {
  final _series = <String, StoredSeries>{};

  @override
  Future<StoredSeries?> read(String source) async => _series[source];

  @override
  Future<void> write(
    String source,
    SeriesParts series, {
    required DateTime fetched,
    String? asked,
  }) async {
    _series[source] = (
      fetched: fetched,
      series: (name: series.name, parts: List.unmodifiable(series.parts)),
      asked: asked,
    );
  }

  @override
  Future<void> prune(Set<String> keepSources) async {
    _series.removeWhere((key, _) => !keepSources.contains(key));
  }
}

/// One JSON file per entry under `<cache>/series/`, named after its lookup
/// id ("tmdb-movie-120.json").
class FileSeriesStore implements SeriesStore {
  FileSeriesStore(this.directory);

  final Directory directory;

  static const _encoder = JsonEncoder.withIndent('  ');

  /// 2 since 2026-10-24: Wikidata's parts are cleaned up when fetched (the
  /// parts of a part, unnumbered extras) and carry their authors.
  static const version = 2;

  Directory get _series =>
      Directory('${directory.path}${Platform.pathSeparator}series');

  static String fileNameFor(String source) =>
      '${source.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')}.json';

  File _file(String source) =>
      File('${_series.path}${Platform.pathSeparator}${fileNameFor(source)}');

  @override
  Future<StoredSeries?> read(String source) async {
    final file = _file(source);
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?> || json['source'] != source) {
        return null;
      }
      var fetched = DateTime.tryParse(json['fetched'] as String? ?? '');
      final name = json['name'];
      if (fetched == null || name is! String) return null;
      // A list stored before the current [version] was cleaned by older
      // rules: it shows, and is fetched again at once.
      if (json['version'] != version) fetched = DateTime.utc(1970);
      final asked = json['asked'];
      return (
        fetched: fetched,
        asked: asked is String ? asked : null,
        series: (
          name: name,
          parts: [
            for (final item in json['parts'] as List<Object?>? ?? const [])
              if (item is Map<String, Object?> && item['title'] is String)
                (
                  number: item['number'] as int?,
                  title: item['title'] as String,
                  year: item['year'] as int?,
                  source: item['source'] as String?,
                  creator: item['creator'] as String?,
                ),
          ],
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(
    String source,
    SeriesParts series, {
    required DateTime fetched,
    String? asked,
  }) => writeAtomically(
    _file(source),
    '${_encoder.convert({
      'version': version,
      'source': source,
      'fetched': fetched.toUtc().toIso8601String(),
      'asked': ?asked,
      'name': series.name,
      'parts': [
        for (final p in series.parts) {'number': p.number, 'title': p.title, 'year': p.year, 'source': p.source, 'creator': ?p.creator},
      ],
    })}\n',
  );

  @override
  Future<void> prune(Set<String> keepSources) async {
    if (!await _series.exists()) return;
    final keep = {for (final s in keepSources) fileNameFor(s)};
    await for (final entity in _series.list()) {
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
