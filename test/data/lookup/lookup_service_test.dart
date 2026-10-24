import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/lookup/lookup_source.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/dev/fake_lookup.dart';

/// Answers every search with [count] numbered matches, or throws.
class _Stub extends LookupSource {
  _Stub(
    this.id,
    this.types, {
    this.count = 3,
    this.failure,
    this.configured = true,
  });

  @override
  final String id;
  @override
  final Set<MediaType> types;
  final int count;
  final LookupFailure? failure;
  final bool configured;
  final searches = <String>[];

  @override
  bool get isConfigured => configured;

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async {
    searches.add('$query:${type.name}:$limit');
    if (failure case final failure?) throw LookupException(failure);
    return [
      for (var i = 1; i <= count; i++)
        LookupMatch(
          type: type,
          title: '$query ${type.name} $i',
          source: '$id:$i',
        ),
    ];
  }

  @override
  Future<LookupMatch?> match(
    String title, {
    required MediaType type,
    int? year,
    String? creator,
  }) async => null;

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async =>
      null;
}

/// A source with two providers, one of which did not answer.
class _Partial extends _Stub {
  _Partial(this.answered) : super('openlibrary', {MediaType.books});

  final List<LookupMatch> answered;
  var calls = 0;

  @override
  Future<List<LookupMatch>> search(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async {
    calls++;
    throw PartialLookupException(answered, LookupFailure.other);
  }
}

/// A source that answers in two steps, the second only once [release] is
/// completed: an early hit, then the full list.
class _TwoSteps extends _Stub {
  _TwoSteps() : super('openlibrary', {MediaType.books});

  final release = Completer<void>();

  @override
  Stream<List<LookupMatch>> searchSteps(
    String query, {
    required MediaType type,
    int limit = 10,
  }) async* {
    yield [LookupMatch(type: type, title: 'Early', source: 'itunes:1')];
    await release.future;
    yield [
      LookupMatch(type: type, title: 'Full', source: 'openlibrary:1'),
      LookupMatch(type: type, title: 'Early', source: 'itunes:1'),
    ];
  }
}

void main() {
  test('one type asks its source once, capped at ten, in its order', () async {
    final tmdb = _Stub('tmdb', {MediaType.movies, MediaType.shows}, count: 12);
    final service = LookupService([tmdb]);
    final result = await service.search(' Dune ', type: MediaType.movies);
    expect(tmdb.searches, ['Dune:movies:10']);
    expect(result.matches.length, 10);
    expect(result.matches.first.title, 'Dune movies 1');
    expect(result.asked, 1);
    expect(result.failures, isEmpty);
    expect(result.allFailed, isNull);
  });

  test('All asks every configured source and takes turns by type', () async {
    final tmdb = _Stub('tmdb', {MediaType.movies, MediaType.shows}, count: 7);
    final igdb = _Stub('igdb', {MediaType.games}, count: 1);
    final deezer = _Stub('deezer', {MediaType.music}, configured: false);
    final service = LookupService([tmdb, igdb, deezer]);
    final result = await service.search('x');
    expect(tmdb.searches, ['x:movies:5', 'x:shows:5']);
    expect(igdb.searches, ['x:games:5']);
    expect(deezer.searches, isEmpty);
    expect(result.asked, 3);
    expect(result.matches.map((m) => m.title).take(4), [
      'x movies 1',
      'x shows 1',
      'x games 1',
      'x movies 2',
    ]);
    // Seven per type cut to five.
    expect(result.matches.length, 5 + 5 + 1);
  });

  test('a failing source leaves the others answers in place', () async {
    final tmdb = _Stub('tmdb', {MediaType.movies});
    final anilist = _Stub('anilist', {
      MediaType.anime,
    }, failure: LookupFailure.offline);
    final result = await LookupService([tmdb, anilist]).search('x');
    expect(result.matches, isNotEmpty);
    expect(result.failures, [LookupFailure.offline]);
    expect(result.partlyFailed, isTrue);
    expect(result.allFailed, isNull);
  });

  test('a source answering in part counts as an answer and a failure, '
      'and is not remembered', () async {
    final books = _Partial([
      const LookupMatch(
        type: MediaType.books,
        title: 'Dracula',
        source: 'openlibrary:OL45804W',
      ),
    ]);
    final service = LookupService([books]);
    final result = await service.search('x', type: MediaType.books);
    expect(result.matches.single.title, 'Dracula');
    expect(result.failures, [LookupFailure.other]);
    expect(result.asked, 2);
    expect(result.partlyFailed, isTrue);
    expect(result.allFailed, isNull);

    // Nothing from the part that answered: still a partial failure, not
    // "no matches" and not "the lookup did not answer".
    final empty = await LookupService([_Partial(const [])])
        .search('x', type: MediaType.books);
    expect(empty.matches, isEmpty);
    expect(empty.partlyFailed, isTrue);
    expect(empty.allFailed, isNull);

    await service.search('x', type: MediaType.books);
    expect(books.calls, 2);
  });

  test('all sources failing names the shared reason', () async {
    Future<LookupFailure?> overall(LookupFailure a, LookupFailure b) async {
      final result = await LookupService([
        _Stub('a', {MediaType.movies}, failure: a),
        _Stub('b', {MediaType.books}, failure: b),
      ]).search('x');
      expect(result.matches, isEmpty);
      return result.allFailed;
    }

    expect(
      await overall(LookupFailure.offline, LookupFailure.offline),
      LookupFailure.offline,
    );
    expect(
      await overall(LookupFailure.offline, LookupFailure.rateLimited),
      LookupFailure.rateLimited,
    );
    expect(
      await overall(LookupFailure.other, LookupFailure.offline),
      LookupFailure.other,
    );
  });

  test('nothing configured for the type is "not set up"', () async {
    final service = LookupService([
      _Stub('igdb', {MediaType.games}, configured: false),
    ]);
    final result = await service.search('x', type: MediaType.games);
    expect(result.notConfigured, isTrue);
    expect(result.allFailed, isNull);
    expect(
      (await service.search('x', type: MediaType.movies)).notConfigured,
      isTrue,
    );
  });

  test('an empty query asks nothing', () async {
    final tmdb = _Stub('tmdb', {MediaType.movies});
    expect(await LookupService([tmdb]).search('   '), LookupResult.empty);
    expect(tmdb.searches, isEmpty);
  });

  test('a complete answer is remembered, a failed one is not', () async {
    final tmdb = _Stub('tmdb', {MediaType.movies});
    final flaky = _Stub('anilist', {
      MediaType.anime,
    }, failure: LookupFailure.offline);
    final service = LookupService([tmdb, flaky]);
    await service.search('dune', type: MediaType.movies);
    await service.search('DUNE', type: MediaType.movies);
    expect(tmdb.searches.length, 1);
    await service.search('dune', type: MediaType.anime);
    await service.search('dune', type: MediaType.anime);
    expect(flaky.searches.length, 2);
  });

  test('games narrow to a platform; other types and All ignore it', () async {
    final fake = FakeLookupSource();
    final service = LookupService([fake]);
    final snes = (await service.platforms()).firstWhere(
      (p) => p.name == 'Super Nintendo',
    );
    final on = await service.search(
      'street fighter ii',
      type: MediaType.games,
      platform: snes,
    );
    expect(fake.calls.last, 'search:street fighter ii:Super Nintendo');
    expect(on.matches.map((m) => m.source), ['igdb:321621', 'igdb:322188']);
    // Each platform is its own answer; any platform is another.
    await service.search('street fighter ii', type: MediaType.games);
    expect(fake.calls.last, 'search:street fighter ii:games');
    await service.search(
      'street fighter ii',
      type: MediaType.movies,
      platform: snes,
    );
    expect(fake.calls.last, 'search:street fighter ii:movies');
    expect(
      await LookupService([
        _Stub('tmdb', {MediaType.movies}),
      ]).platforms(),
      isEmpty,
    );
  });

  test('searchSteps shows the matches so far, then the complete answer, '
      'and remembers only that', () async {
    final books = _TwoSteps();
    final service = LookupService([books]);
    final steps = <LookupResult>[];
    await service.searchSteps('dune', type: MediaType.books).listen((r) {
      steps.add(r);
      if (!books.release.isCompleted) books.release.complete();
    }).asFuture<void>();
    expect(steps.first.complete, isFalse);
    expect(steps.first.matches.map((m) => m.title), ['Early']);
    expect(steps.last.complete, isTrue);
    expect(steps.last.matches.map((m) => m.title), ['Full', 'Early']);
    // Asked again, the complete answer comes from memory in one step.
    final again = await service
        .searchSteps('dune', type: MediaType.books)
        .toList();
    expect(again.single.matches.map((m) => m.title), ['Full', 'Early']);
  });

  test('sourceOf finds the source by the id prefix', () {
    final tmdb = _Stub('tmdb', {MediaType.movies});
    final service = LookupService([tmdb]);
    expect(service.sourceOf('tmdb:movie:603'), tmdb);
    expect(service.sourceOf('igdb:1009'), isNull);
    expect(LookupMatch.providerOf('deezer:album:1'), 'deezer');
  });

  test('cover choices: every source in turn, with a cover, one of each image; '
      'failures in the result', () async {
    final a = _Covers('a', ['x', 'y', null, 'x']);
    final b = _Covers('b', ['y', 'z']);
    final down = _Covers('c', const [], failure: LookupFailure.offline);
    final result = await LookupService([
      a,
      b,
      down,
    ]).coverChoices(' Dune ', type: MediaType.books, creator: 'Frank Herbert');
    expect(result.matches.map((m) => m.coverUrl), ['x', 'y', 'z']);
    expect(result.matches.map((m) => m.source), ['a:0', 'a:1', 'b:1']);
    expect(a.asked, ['Dune:Frank Herbert']);
    expect(result.failures, [LookupFailure.offline]);
    expect(result.partlyFailed, isTrue);
  });
}

/// Answers [coverChoices] with one match per URL in [covers] (null for a
/// match without a cover), or throws [failure].
class _Covers extends _Stub {
  _Covers(String id, this.covers, {super.failure})
    : super(id, {MediaType.books});

  final List<String?> covers;
  final asked = <String>[];

  @override
  Future<List<LookupMatch>> coverChoices(
    String title, {
    required MediaType type,
    String? creator,
  }) async {
    asked.add('$title:$creator');
    if (failure case final failure?) throw LookupException(failure);
    return [
      for (final (i, url) in covers.indexed)
        LookupMatch(type: type, title: title, source: '$id:$i', coverUrl: url),
    ];
  }
}
