import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/movie_dates.dart';
import 'package:library_app/data/models/release_dates.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/storage/json_file.dart';

void main() {
  const cinema = Released(2026, 12, 18);
  const digital = Released(2027, 2);
  const both = MovieDates(cinema: cinema, digital: digital);

  test('the first date is the earlier of the two, or the one known', () {
    expect(both.first, cinema);
    expect(
      const MovieDates(cinema: Released(2027, 3), digital: digital).first,
      digital,
    );
    expect(const MovieDates(digital: digital).first, digital);
    expect(const MovieDates().first, isNull);
    expect(const MovieDates().isEmpty, isTrue);
  });

  test('the shown date follows the setting and falls back to released', () {
    const released = Released(2026, 12, 18);
    expect(shownRelease(released, both, ReleaseDates.cinema), cinema);
    expect(shownRelease(released, both, ReleaseDates.digital), digital);
    expect(shownRelease(released, both, ReleaseDates.both), released);
    expect(
      shownRelease(
        released,
        const MovieDates(cinema: cinema),
        ReleaseDates.digital,
      ),
      released,
    );
    expect(shownRelease(released, null, ReleaseDates.cinema), released);
    expect(shownRelease(null, both, ReleaseDates.digital), digital);
    expect(shownRelease(null, null, ReleaseDates.cinema), isNull);
  });

  test('JSON and the file store round-trip', () async {
    expect(both.toJson(), {'cinema': '2026-12-18', 'digital': '2027-02'});
    expect(MovieDates.fromJson(both.toJson()), both);
    expect(const MovieDates(cinema: cinema).toJson(), {'cinema': '2026-12-18'});
    expect(MovieDates.fromJson({'cinema': 'soon'}), const MovieDates());

    final dir = await Directory.systemTemp.createTemp('libri-dates-');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileMovieDateStore(
      JsonFile(File('${dir.path}/movie_dates.json')),
    );
    expect(await store.read(), isEmpty);
    await store.write({
      'tmdb:movie:1': both,
      'tmdb:movie:2': const MovieDates(),
    });
    expect(await store.read(), {
      'tmdb:movie:1': both,
      'tmdb:movie:2': const MovieDates(),
    });
  });
}
