import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/models/track.dart';
import 'package:library_app/data/operations/operations.dart';

import '../../helpers/sample_library.dart';

import 'package:library_app/data/models/entry_kind.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/models/series.dart';

void main() {
  test('SetStatus changes one entry in place', () {
    final result = SetStatus(mummy.id, EntryStatus.want).apply(sampleLibrary());
    expect(result.entries.first.status, EntryStatus.want);
    expect(result.entries.map((e) => e.id), [mummy.id, dirt.id]);
  });

  test('operations on a missing entry leave the library unchanged', () {
    final library = sampleLibrary();
    expect(const SetStatus('nope', EntryStatus.done).apply(library), library);
    expect(const SetRating('nope', 5).apply(library), library);
    expect(const DeleteEntry('nope').apply(library), library);
    expect(UpdateEntry(mummy.copyWith(id: 'nope')).apply(library), library);
  });

  test('movies and music are never In progress, and music never DNF', () {
    expect(EntryStatus.optionsFor(MediaType.movies), [
      EntryStatus.want,
      EntryStatus.done,
      EntryStatus.dnf,
    ]);
    expect(EntryStatus.optionsFor(MediaType.music), [
      EntryStatus.want,
      EntryStatus.done,
    ]);
    for (final type in [
      MediaType.shows,
      MediaType.books,
      MediaType.games,
      MediaType.anime,
    ]) {
      expect(EntryStatus.optionsFor(type), EntryStatus.values);
    }
    expect(
      () => SetStatus(dirt.id, EntryStatus.dnf).apply(sampleLibrary()),
      throwsArgumentError,
    );
    expect(
      () => SetStatus(dirt.id, EntryStatus.inProgress).apply(sampleLibrary()),
      throwsArgumentError,
    );
    expect(
      () => SetStatus(mummy.id, EntryStatus.inProgress).apply(sampleLibrary()),
      throwsArgumentError,
    );
    final movie = SetStatus(
      mummy.id,
      EntryStatus.dnf,
    ).apply(sampleLibrary()).entryById(mummy.id)!;
    expect(movie.status, EntryStatus.dnf);
  });

  test('SetRating sets and clears', () {
    final library = sampleLibrary();
    expect(
      SetRating(mummy.id, 3).apply(library).entryById(mummy.id)!.rating,
      3,
    );
    expect(
      SetRating(mummy.id, null).apply(library).entryById(mummy.id)!.rating,
      isNull,
    );
  });

  test('AddEntry appends and keeps the id unique', () {
    final library = sampleLibrary();
    final added = AddEntry(mummy.copyWith(title: 'The Mummy (again)'))
        .apply(library);
    expect(added.entries.length, 3);
    expect(added.entries.last.id, 'movies/the-mummy-1999-2');
    expect(added.entries.last.title, 'The Mummy (again)');

    final fresh = AddEntry(
      mummy.copyWith(id: 'movies/the-mummy-2017', type: MediaType.movies),
    ).apply(library);
    expect(fresh.entries.last.id, 'movies/the-mummy-2017');
  });

  test('UpdateEntry keeps id and position and prunes tags', () {
    final library = sampleLibrary();
    final updated = UpdateEntry(
      mummy.copyWith(title: 'The Mummy (1999)', tags: ['adventure']),
    ).apply(library);
    expect(updated.entries.first.id, mummy.id);
    expect(updated.entries.first.title, 'The Mummy (1999)');
    expect(updated.entries.map((e) => e.id), library.entries.map((e) => e.id));
    expect(updated.tags[TagCategory.mood], isNull);
    expect(updated.tags[TagCategory.genre], ['adventure', 'grunge']);
    expect(updated.tags[TagCategory.season], ['halloween', 'christmas']);
  });

  test('DeleteEntry removes the entry, its plan items and unused tags', () {
    final result = DeleteEntry(mummy.id).apply(sampleLibrary());
    expect(result.entries.map((e) => e.id), [dirt.id]);
    expect(result.plans.first.items, isEmpty);
    expect(result.tags[TagCategory.genre], ['grunge']);
    expect(result.tags[TagCategory.season], ['halloween', 'christmas']);
  });

  group('tracks', () {
    test('RateTrack adds a track, matching by id or title', () {
      final library = sampleLibrary();
      final added = RateTrack(
        dirt.id,
        const Track(title: 'Them Bones', id: 'mb:2', rating: 9),
      ).apply(library);
      expect(added.entryById(dirt.id)!.tracks!.map((t) => t.title), [
        'Rooster',
        'Them Bones',
      ]);

      final byId = RateTrack(
        dirt.id,
        const Track(title: 'Rooster (remaster)', id: 'mb:1', rating: 8),
      ).apply(library);
      expect(byId.entryById(dirt.id)!.tracks!.single.rating, 8);

      final byTitle = RateTrack(
        dirt.id,
        const Track(title: 'Rooster', rating: 7),
      ).apply(library);
      expect(byTitle.entryById(dirt.id)!.tracks!.single.rating, 7);
    });

    test('RateTrack on an album without tracks creates the list', () {
      final library = sampleLibrary();
      final bare = UpdateEntry(dirt.copyWith(tracks: null)).apply(library);
      final rated = RateTrack(
        dirt.id,
        const Track(title: 'Rain When I Die', rating: 9),
      ).apply(bare);
      expect(rated.entryById(dirt.id)!.tracks!.length, 1);
    });

    test('ClearTrackRating removes the track and drops an empty list', () {
      final library = sampleLibrary();
      final cleared = ClearTrackRating(dirt.id, trackId: 'mb:1').apply(library);
      expect(cleared.entryById(dirt.id)!.tracks, isNull);

      final two = RateTrack(
        dirt.id,
        const Track(title: 'Them Bones', rating: 9),
      ).apply(library);
      final one = ClearTrackRating(dirt.id, title: 'Them Bones').apply(two);
      expect(one.entryById(dirt.id)!.tracks!.single.title, 'Rooster');
    });
  });
  test('entry operations summarize themselves', () {
    final library = sampleLibrary();
    expect(
      SetStatus(mummy.id, EntryStatus.done).summary(library),
      'Mark The Mummy as done',
    );
    expect(
      SetStatus(mummy.id, EntryStatus.dnf).summary(library),
      'Mark The Mummy as DNF',
    );
    expect(SetRating(mummy.id, 8).summary(library), 'Rate The Mummy 8 of 10');
    expect(
      SetRating(mummy.id, null).summary(library),
      'Clear the rating of The Mummy',
    );
    expect(AddEntry(mummy).summary(library), 'Add The Mummy');
    expect(UpdateEntry(mummy).summary(library), 'Edit The Mummy');
    expect(DeleteEntry(dirt.id).summary(library), 'Delete Dirt');
    expect(
      RateTrack(
        dirt.id,
        const Track(title: 'Rooster', rating: 9),
      ).summary(library),
      'Rate Rooster on Dirt 9 of 10',
    );
    expect(
      ClearTrackRating(dirt.id, trackId: 'mb:1').summary(library),
      'Clear the rating of Rooster on Dirt',
    );
  });

  group('SetKind', () {
    final frieren = mummy.copyWith(
      id: 'anime/frieren-2023',
      type: MediaType.anime,
      title: 'Frieren',
      status: EntryStatus.done,
    );
    Library lib() => sampleLibrary().copyWith(entries: [mummy, dirt, frieren]);

    test('marks an anime a series or a movie, nothing else changing', () {
      final series = SetKind(frieren.id, EntryKind.series).apply(lib());
      final after = series.entryById(frieren.id)!;
      expect(after.kind, EntryKind.series);
      expect(after.released, frieren.released);
      expect(after.status, EntryStatus.done);
      expect(
        SetKind(
          frieren.id,
          EntryKind.movie,
        ).apply(lib()).entryById(frieren.id)!.kind,
        EntryKind.movie,
      );
      expect(
        SetKind(frieren.id, EntryKind.series).summary(lib()),
        'Mark Frieren as a series',
      );
      expect(
        SetKind(frieren.id, EntryKind.movie).summary(lib()),
        'Mark Frieren as a movie',
      );
    });

    test('refuses a kind the type cannot have; a missing entry is left', () {
      expect(
        () => SetKind(frieren.id, EntryKind.album).apply(lib()),
        throwsArgumentError,
      );
      expect(
        () => SetKind(mummy.id, EntryKind.movie).apply(lib()),
        throwsArgumentError,
      );
      expect(
        () => SetKind(dirt.id, EntryKind.series).apply(lib()),
        throwsArgumentError,
      );
      expect(
        SetKind(dirt.id, EntryKind.song).apply(lib()).entryById(dirt.id)!.kind,
        EntryKind.song,
      );
      expect(const SetKind('nope', EntryKind.movie).apply(lib()), lib());
    });
  });

  test('SetStatus on an anime series goes through its seasons', () {
    final series = mummy.copyWith(
      id: 'anime/frieren-2023',
      type: MediaType.anime,
      title: 'Frieren',
      released: null,
      kind: EntryKind.series,
      status: EntryStatus.want,
      seasons: const [
        Season(season: 1, released: Released(2023), status: EntryStatus.want),
        Season(season: 2, released: Released(2099)),
      ],
    );
    final lib = sampleLibrary().copyWith(entries: [series]);
    final after = SetStatus(
      series.id,
      EntryStatus.done,
    ).apply(lib).entries.single;
    expect(after.seasons!.first.status, EntryStatus.done);
    expect(after.seasons!.last.status, isNull);
    expect(after.status, EntryStatus.done);
  });

  group('SetSeriesCover', () {
    final one = mummy.copyWith(
      id: 'movies/kfp1',
      title: 'Kung Fu Panda',
      series: const Series(name: 'Kung Fu Panda', number: 1),
    );
    final two = mummy.copyWith(
      id: 'movies/kfp2',
      title: 'Kung Fu Panda 2',
      series: const Series(name: 'Kung Fu Panda', number: 2, cover: true),
    );
    final three = mummy.copyWith(
      id: 'movies/kfp3',
      title: 'Kung Fu Panda 3',
      series: const Series(name: 'kung fu panda', number: 3),
    );
    final book = mummy.copyWith(
      id: 'books/kfp',
      type: MediaType.books,
      title: 'Kung Fu Panda: The Novel',
      series: const Series(name: 'Kung Fu Panda', number: 1, cover: true),
    );
    final library = sampleLibrary().copyWith(
      entries: [mummy, one, two, three, book],
    );

    test('marks the part and clears the rest of its series, same type', () {
      final result = const SetSeriesCover('movies/kfp3').apply(library);
      expect(result.entryById('movies/kfp1')!.series!.cover, isNull);
      expect(result.entryById('movies/kfp2')!.series!.cover, isNull);
      expect(result.entryById('movies/kfp3')!.series!.cover, isTrue);
      // A book series of the same name is another series.
      expect(result.entryById('books/kfp')!.series!.cover, isTrue);
      expect(result.entries.map((e) => e.id), library.entries.map((e) => e.id));
    });

    test('part 1 picked: no part is marked, so part 1 stands in', () {
      final result = const SetSeriesCover('movies/kfp1').apply(library);
      expect(result.entryById('movies/kfp1')!.series!.cover, isTrue);
      expect(result.entryById('movies/kfp2')!.series!.cover, isNull);
    });

    test('an entry in no series, or missing, changes nothing', () {
      expect(SetSeriesCover(mummy.id).apply(library), library);
      expect(const SetSeriesCover('nope').apply(library), library);
    });

    test('summarizes itself', () {
      expect(
        const SetSeriesCover('movies/kfp2').summary(library),
        'Use Kung Fu Panda 2 as the cover of its series',
      );
    });
  });

  group('SetReleased', () {
    test('sets the date; a show or an anime series keeps none', () {
      final library = sampleLibrary();
      final result = SetReleased(
        mummy.id,
        const Released(2027, 5, 26),
      ).apply(library);
      expect(result.entryById(mummy.id)!.released, const Released(2027, 5, 26));
      expect(result.entries.map((e) => e.id), [mummy.id, dirt.id]);
      expect(const SetReleased('nope', Released(2027)).apply(library), library);
      final show = mummy.copyWith(
        id: 'shows/show',
        type: MediaType.shows,
        released: null,
        seasons: const [Season(season: 1, released: Released(2027))],
      );
      final withShow = library.copyWith(entries: [...library.entries, show]);
      expect(
        SetReleased(show.id, const Released(2028)).apply(withShow),
        withShow,
      );
      expect(
        SetReleased(mummy.id, const Released(2027)).summary(library),
        'Update the release date of The Mummy',
      );
    });
  });
}
