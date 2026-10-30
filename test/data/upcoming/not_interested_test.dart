import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/lookup/lookup_match.dart';
import 'package:library_app/data/lookup/series_check.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/data/operations/operations.dart';
import 'package:library_app/data/upcoming/creator_lookup.dart';
import 'package:library_app/data/upcoming/not_interested.dart';

void main() {
  final today = DateTime(2026, 10, 30);

  Entry entry(
    String id, {
    Released? released,
    String? source,
    List<Season>? seasons,
  }) => Entry(
    id: id,
    type: MediaType.movies,
    title: id,
    status: EntryStatus.want,
    released: released,
    added: DateTime(2026, 1, 1),
    source: source,
    seasons: seasons,
  );

  final library = Library(
    entries: [
      entry('movies/ahead', released: const Released(2027, 3, 5)),
      entry('movies/out', released: const Released(2026, 10, 1)),
      entry('movies/added', source: 'deezer:album:9'),
      entry(
        'shows/x',
        seasons: const [
          Season(season: 1, released: Released(2020), status: EntryStatus.done),
          Season(season: 2, released: Released(2026, 10, 20)),
          Season(season: 3, released: Released(2027, 2)),
        ],
      ),
    ],
  );

  FoundRelease release(String source, Released released) => FoundRelease(
    kind: FollowKind.artists,
    creatorId: 'a',
    creatorName: 'A',
    match: LookupMatch(
      type: MediaType.music,
      title: source,
      source: source,
      released: released,
    ),
    foundOn: today,
  );

  test('keys whose rows are out or gone are stale; the rest stay', () {
    const settings = AppSettings(
      notInterested: {
        'movies/ahead', // still ahead
        'movies/out', // released
        'movies/gone', // no such entry
        'shows/x#2', // season out
        'shows/x#3', // season ahead
        'shows/x#9', // no such season
        'deezer:album:9', // in the library now
        'deezer:album:1', // recorded, ahead
        'deezer:album:2', // recorded, long out
        'deezer:album:3', // not recorded: an unfollowed creator's, kept
        'tmdb:movie:5', // a recorded part, out
      },
    );
    final stale = staleNotInterested(
      settings,
      library,
      parts: const [
        UpcomingPart(
          type: MediaType.movies,
          seriesName: 'S',
          entryId: 'movies/ahead',
          title: 'Part',
          released: Released(2026, 9, 1),
          source: 'tmdb:movie:5',
        ),
      ],
      releases: [
        release('deezer:album:1', const Released(2026, 12, 1)),
        release('deezer:album:2', const Released(2026, 8, 1)),
      ],
      today: today,
    );
    expect(stale.toSet(), {
      'movies/out',
      'movies/gone',
      'shows/x#2',
      'shows/x#9',
      'deezer:album:9',
      'deezer:album:2',
      'tmdb:movie:5',
    });
    final after = ForgetNotInterested(stale).apply(settings);
    expect(after.notInterested, {
      'movies/ahead',
      'shows/x#3',
      'deezer:album:1',
      'deezer:album:3',
    });
    expect(
      ForgetNotInterested(stale).summary(settings),
      'Forget 7 hidden upcoming rows that came out',
    );
    expect(
      const ForgetNotInterested(['movies/out']).summary(settings),
      'Forget 1 hidden upcoming row that came out',
    );
    final json = encodeOperation(ForgetNotInterested(stale));
    expect(json['op'], 'settings.forgetNotInterested');
    expect((decodeOperation(json) as SettingsOperation).apply(settings), after);
  });
}
