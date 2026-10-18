import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/models/released.dart';
import 'package:library_app/data/models/season.dart';
import 'package:library_app/features/entry/dropped_season_dialog.dart';

import '../../helpers/pump.dart';

void main() {
  final carrie = Entry(
    id: 'shows/carrie-2026',
    type: MediaType.shows,
    title: 'Carrie',
    status: EntryStatus.done,
    added: DateTime(2026),
    seasons: const [
      Season(season: 1, released: Released(2026), status: EntryStatus.done),
      Season(season: 2, released: Released(2027), status: EntryStatus.want),
    ],
  );

  Future<DroppedSeasonChoice?> open(WidgetTester tester, String tap) async {
    DroppedSeasonChoice? choice;
    await pumpThemed(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => choice = await showDroppedSeasonDialog(
            context,
            show: carrie,
            season: 2,
            status: EntryStatus.want,
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Season 2 of Carrie is no longer listed'), findsOneWidget);
    expect(
      find.text(
        'TMDB has dropped it, so it was probably canceled. '
        'You had it as Want.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Season 1 and the show stay as they are.'),
      findsOneWidget,
    );
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    return choice;
  }

  testWidgets('Keep it keeps the season', (tester) async {
    expect(await open(tester, 'Keep it'), DroppedSeasonChoice.keep);
  });

  testWidgets('Remove removes it', (tester) async {
    expect(await open(tester, 'Remove'), DroppedSeasonChoice.remove);
  });

  test('the note names the one other season, or the others', () {
    final three = carrie.copyWith(
      seasons: [...carrie.seasons!, const Season(season: 3)],
    );
    expect(
      droppedSeasonNote(three, 3),
      'The other seasons and the show stay as they are.',
    );
  });
}
