import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/images/anime_cover_default.dart';
import 'package:library_app/data/lookup/lookup_failure.dart';
import 'package:library_app/data/lookup/lookup_service.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/operations/entry_operations.dart';
import 'package:library_app/data/operations/library_operation.dart';
import 'package:library_app/data/repository/library_repository.dart';
import 'package:library_app/dev/fake_lookup.dart';

/// TMDB with a poster for every show but [none]; [down] makes it fail.
class _Tmdb extends FakeLookupSource {
  _Tmdb({this.none = const {}});

  final Set<String> none;
  bool down = false;
  final asked = <String>[];

  @override
  Future<String?> coverUrl(String source, {required MediaType type}) async {
    if (down) throw const LookupException(LookupFailure.offline);
    asked.add(source);
    return none.contains(source) ? null : 'https://image.tmdb.org/$source.jpg';
  }
}

class _Repository implements LibraryRepository {
  _Repository(this.library);

  Library library;
  final applied = <LibraryOperation>[];

  @override
  Future<Library> apply(LibraryOperation operation) async {
    applied.add(operation);
    return library = operation.apply(library);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Entry _anime(
  String name, {
  String? tmdb,
  String? coverFrom,
  EntryKind kind = EntryKind.series,
}) => Entry(
  id: 'anime/$name',
  type: MediaType.anime,
  title: name,
  kind: kind,
  status: EntryStatus.want,
  added: DateTime(2026),
  source: 'anilist:$name',
  tmdb: tmdb,
  coverFrom: coverFrom,
);

void main() {
  test('every anime with a tmdb link and no cover_from gets the poster of '
      'its show, and nothing else is touched', () async {
    final library = Library(
      entries: [
        _anime('frieren', tmdb: 'tmdb:tv:209867'),
        // No link: AniList's cover, no cover_from.
        _anime('akira', kind: EntryKind.movie),
        // A cover picked already: AniList's own, another match's, a file.
        _anime('bleach', tmdb: 'tmdb:tv:30984', coverFrom: 'anilist:bleach'),
        _anime('shiki', tmdb: 'tmdb:tv:36581', coverFrom: 'anilist:999'),
        _anime(
          'berserk',
          tmdb: 'tmdb:tv:35935',
          coverFrom: 'repo:anime/berserk.a3f9c2e.jpg',
        ),
        // A show without a poster keeps AniList's.
        _anime('hellsing', tmdb: 'tmdb:tv:16830'),
      ],
    );
    final tmdb = _Tmdb(none: {'tmdb:tv:16830'});
    final repository = _Repository(library);
    final check = AnimeCoverDefault(
      lookups: LookupService([tmdb]),
      repository: repository,
    );

    expect(await check.run(library), 1);
    expect(tmdb.asked, ['tmdb:tv:209867', 'tmdb:tv:16830']);
    expect(
      repository.library.entryById('anime/frieren')!.coverFrom,
      'tmdb:tv:209867',
    );
    expect(repository.library.entryById('anime/hellsing')!.coverFrom, isNull);
    expect(repository.applied, hasLength(1));

    // A show known to have no poster is not asked about twice a session.
    tmdb.asked.clear();
    expect(await check.run(repository.library), 0);
    expect(tmdb.asked, isEmpty);
  });

  test(
    'a check that cannot be made writes nothing and is made again',
    () async {
      final library = Library(
        entries: [_anime('frieren', tmdb: 'tmdb:tv:209867')],
      );
      final tmdb = _Tmdb()..down = true;
      final repository = _Repository(library);
      final check = AnimeCoverDefault(
        lookups: LookupService([tmdb]),
        repository: repository,
      );
      expect(await check.run(library), 0);
      expect(repository.applied, isEmpty);
      tmdb.down = false;
      expect(await check.run(library), 1);
    },
  );

  test('the default never replaces a cover picked meanwhile', () {
    final picked = Library(
      entries: [
        _anime('frieren', tmdb: 'tmdb:tv:209867', coverFrom: 'anilist:frieren'),
      ],
    );
    const op = SetCover(
      'anime/frieren',
      coverFrom: 'tmdb:tv:209867',
      ifNone: true,
    );
    expect(op.apply(picked), same(picked));
    final again = SetCover.fromJson(op.toJson());
    expect(again.ifNone, isTrue);
    expect(
      SetCover.fromJson({'entryId': 'a', 'coverFrom': null}).ifNone,
      isFalse,
    );
  });

  test('TMDB’s poster follows the link; any other cover stays', () {
    String? after(String? coverFrom, String? to) =>
        coverFromAfterTmdbChange(coverFrom, oldTmdb: 'tmdb:tv:1', newTmdb: to);
    expect(after('tmdb:tv:1', 'tmdb:tv:2'), 'tmdb:tv:2');
    // Cleared, as when the anime becomes a movie.
    expect(after('tmdb:tv:1', null), isNull);
    expect(after('tmdb:tv:1', 'tmdb:tv:1'), 'tmdb:tv:1');
    expect(after('anilist:5', 'tmdb:tv:2'), 'anilist:5');
    expect(after('anilist:5', null), 'anilist:5');
    expect(after('repo:anime/x.jpg', null), 'repo:anime/x.jpg');
    expect(after(null, 'tmdb:tv:2'), isNull);
  });
}
