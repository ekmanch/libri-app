import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/operations/operations.dart';

void main() {
  const defaults = AppSettings.defaults;

  test('each operation changes its setting and says so', () {
    expect(
      const SetTimelineDefault(true).apply(defaults).timelineDefault,
      isTrue,
    );
    expect(
      const SetTimelineDefault(true).summary(defaults),
      'Turn on the timeline for new plans',
    );
    expect(
      const SetSeasonalThemeDefault(false).apply(defaults).seasonalThemeDefault,
      isFalse,
    );
    expect(
      const SetSeasonalThemeDefault(false).summary(defaults),
      'Turn off seasonal touches for new plans',
    );
    expect(
      const SetDefaultPlatform('Steam Deck').apply(defaults).defaultPlatform,
      'Steam Deck',
    );
    expect(
      const SetDefaultPlatform('Steam Deck').summary(defaults),
      'Set default platform to Steam Deck',
    );
    expect(
      const SetDefaultPlatform(null).apply(defaults).defaultPlatform,
      isNull,
    );
    expect(
      const SetDefaultPlatform(null).summary(defaults),
      'Clear the default platform',
    );
    expect(
      const SetUpcomingEnabled(false).apply(defaults).upcomingEnabled,
      isFalse,
    );
    expect(
      const SetUpcomingEnabled(false).summary(defaults),
      'Turn off the checks for new releases',
    );
  });

  test('follows are stored as the exception to their default', () {
    const unfollow = SetFollow(
      FollowKind.authors,
      'j-k-rowling',
      name: 'J. K. Rowling',
      on: false,
      defaultOn: true,
    );
    final settings = unfollow.apply(defaults);
    expect(settings.unfollowedOf(FollowKind.authors), {'j-k-rowling'});
    expect(unfollow.summary(defaults), 'Unfollow J. K. Rowling');

    const follow = SetFollow(
      FollowKind.actors,
      'pedro-pascal',
      name: 'Pedro Pascal',
      on: true,
      defaultOn: false,
    );
    expect(follow.apply(settings).followedOf(FollowKind.actors), {
      'pedro-pascal',
    });
    expect(follow.summary(defaults), 'Follow Pedro Pascal');

    // Follow all on the actors: every active actor ticked.
    const all = SetFollows(FollowKind.actors, {
      'pedro-pascal': false,
      'jenna-ortega': false,
      'alec-guinness': false,
    }, on: true);
    expect(all.apply(defaults).followedOf(FollowKind.actors), {
      'pedro-pascal',
      'jenna-ortega',
      'alec-guinness',
    });
    expect(all.summary(defaults), 'Follow all actors');
    // Unfollow all on the authors: the default-on ones go to unfollowed, a
    // ticked inactive one just loses its tick.
    final authors = const SetFollow(
      FollowKind.authors,
      'j-r-r-tolkien',
      name: 'J. R. R. Tolkien',
      on: true,
      defaultOn: false,
    ).apply(defaults);
    final none = const SetFollows(FollowKind.authors, {
      'stephen-king': true,
      'j-r-r-tolkien': false,
    }, on: false).apply(authors);
    expect(none.unfollowedOf(FollowKind.authors), {'stephen-king'});
    expect(none.followedOf(FollowKind.authors), isEmpty);
  });

  test('not interested adds and removes a key', () {
    const hide = SetNotInterested(
      'movies/dune-part-three-2026',
      title: 'Dune: Part Three',
    );
    final hidden = hide.apply(defaults);
    expect(hidden.notInterested, {'movies/dune-part-three-2026'});
    expect(hide.summary(defaults), 'Hide Dune: Part Three from upcoming');
    const show = SetNotInterested(
      'movies/dune-part-three-2026',
      title: 'Dune: Part Three',
      hidden: false,
    );
    expect(show.apply(hidden), defaults);
    expect(show.summary(hidden), 'Show Dune: Part Three in upcoming');
  });

  test('every operation survives the queue\'s JSON form', () {
    const operations = <SettingsOperation>[
      SetTimelineDefault(true),
      SetSeasonalThemeDefault(false),
      SetDefaultPlatform('PC'),
      SetDefaultPlatform(null),
      SetUpcomingEnabled(false),
      SetFollow(
        FollowKind.studios,
        'pixar',
        name: 'Pixar',
        on: false,
        defaultOn: true,
      ),
      SetFollows(FollowKind.actors, {'a': false, 'b': true}, on: true),
      SetNotInterested('tmdb:movie:1', title: 'The Hunt for Gollum'),
      SetNotInterested('shows/x#2', title: 'X, Season 2', hidden: false),
    ];
    const start = AppSettings(
      followed: {
        FollowKind.actors: {'a'},
      },
      notInterested: {'shows/x#2'},
    );
    for (final operation in operations) {
      final json = encodeOperation(operation);
      expect(json['op'], startsWith('settings.'));
      final decoded = decodeOperation(json) as SettingsOperation;
      expect(decoded.runtimeType, operation.runtimeType);
      expect(decoded.apply(start), operation.apply(start), reason: '$json');
      expect(decoded.summary(start), operation.summary(start));
      expect(encodeOperation(decoded), json);
    }
  });

  test('a commit message for several operations', () {
    SettingsOperation unfollow(String id, String name) => SetFollow(
      FollowKind.authors,
      id,
      name: name,
      on: false,
      defaultOn: true,
    );
    List<({SettingsOperation operation, String summary})> queued(
      List<SettingsOperation> ops,
    ) => [for (final o in ops) (operation: o, summary: o.summary(defaults))];

    expect(
      settingsMessage(queued([unfollow('a', 'Ann Author')])),
      'Unfollow Ann Author',
    );
    expect(
      settingsMessage(
        queued([
          unfollow('a', 'Ann Author'),
          unfollow('b', 'Bob Books'),
          unfollow('c', 'Cy Codex'),
        ]),
      ),
      'Unfollow 3 authors\n\n'
      '- Unfollow Ann Author\n- Unfollow Bob Books\n- Unfollow Cy Codex',
    );
    expect(
      settingsMessage(
        queued([
          const SetFollow(
            FollowKind.shows,
            'shows/a',
            name: 'A',
            on: true,
            defaultOn: false,
          ),
          const SetFollow(
            FollowKind.shows,
            'shows/b',
            name: 'B',
            on: true,
            defaultOn: false,
          ),
        ]),
      ),
      startsWith('Follow 2 shows\n'),
    );
    expect(
      settingsMessage(
        queued([unfollow('a', 'Ann Author'), const SetDefaultPlatform('PC')]),
      ),
      'Unfollow Ann Author and 1 other change\n\n'
      '- Unfollow Ann Author\n- Set default platform to PC',
    );
  });
}
