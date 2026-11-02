import 'dart:io';

import '../storage/json_file.dart';

/// An anime's AniList chain as last fetched (section 10c): its entries,
/// first to last, each as `AniNode.toJson` writes it, and when it was
/// fetched.
typedef KeptChain = ({DateTime fetched, List<Map<String, Object?>> nodes});

/// AniList chains kept on the phone, so the season screen need not walk a
/// chain again (two seconds a request under AniList's limit); the daily
/// check fetches them fresh and writes them here. Never in `library.json`.
abstract class AnimeChainStore {
  /// The kept chain with the entry [anilistId] in it, or null.
  Future<KeptChain?> read(int anilistId);

  Future<void> write(KeptChain chain);
}

/// For the tests and the fake.
class MemoryAnimeChainStore implements AnimeChainStore {
  final chains = <KeptChain>[];

  static bool _has(KeptChain chain, int id) =>
      chain.nodes.any((n) => n['id'] == id);

  @override
  Future<KeptChain?> read(int anilistId) async =>
      chains.where((c) => _has(c, anilistId)).firstOrNull;

  @override
  Future<void> write(KeptChain chain) async => chains
    ..removeWhere((c) => chain.nodes.any((n) => _has(c, n['id'] as int)))
    ..add(chain);
}

/// `anime_chains.json` under the cache folder, by the chain's first entry:
/// `{"154587": {"fetched": "2026-11-02T08:00:00.000Z", "nodes": [{"id":
/// 154587, "format": "TV", ...}, ...]}}`. A cleared cache only means
/// walking the chain once more.
class FileAnimeChainStore implements AnimeChainStore {
  FileAnimeChainStore(Directory cache)
    : _file = JsonFile(
        File('${cache.path}${Platform.pathSeparator}anime_chains.json'),
      );

  final JsonFile _file;

  static KeptChain? _parse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final fetched = DateTime.tryParse(json['fetched'] as String? ?? '');
    final nodes = json['nodes'];
    if (fetched == null || nodes is! List || nodes.isEmpty) return null;
    return (
      fetched: fetched,
      nodes: [
        for (final n in nodes)
          if (n is Map<String, Object?> && n['id'] is int) n,
      ],
    );
  }

  @override
  Future<KeptChain?> read(int anilistId) async {
    final json = await _file.read();
    if (json == null) return null;
    for (final value in json.values) {
      final chain = _parse(value);
      if (chain != null && chain.nodes.any((n) => n['id'] == anilistId)) {
        return chain;
      }
    }
    return null;
  }

  @override
  Future<void> write(KeptChain chain) async {
    final json = await _file.read() ?? {};
    final ids = {for (final n in chain.nodes) n['id']};
    // A chain that grew a first entry is kept under it, once.
    json.removeWhere(
      (_, value) =>
          _parse(value)?.nodes.any((n) => ids.contains(n['id'])) ?? false,
    );
    json['${chain.nodes.first['id']}'] = {
      'fetched': chain.fetched.toUtc().toIso8601String(),
      'nodes': chain.nodes,
    };
    await _file.write(json);
  }
}
