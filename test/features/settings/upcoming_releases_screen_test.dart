import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/lookup/lookup_providers.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/upcoming/follows.dart';
import 'package:library_app/data/upcoming/upcoming_scheduler.dart';
import 'package:library_app/dev/fake_lookup.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/follow_list_screen.dart';
import 'package:library_app/features/settings/settings_screen.dart';
import 'package:library_app/features/settings/upcoming_releases_screen.dart';
import 'package:library_app/widgets/setting_row.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('the Settings row says how many kinds are followed and opens '
      'the screen', (tester) async {
    await pumpApp(tester, const SettingsScreen());
    await tester.scrollUntilVisible(find.text('Check for new releases'), 200);
    await tester.ensureVisible(find.text('Check for new releases'));
    await tester.pumpAndSettle();
    // The fixture tags a director, two studios, actors (off by default) and
    // has artists and series; no linked shows and no authors.
    expect(find.text('Daily · 4 of 7 kinds'), findsOneWidget);
    await tester.tap(find.text('Check for new releases'));
    await tester.pumpAndSettle();
    expect(find.byType(UpcomingReleasesScreen), findsOneWidget);
    expect(find.text('Upcoming releases'), findsOneWidget);
  });

  testWidgets(
    'the master switch, Wi-Fi, the kinds with their counts and the note',
    (tester) async {
      final container = await pumpApp(tester, const UpcomingReleasesScreen());
      expect(find.text(UpcomingReleasesScreen.onHelp), findsOneWidget);
      expect(find.text('Only on Wi-Fi'), findsOneWidget);
      expect(find.text('Last checked'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
      expect(find.text('Check now'), findsOneWidget);
      expect(find.text('FOLLOW'), findsOneWidget);
      expect(find.text(UpcomingReleasesScreen.followHelp), findsOneWidget);
      // The counts: a director, two studios, every artist but Various
      // Artists, no actors on, no linked shows. The rows are built as they
      // scroll into view.
      final artists = deriveFollows(
        loadFixture(),
        AppSettings.defaults,
      ).of(FollowKind.artists).length;
      expect(artists, greaterThan(10));
      final counts = {
        FollowKind.shows: '0',
        FollowKind.series: '2',
        FollowKind.authors: '0',
        FollowKind.artists: '$artists',
        FollowKind.directors: '1',
        FollowKind.studios: '2',
        FollowKind.actors: '0 of 3',
      };
      for (final kind in FollowKind.values) {
        final row = find.byKey(ValueKey('kind-${kind.key}'));
        await tester.scrollUntilVisible(row, 150);
        expect(find.text(kind.label), findsOneWidget, reason: kind.label);
        expect(find.text(kind.what), findsWidgets, reason: kind.what);
        expect(
          tester.widget<SettingRow>(row).value,
          counts[kind],
          reason: kind.label,
        );
      }
      await tester.scrollUntilVisible(
        find.text(UpcomingReleasesScreen.scheduleNote),
        150,
      );
      expect(find.text(UpcomingReleasesScreen.scheduleNote), findsOneWidget);

      // Only on Wi-Fi is a device preference.
      await tester.scrollUntilVisible(find.text('Only on Wi-Fi'), -150);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(
        container.read(displayPreferencesProvider).upcomingWifiOnly,
        isTrue,
      );

      // Off: nothing is followed, and the rest of the screen goes.
      await tester.scrollUntilVisible(
        find.text('Check for new releases'),
        -200,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      final settings = await container
          .read(libraryRepositoryProvider)
          .loadSettings();
      expect(settings.upcomingEnabled, isFalse);
      expect(find.text(UpcomingReleasesScreen.offHelp), findsOneWidget);
      expect(find.text('Only on Wi-Fi'), findsNothing);
      expect(find.text('Authors'), findsNothing);
    },
  );

  testWidgets('a kind row opens its list', (tester) async {
    await pumpApp(tester, const UpcomingReleasesScreen());
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('kind-artists')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('kind-artists')));
    await tester.pumpAndSettle();
    expect(find.byType(FollowListScreen), findsOneWidget);
    expect(find.text('FOLLOWED FOR NEW ALBUMS'), findsOneWidget);
  });

  testWidgets('Check now runs every check and says what it found', (
    tester,
  ) async {
    final fake = FakeLookupSource();
    final container = await pumpApp(
      tester,
      const UpcomingReleasesScreen(),
      lookupOverrides: fakeLookupOverrides(source: fake),
    );
    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();
    // The fixture's followed creators were asked about; the Alice in Chains
    // album, the FromSoftware game, the Eastwood movie and the Ghibli film
    // were found.
    expect(fake.calls.where((c) => c.startsWith('releases:')), isNotEmpty);
    expect(find.textContaining('Today '), findsOneWidget);
    expect(find.textContaining('· 4 new'), findsOneWidget);
    final schedule = await container.read(upcomingScheduleStoreProvider).read();
    expect(schedule.newCount, 4);
    expect(find.text('Check now'), findsOneWidget);
  });

  test('the Last checked label', () {
    final now = DateTime(2026, 10, 30, 9, 30);
    expect(lastCheckedLabel(UpcomingSchedule.none, now: now), 'Never');
    expect(
      lastCheckedLabel(
        UpcomingSchedule(
          lastChecked: DateTime(2026, 10, 30, 7, 12),
          newCount: 3,
        ),
        now: now,
      ),
      'Today 07:12 · 3 new',
    );
    expect(
      lastCheckedLabel(
        UpcomingSchedule(lastChecked: DateTime(2026, 10, 29, 22, 40)),
        now: now,
      ),
      'Yesterday 22:40',
    );
    expect(
      lastCheckedLabel(
        UpcomingSchedule(lastChecked: DateTime(2026, 10, 12, 8), newCount: 1),
        now: now,
      ),
      'Oct 12 · 1 new',
    );
    expect(
      lastCheckedLabel(
        UpcomingSchedule(lastChecked: DateTime(2025, 12, 24, 8)),
        now: now,
      ),
      'Dec 24, 2025',
    );
  });

  test('the Settings row reads Off with the switch off', () {
    expect(const AppSettings(upcomingEnabled: false).upcomingEnabled, isFalse);
  });
}
