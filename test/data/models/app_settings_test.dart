import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/models/release_dates.dart';
import 'package:library_app/data/settings_codec.dart';

void main() {
  test('the defaults write only the version', () {
    expect(AppSettings.defaults.toJson(), {'version': 1});
    expect(emptySettingsText, '{\n  "version": 1\n}\n');
  });

  test('only the keys that differ from the defaults are written, in order', () {
    const settings = AppSettings(
      timelineDefault: true,
      defaultPlatform: null,
      languages: ['sv', 'en'],
      releaseDates: ReleaseDates.digital,
      upcomingEnabled: false,
      unfollowed: {
        FollowKind.authors: {'stephen-king', 'dan-simmons'},
      },
      followed: {
        FollowKind.actors: {'pedro-pascal'},
      },
      notInterested: {'shows/stranger-things-2016#5', 'games/silksong'},
    );
    final json = settings.toJson();
    expect(json.keys.toList(), [
      'version',
      'timeline_default',
      'games',
      'books',
      'movies',
      'upcoming',
    ]);
    expect(json['timeline_default'], isTrue);
    expect(json.containsKey('seasonal_theme_default'), isFalse);
    // None differs from PC, so the key is written as null.
    expect(json['games'], {'default_platform': null});
    // The languages read, sorted; the release dates pick when not Both.
    expect(json['books'], {
      'languages': ['en', 'sv'],
    });
    expect(json['movies'], {'release_dates': 'digital'});
    expect(json['upcoming'], {
      'enabled': false,
      'unfollowed': {
        'authors': ['dan-simmons', 'stephen-king'],
      },
      'followed': {
        'actors': ['pedro-pascal'],
      },
      'not_interested': ['games/silksong', 'shows/stranger-things-2016#5'],
    });
    expect(
      AppSettings.fromJson(json),
      settings.copyWith(languages: const ['en', 'sv']),
    );
    expect(
      decodeSettings(encodeSettings(settings)),
      settings.copyWith(languages: const ['en', 'sv']),
    );
    expect(
      encodeSettings(decodeSettings(encodeSettings(settings))),
      encodeSettings(settings),
    );
  });

  test('missing and unknown keys mean the defaults', () {
    final settings = AppSettings.fromJson({
      'version': 1,
      'games': {},
      'upcoming': {
        'unfollowed': {
          'dragons': ['x'],
          'authors': [],
        },
      },
      'later': true,
    });
    expect(settings, AppSettings.defaults);
    expect(settings.defaultPlatform, 'PC');
    // No languages yet (the first run writes them), Both until picked.
    expect(settings.languages, isNull);
    expect(settings.releaseDates, ReleaseDates.both);
    expect(
      AppSettings.fromJson({
        'books': {'languages': []},
        'movies': {'release_dates': 'laserdisc'},
      }),
      const AppSettings(languages: []),
    );
  });

  test('a file of another version is refused, as is a non-object', () {
    expect(() => decodeSettings('{"version": 2}'), throwsFormatException);
    expect(() => decodeSettings('[]'), throwsFormatException);
    expect(decodeSettings('{}'), AppSettings.defaults);
  });

  group('follows', () {
    test('on by default unless unticked, off by default unless ticked', () {
      const settings = AppSettings(
        unfollowed: {
          FollowKind.authors: {'j-k-rowling'},
        },
        followed: {
          FollowKind.actors: {'jenna-ortega'},
          FollowKind.authors: {'j-r-r-tolkien'},
        },
      );
      bool followed(FollowKind kind, String id, {required bool defaultOn}) =>
          settings.isFollowed(kind, id, defaultOn: defaultOn);
      expect(
        followed(FollowKind.authors, 'stephen-king', defaultOn: true),
        isTrue,
      );
      expect(
        followed(FollowKind.authors, 'j-k-rowling', defaultOn: true),
        isFalse,
      );
      // An author who died is off by default; the owner ticked Tolkien anyway.
      expect(
        followed(FollowKind.authors, 'j-r-r-tolkien', defaultOn: false),
        isTrue,
      );
      expect(
        followed(FollowKind.authors, 'roald-dahl', defaultOn: false),
        isFalse,
      );
      expect(
        followed(FollowKind.actors, 'jenna-ortega', defaultOn: false),
        isTrue,
      );
      expect(
        followed(FollowKind.actors, 'willem-dafoe', defaultOn: false),
        isFalse,
      );
    });

    test('withFollow stores only the exception to the default', () {
      var settings = AppSettings.defaults;
      settings = settings.withFollow(
        FollowKind.authors,
        'j-k-rowling',
        on: false,
        defaultOn: true,
      );
      expect(settings.unfollowedOf(FollowKind.authors), {'j-k-rowling'});
      expect(settings.followedOf(FollowKind.authors), isEmpty);
      // Back to the default: the exception goes, and the empty kind with it.
      settings = settings.withFollow(
        FollowKind.authors,
        'j-k-rowling',
        on: true,
        defaultOn: true,
      );
      expect(settings, AppSettings.defaults);
      expect(settings.unfollowed, isEmpty);

      settings = settings.withFollow(
        FollowKind.actors,
        'pedro-pascal',
        on: true,
        defaultOn: false,
      );
      expect(settings.followedOf(FollowKind.actors), {'pedro-pascal'});
      // Ticking what is on by default removes it from unfollowed only.
      settings = settings
          .withFollow(
            FollowKind.actors,
            'pedro-pascal',
            on: true,
            defaultOn: true,
          )
          .withFollow(
            FollowKind.actors,
            'bill-paxton',
            on: false,
            defaultOn: true,
          );
      expect(settings.followedOf(FollowKind.actors), isEmpty);
      expect(settings.unfollowedOf(FollowKind.actors), {'bill-paxton'});
    });
  });

  test('equality ignores map order and empty sets', () {
    const a = AppSettings(
      unfollowed: {
        FollowKind.authors: {'x', 'y'},
        FollowKind.actors: {},
      },
    );
    const b = AppSettings(
      unfollowed: {
        FollowKind.authors: {'y', 'x'},
      },
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const AppSettings(timelineDefault: true)));
  });
}
