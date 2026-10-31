import 'dart:async';

import '../models/media_type.dart';
import 'lookup_failure.dart';
import 'lookup_match.dart';
import 'lookup_source.dart';

/// What a search came back with: the matches, and which sources failed.
class LookupResult {
  const LookupResult({
    this.matches = const [],
    this.failures = const [],
    this.asked = 0,
    this.complete = true,
  });

  static const empty = LookupResult();

  final List<LookupMatch> matches;

  /// One entry per ask (a source and a type) that failed.
  final List<LookupFailure> failures;

  /// How many providers were asked: one per configured source, and one
  /// more for each that answered only in part ([PartialLookupException]).
  /// Zero means none is set up for the chosen type (or for any type, on
  /// All).
  final int asked;

  /// False while some sources have not answered yet: the matches so far
  /// ([LookupService.searchSteps]).
  final bool complete;

  bool get notConfigured => asked == 0;

  /// Every source asked failed, so there is nothing to show but the reason:
  /// offline when all were offline, rate limited when any was, else other.
  LookupFailure? get allFailed {
    if (asked == 0 || failures.length < asked) return null;
    if (failures.every((f) => f == LookupFailure.offline)) {
      return LookupFailure.offline;
    }
    if (failures.contains(LookupFailure.rateLimited)) {
      return LookupFailure.rateLimited;
    }
    return LookupFailure.other;
  }

  /// Some sources answered and some did not.
  bool get partlyFailed => failures.isNotEmpty && allFailed == null;
}

/// Asks the right sources for a query and merges their answers. One type:
/// its source's own order, cut to [capOneType]. All: every configured
/// source in parallel, each cut to [capPerTypeAll], then one from each type
/// in turn (in [MediaType] order) so no type crowds out the others. Games
/// may be narrowed to one platform (Add / edit entry › Game search on a
/// platform).
/// Failures come back in the result, never as exceptions. A complete
/// answer (no failures) is remembered for the session, so switching the
/// type chips back and forth costs nothing.
class LookupService {
  LookupService(
    this.sources, {
    this.capPerTypeAll = 5,
    this.capOneType = 10,
    this.cacheSize = 50,
  });

  final List<LookupSource> sources;
  final int capPerTypeAll;
  final int capOneType;
  final int cacheSize;

  final _cache = <String, LookupResult>{};

  /// The languages the owner reads, passed on to every source
  /// ([LookupSource.readingLanguages]); the remembered answers go, since a
  /// book search ranks by them.
  set readingLanguages(Set<String> codes) {
    for (final source in sources) {
      source.readingLanguages = codes;
    }
    _cache.clear();
  }

  /// The configured sources for [type].
  List<LookupSource> sourcesFor(MediaType type) => [
    for (final source in sources)
      if (source.isConfigured && source.types.contains(type)) source,
  ];

  /// The source that issued [sourceId] ("tmdb:movie:603"), or null.
  LookupSource? sourceOf(String sourceId) {
    for (final source in sources) {
      if (source.issued(sourceId)) return source;
    }
    return null;
  }

  /// [platform] counts only when [type] is games. The last of
  /// [searchSteps].
  Future<LookupResult> search(
    String query, {
    MediaType? type,
    GamePlatform? platform,
  }) => searchSteps(query, type: type, platform: platform).last;

  /// The matches as the sources answer: a result each time one answers
  /// (or, like books, answers in part: Apple Books in under a second, Open
  /// Library in up to fifteen), marked [LookupResult.complete] on the last.
  /// Only a complete result with no failures is remembered.
  Stream<LookupResult> searchSteps(
    String query, {
    MediaType? type,
    GamePlatform? platform,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      yield LookupResult.empty;
      return;
    }
    final on = type == MediaType.games ? platform : null;
    final key = '${type?.name ?? '*'}|${on?.id ?? ''}|${trimmed.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) {
      yield cached;
      return;
    }

    final types = type == null ? MediaType.values : [type];
    final limit = type == null ? capPerTypeAll : capOneType;
    final asks = <(MediaType, LookupSource)>[
      for (final t in types)
        for (final source in sourcesFor(t)) (t, source),
    ];
    if (asks.isEmpty) {
      yield const LookupResult();
      return;
    }

    // The latest answer of each ask (null until its first), and how many
    // have given their last.
    final answers = List<Object?>.filled(asks.length, null);
    var pending = asks.length;
    final updates = StreamController<void>();
    for (final (i, (t, source)) in asks.indexed) {
      _askSteps(source, trimmed, t, limit, on).listen((step) {
        answers[i] = step.answer;
        if (step.last) pending--;
        updates.add(null);
        if (pending == 0) updates.close();
      });
    }

    await for (final _ in updates.stream) {
      final failures = <LookupFailure>[];
      var partial = 0;
      final byType = <MediaType, List<LookupMatch>>{};
      for (final (i, answer) in answers.indexed) {
        final (t, _) = asks[i];
        switch (answer) {
          case List<LookupMatch> matches:
            byType.putIfAbsent(t, () => []).addAll(matches.take(limit));
          case LookupFailure failure:
            failures.add(failure);
          case (List<LookupMatch> matches, LookupFailure failure):
            byType.putIfAbsent(t, () => []).addAll(matches.take(limit));
            failures.add(failure);
            partial++;
        }
      }
      final result = LookupResult(
        matches: type == null
            ? _roundRobin([for (final t in types) byType[t] ?? const []])
            : [...?byType[type]],
        failures: failures,
        asked: asks.length + partial,
        complete: pending == 0,
      );
      if (result.complete && failures.isEmpty) _remember(key, result);
      yield result;
    }
  }

  /// Covers to pick from for an entry titled [title] (Add / edit entry ›
  /// Pick a cover): each configured source for [type] in turn, in its own
  /// order, only matches with a cover and one of each image. Failures come
  /// back in the result, as for [search]; nothing is remembered, since the
  /// picker is opened rarely.
  Future<LookupResult> coverChoices(
    String title, {
    required MediaType type,
    String? creator,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return LookupResult.empty;
    final asked = sourcesFor(type);
    final failures = <LookupFailure>[];
    var partial = 0;
    final seen = <String>{};
    final matches = <LookupMatch>[];
    void add(List<LookupMatch> hits) {
      for (final hit in hits) {
        final url = hit.cacheCoverUrl;
        if (url != null && seen.add(url)) matches.add(hit);
      }
    }

    for (final source in asked) {
      try {
        add(await source.coverChoices(trimmed, type: type, creator: creator));
      } on PartialLookupException catch (e) {
        add(e.matches);
        failures.add(e.failure);
        partial++;
      } on LookupException catch (e) {
        failures.add(e.failure);
      } on Object {
        failures.add(LookupFailure.other);
      }
    }
    return LookupResult(
      matches: matches,
      failures: failures,
      asked: asked.length + partial,
    );
  }

  /// The platforms games can be narrowed to (Add / edit entry › Platform
  /// picker): the first configured game source's. Empty when none is set
  /// up; throws [LookupException] when the list could not be had.
  Future<List<GamePlatform>> platforms() async {
    for (final source in sourcesFor(MediaType.games)) {
      final platforms = await source.platforms();
      if (platforms.isNotEmpty) return platforms;
    }
    return const [];
  }

  /// One ask's answers as they come: a list of matches, the failure, or for
  /// a partial answer both; [last] marks the final one.
  Stream<({Object answer, bool last})> _askSteps(
    LookupSource source,
    String query,
    MediaType type,
    int limit,
    GamePlatform? platform,
  ) async* {
    List<LookupMatch> hits = const [];
    try {
      final steps = platform == null
          ? source.searchSteps(query, type: type, limit: limit)
          : Stream.fromFuture(
              source.searchOnPlatform(query, platform, limit: limit),
            );
      await for (final step in steps) {
        hits = step;
        yield (answer: hits, last: false);
      }
      yield (answer: hits, last: true);
    } on PartialLookupException catch (e) {
      yield (answer: (e.matches, e.failure), last: true);
    } on LookupException catch (e) {
      yield (answer: e.failure, last: true);
    } on Object {
      yield (answer: LookupFailure.other, last: true);
    }
  }

  static List<LookupMatch> _roundRobin(List<List<LookupMatch>> lists) {
    final out = <LookupMatch>[];
    final longest = lists.fold(0, (n, l) => l.length > n ? l.length : n);
    for (var i = 0; i < longest; i++) {
      for (final list in lists) {
        if (i < list.length) out.add(list[i]);
      }
    }
    return out;
  }

  void _remember(String key, LookupResult result) {
    _cache[key] = result;
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }
}
