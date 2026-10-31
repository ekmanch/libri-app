import 'package:flutter/foundation.dart';

import '../models/release_dates.dart';
import '../models/released.dart';
import '../storage/json_file.dart';

/// A movie's release dates by kind, as the lookup has them (TMDB's
/// `/movie/{id}/release_dates`; DESIGN.md 10c): the earliest theatrical
/// date anywhere and the earliest digital date anywhere, either of which
/// may be unknown. Kept on the device in `movie_dates.json` by lookup id,
/// never in `library.json`, whose `released` holds the [first] of them.
/// Settings › Movies › Release dates picks which one Coming soon and the
/// details show ([shownRelease]).
@immutable
class MovieDates {
  const MovieDates({this.cinema, this.digital});

  final Released? cinema;
  final Released? digital;

  /// The earlier of the two; null when neither is known.
  Released? get first {
    final a = cinema, b = digital;
    if (a == null || b == null) return a ?? b;
    return b.availableFrom.isBefore(a.availableFrom) ? b : a;
  }

  bool get isEmpty => cinema == null && digital == null;

  factory MovieDates.fromJson(Map<String, Object?> json) => MovieDates(
    cinema: _date(json['cinema']),
    digital: _date(json['digital']),
  );

  static Released? _date(Object? value) =>
      value is String ? Released.tryParse(value) : null;

  Map<String, Object?> toJson() => {
    if (cinema != null) 'cinema': cinema.toString(),
    if (digital != null) 'digital': digital.toString(),
  };

  @override
  bool operator ==(Object other) =>
      other is MovieDates && other.cinema == cinema && other.digital == digital;

  @override
  int get hashCode => Object.hash(cinema, digital);

  @override
  String toString() => 'MovieDates(cinema: $cinema, digital: $digital)';
}

/// The date Coming soon and the details show for a title whose `released`
/// is [released] (the first release date anywhere), given the movie's
/// [dates] on the device and the Release dates [setting]: Cinema shows the
/// cinema date, Digital the digital date, Both the first; a date the
/// setting asks for that is not known falls back to [released]. Anything
/// that is not a movie has no [dates] and shows [released].
Released? shownRelease(
  Released? released,
  MovieDates? dates,
  ReleaseDates setting,
) => switch (setting) {
  ReleaseDates.cinema => dates?.cinema ?? released,
  ReleaseDates.digital => dates?.digital ?? released,
  ReleaseDates.both => released,
};

/// A book's release among the editions in the languages the owner reads
/// (Settings › Books › Languages you read; DESIGN.md 10c): whether any
/// edition is in them (an edition the source gives no language for counts,
/// and a work whose editions have no languages at all is in them), and the
/// earliest date of those editions, null when none of them is dated.
typedef EditionRelease = ({bool inLanguages, Released? released});

/// Where the movie dates are kept, by lookup id ("tmdb:movie:1234").
abstract class MovieDateStore {
  Future<Map<String, MovieDates>> read();

  Future<void> write(Map<String, MovieDates> dates);
}

/// `movie_dates.json` under the cache folder: `{"dates": {"tmdb:movie:1":
/// {"cinema": "2026-12-18", "digital": "2027-02"}}}`. A cleared cache means
/// no dates until the next check.
class FileMovieDateStore implements MovieDateStore {
  FileMovieDateStore(this._file);

  final JsonFile _file;

  @override
  Future<Map<String, MovieDates>> read() async {
    final dates = (await _file.read())?['dates'];
    if (dates is! Map<String, Object?>) return const {};
    return {
      for (final MapEntry(:key, :value) in dates.entries)
        if (value is Map<String, Object?>) key: MovieDates.fromJson(value),
    };
  }

  @override
  Future<void> write(Map<String, MovieDates> dates) => _file.write({
    'dates': {for (final e in dates.entries) e.key: e.value.toJson()},
  });
}

class MemoryMovieDateStore implements MovieDateStore {
  MemoryMovieDateStore([Map<String, MovieDates>? dates])
    : _dates = dates ?? const {};

  Map<String, MovieDates> _dates;

  @override
  Future<Map<String, MovieDates>> read() async => _dates;

  @override
  Future<void> write(Map<String, MovieDates> dates) async => _dates = dates;
}
