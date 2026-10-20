import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/book_format.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/plan.dart';
import 'package:library_app/data/models/plan_item.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/models/track.dart';

import '../../helpers/sample_library.dart';

import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';

void main() {
  group('Entry', () {
    final json = <String, Object?>{
      'id': 'movies/the-mummy-1999',
      'type': 'movies',
      'title': 'The Mummy',
      'released': '1999',
      'creator': 'Stephen Sommers',
      'status': 'in_progress',
      'rating': null,
      'tags': ['adventure'],
      'note': '',
      'description': '',
      'seasonal_only': false,
      'added': '2026-10-01',
      'source': null,
    };

    test('round-trips the common fields, writing null rating and source', () {
      final entry = Entry.fromJson(json);
      expect(entry.status, EntryStatus.inProgress);
      expect(entry.released, const Released(1999));
      expect(entry.added, DateTime(2026, 10, 1));
      expect(entry.toJson(), json);
      expect(entry.toJson().keys.toList(), json.keys.toList());
    });

    test('omits type-specific fields when absent and keeps them when set', () {
      final plain = Entry.fromJson(json).toJson();
      expect(plain.containsKey('platform'), isFalse);
      expect(plain.containsKey('tracks'), isFalse);

      final book = Entry.fromJson({
        ...json,
        'id': 'books/dracula-1897',
        'type': 'books',
        'formats': ['audiobook', 'physical'],
        'pages': 160,
      });
      expect(book.formats, [BookFormat.audiobook, BookFormat.physical]);
      expect(book.toJson()['formats'], ['audiobook', 'physical']);
      expect(book.pages, 160);
      expect(book.toJson().keys.last, 'pages');
      expect(plain.containsKey('pages'), isFalse);

      expect(dirt.toJson()['kind'], 'album');
      expect(dirt.toJson()['tracks'], [
        {'title': 'Rooster', 'id': 'mb:1', 'rating': 10},
      ]);
      expect(Entry.fromJson(dirt.toJson()), dirt);
    });

    test('source is written after added, null or a lookup id', () {
      final entry = Entry.fromJson(json);
      expect(entry.source, isNull);
      final keys = entry.toJson().keys.toList();
      expect(keys.indexOf('source'), keys.indexOf('added') + 1);

      final linked = entry.copyWith(source: 'tmdb:movie:564');
      expect(linked.toJson()['source'], 'tmdb:movie:564');
      expect(Entry.fromJson(linked.toJson()), linked);
      expect(linked.copyWith(source: null).source, isNull);
    });

    test('a file written before source existed decodes with a null one', () {
      final old = {...json}..remove('source');
      expect(Entry.fromJson(old).source, isNull);
      expect(Entry.fromJson(old).toJson().containsKey('source'), isTrue);
    });

    test('copyWith can clear nullable fields', () {
      expect(mummy.copyWith(rating: null).rating, isNull);
      expect(mummy.copyWith(released: null).released, isNull);
      expect(
        dirt.copyWith(tracks: null).toJson().containsKey('tracks'),
        isFalse,
      );
    });

    test('derives year and release state', () {
      expect(mummy.year, 1999);
      expect(mummy.isReleasedOn(DateTime(2026, 10, 10)), isTrue);
      final coming = mummy.copyWith(released: const Released(2027, 10));
      expect(coming.isReleasedOn(DateTime(2027, 10, 15)), isFalse);
      expect(
        mummy.copyWith(released: null).isReleasedOn(DateTime(2026)),
        isTrue,
      );
    });
  });

  test('Track omits a missing id', () {
    const track = Track(title: 'Time', rating: 10);
    expect(track.toJson(), {'title': 'Time', 'rating': 10});
    expect(Track.fromJson(track.toJson()), track);
  });

  group('PlanItem', () {
    test('round-trips with a period and with no when', () {
      final json = {
        'entry': 'movies/the-mummy-1999',
        'done': false,
        'repeat': true,
        'note': '',
        'when': {'from': '2026-10-19', 'to': '2026-10-31'},
      };
      final item = PlanItem.fromJson(json);
      expect(item.when!.isSingleDay, isFalse);
      expect(item.toJson(), json);

      final bare = PlanItem.fromJson({...json, 'when': null});
      expect(bare.when, isNull);
      expect(bare.toJson()['when'], isNull);
      expect(bare.toJson().containsKey('when'), isTrue);
    });

    test('a single day has equal from and to', () {
      final when = PlanWhen(
        from: DateTime(2026, 10, 3),
        to: DateTime(2026, 10, 3),
      );
      expect(when.isSingleDay, isTrue);
    });
  });

  test('Plan round-trips', () {
    final json = halloweenPlan.toJson();
    expect(json['seasonal_theme'], isTrue);
    expect(json.keys.toList(), [
      'id',
      'name',
      'year',
      'tags',
      'timeline',
      'seasonal_theme',
      'started',
      'items',
    ]);
    expect(Plan.fromJson(json), halloweenPlan);
    expect(halloweenPlan.itemFor(mummy.id)?.repeat, isTrue);
    expect(halloweenPlan.itemFor('nope'), isNull);
  });

  group('Library', () {
    test('round-trips with enum-keyed tag categories', () {
      final library = sampleLibrary();
      final json = library.toJson();
      expect(json['version'], 2);
      expect((json['tags'] as Map).keys, ['Genres', 'Mood', 'Season']);
      expect(Library.fromJson(json), library);
    });

    test('looks up entries and plans', () {
      final library = sampleLibrary();
      expect(library.entryById(dirt.id), dirt);
      expect(library.entryById('x'), isNull);
      expect(library.planById('halloween-2026'), halloweenPlan);
      expect(library.entriesOfType(MediaType.music), [dirt]);
    });

    test('prunes tags used by nothing but keeps tags used only by a plan', () {
      final pruned = sampleLibrary().withUnusedTagsRemoved();
      expect(pruned.tags[TagCategory.genre], ['adventure', 'grunge']);
      expect(pruned.tags[TagCategory.season], ['halloween', 'christmas']);
      expect(pruned.tags[TagCategory.mood], ['lighthearted']);
    });

    test('drops a category left empty', () {
      final library = sampleLibrary().copyWith(
        tags: const {
          TagCategory.genre: ['adventure', 'grunge'],
          TagCategory.other: ['unused'],
        },
      );
      expect(
        library.withUnusedTagsRemoved().tags.containsKey(TagCategory.other),
        isFalse,
      );
    });
  });

  test('enums use the JSON names from DESIGN.md', () {
    final json = Entry.fromJson({
      ...mummy.toJson(),
      'status': 'dnf',
      'type': 'anime',
    }).toJson();
    expect(json['status'], 'dnf');
    expect(json['type'], 'anime');
    expect(
      mummy.copyWith(status: EntryStatus.inProgress).toJson()['status'],
      'in_progress',
    );
  });

  group('series and anime kinds', () {
    final json = <String, Object?>{
      'id': 'movies/the-two-towers-2002',
      'type': 'movies',
      'title': 'The Two Towers',
      'released': '2002',
      'creator': 'Peter Jackson',
      'status': 'want',
      'rating': null,
      'tags': <String>[],
      'note': '',
      'description': '',
      'seasonal_only': false,
      'added': '2026-10-01',
      'source': null,
      'series': {'name': 'The Lord of the Rings', 'number': 2},
    };

    test('series is written after pages, with its number always', () {
      final entry = Entry.fromJson(json);
      expect(
        entry.series,
        const Series(name: 'The Lord of the Rings', number: 2),
      );
      expect(entry.toJson(), json);
      final unnumbered = entry.copyWith(series: const Series(name: 'Dune'));
      expect(unnumbered.toJson()['series'], {'name': 'Dune', 'number': null});
      final book = entry.copyWith(type: MediaType.books, pages: 300);
      final keys = book.toJson().keys.toList();
      expect(keys.indexOf('series'), keys.indexOf('pages') + 1);
      expect(Entry.fromJson(book.toJson()), book);
      expect(
        entry.copyWith(series: null).toJson().containsKey('series'),
        isFalse,
      );
    });

    test('an anime series has a kind and seasons, and uses them', () {
      final anime = Entry.fromJson({
        ...json,
        'id': 'anime/frieren-2023',
        'type': 'anime',
        'title': 'Frieren',
        'released': null,
        'kind': 'series',
        'seasons': [
          {'season': 1, 'released': '2023-09-29', 'status': 'done'},
        ],
      });
      expect(anime.kind, EntryKind.series);
      expect(anime.usesSeasons, isTrue);
      expect(anime.canHaveSeries, isFalse);
      expect(anime.year, 2023);
      final keys = anime.toJson().keys.toList();
      expect(keys.sublist(keys.length - 2), ['kind', 'seasons']);
      expect(Entry.fromJson(anime.toJson()), anime);

      final movie = anime.copyWith(kind: EntryKind.movie, seasons: null);
      expect(movie.usesSeasons, isFalse);
      expect(movie.canHaveSeries, isTrue);
      expect(movie.toJson()['kind'], 'movie');
      // An anime from before kinds: like a movie, and may be in a series.
      final old = anime.copyWith(kind: null, seasons: null);
      expect(old.usesSeasons, isFalse);
      expect(old.canHaveSeries, isTrue);
      // Shows and music never have a series.
      expect(Entry.typeHasSeries(MediaType.shows, null), isFalse);
      expect(Entry.typeHasSeries(MediaType.music, EntryKind.album), isFalse);
      expect(Entry.typeHasSeries(MediaType.games, null), isTrue);
    });

    test('withSeasons derives the status of an anime series only', () {
      const seasons = [
        Season(season: 1, released: Released(2023), status: EntryStatus.done),
        Season(
          season: 2,
          released: Released(2026, 1, 16),
          status: EntryStatus.want,
        ),
      ];
      final series = Entry.fromJson({
        ...json,
        'type': 'anime',
        'kind': 'series',
      });
      expect(
        series.withSeasons(seasons, today: DateTime(2026, 10)).status,
        EntryStatus.inProgress,
      );
      final movie = Entry.fromJson({...json, 'type': 'anime', 'kind': 'movie'});
      expect(
        movie.withSeasons(seasons, today: DateTime(2026, 10)).status,
        EntryStatus.want,
      );
    });
  });
}
