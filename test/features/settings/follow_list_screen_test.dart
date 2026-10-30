import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/follow_kind.dart';
import 'package:library_app/data/upcoming/creator_status.dart';
import 'package:library_app/data/upcoming/follows.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/settings/follow_list_screen.dart';
import 'package:library_app/widgets/check_box_mark.dart';

import '../../helpers/pump_app.dart';

void main() {
  /// The fixture's artists, with the fake's dead ones recorded as such.
  final gone = <String, CreatorStatus>{
    for (final (name, year) in [
      ('miles davis', 1991),
      ('2pac', 1996),
      ("screamin' jay hawkins", 2000),
    ])
      'artists/$name': CreatorStatus(
        kind: FollowKind.artists,
        id: name,
        providerId: 'fake:creator:$name',
        inactive: Inactive(InactiveReason.died, year: year),
        checkedOn: DateTime(2026, 10, 30),
      ),
    'artists/creedence clearwater revival': CreatorStatus(
      kind: FollowKind.artists,
      id: 'creedence clearwater revival',
      providerId: 'fake:creator:ccr',
      inactive: const Inactive(InactiveReason.disbanded, year: 1972),
      checkedOn: DateTime(2026, 10, 30),
    ),
  };
  final statuses = MemoryCreatorStatusStore(gone);

  /// The fixture's follows as the screen derives them.
  final fixture = deriveFollows(
    loadFixture(),
    AppSettings.defaults,
    statuses: gone,
  );
  final artists = fixture.of(FollowKind.artists).length;
  final active = artists - gone.length;

  Future<Future<AppSettings> Function()> pump(
    WidgetTester tester, {
    FollowKind kind = FollowKind.artists,
  }) async {
    final container = await pumpApp(
      tester,
      FollowListScreen(kind: kind),
      lookupOverrides: fakeLookupOverrides(creatorStatuses: statuses),
    );
    return () => container.read(libraryRepositoryProvider).loadSettings();
  }

  /// The list, not the search field's own scrollable.
  final list = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );

  bool checked(WidgetTester tester, String id) {
    final row = find.byKey(ValueKey('follow-$id'));
    return tester
        .widget<CheckBoxMark>(
          find.descendant(of: row, matching: find.byType(CheckBoxMark)),
        )
        .checked;
  }

  testWidgets('lists the followed and the no longer active, with counts', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Artists'), findsOneWidget);
    expect(gone.length, 4, reason: 'four of the fixture\'s artists are gone');
    expect(find.text('$active of $artists followed'), findsOneWidget);
    expect(find.text('Unfollow all'), findsOneWidget);
    expect(find.text('FOLLOWED FOR NEW ALBUMS'), findsOneWidget);
    expect(find.text('Alice in Chains'), findsOneWidget);
    expect(checked(tester, 'alice in chains'), isTrue);
    await tester.scrollUntilVisible(
      find.text(FollowListScreen.inactiveHelp),
      200,
      scrollable: list,
    );
    expect(find.text('NO LONGER ACTIVE'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Miles Davis'),
      200,
      scrollable: list,
    );
    expect(find.text('Died 1991 · Not checked'), findsOneWidget);
    expect(checked(tester, 'miles davis'), isFalse);
    await tester.scrollUntilVisible(
      find.text('Creedence Clearwater Revival'),
      200,
      scrollable: list,
    );
    expect(find.text('Disbanded 1972 · Not checked'), findsOneWidget);
  });

  testWidgets(
    'a tap toggles the follow and the counts; a dead one can be ticked',
    (tester) async {
      final settings = await pump(tester);
      await tester.tap(find.text('Alice in Chains'));
      await tester.pumpAndSettle();
      expect(checked(tester, 'alice in chains'), isFalse);
      expect(find.text('${active - 1} of $artists followed'), findsOneWidget);
      expect((await settings()).unfollowedOf(FollowKind.artists), {
        'alice in chains',
      });

      await tester.scrollUntilVisible(
        find.text('Miles Davis'),
        200,
        scrollable: list,
      );
      await tester.tap(find.text('Miles Davis'));
      await tester.pumpAndSettle();
      expect(checked(tester, 'miles davis'), isTrue);
      expect(find.text('$active of $artists followed'), findsOneWidget);
      expect((await settings()).followedOf(FollowKind.artists), {
        'miles davis',
      });
    },
  );

  testWidgets('Unfollow all and Follow all act on the active ones only', (
    tester,
  ) async {
    final settings = await pump(tester);
    await tester.tap(find.text('Unfollow all'));
    await tester.pumpAndSettle();
    expect(find.text('0 of $artists followed'), findsOneWidget);
    expect(find.text('Follow all'), findsOneWidget);
    expect(
      (await settings()).unfollowedOf(FollowKind.artists),
      hasLength(active),
    );
    expect((await settings()).followedOf(FollowKind.artists), isEmpty);
    await tester.tap(find.text('Follow all'));
    await tester.pumpAndSettle();
    expect(find.text('$active of $artists followed'), findsOneWidget);
    expect((await settings()).unfollowedOf(FollowKind.artists), isEmpty);
  });

  testWidgets('actors are off until ticked; the search narrows by name', (
    tester,
  ) async {
    final settings = await pump(tester, kind: FollowKind.actors);
    expect(find.text('0 of 3 followed'), findsOneWidget);
    expect(find.text('Follow all'), findsOneWidget);
    expect(find.text('FOLLOWED FOR NEW MOVIES AND SHOWS'), findsOneWidget);
    expect(checked(tester, 'clint-eastwood'), isFalse);
    expect(find.text('2 movies'), findsOneWidget);
    await tester.tap(find.text('Hilary Swank'));
    await tester.pumpAndSettle();
    expect(checked(tester, 'hilary-swank'), isTrue);
    expect((await settings()).followedOf(FollowKind.actors), {'hilary-swank'});

    await tester.enterText(find.byType(TextField), 'free');
    await tester.pumpAndSettle();
    expect(find.text('Morgan Freeman'), findsOneWidget);
    expect(find.text('Clint Eastwood'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No actors match "zzz".'), findsOneWidget);
  });

  testWidgets('a kind with nothing to follow says why', (tester) async {
    await pump(tester, kind: FollowKind.authors);
    expect(find.text('0 of 0 followed'), findsOneWidget);
    expect(find.textContaining('No authors tagged yet'), findsOneWidget);
    expect(find.text('Follow all'), findsNothing);
  });
}
