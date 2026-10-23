import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/models/entry_status.dart';
import 'package:library_app/data/models/plan.dart';
import 'package:library_app/data/models/plan_item.dart';
import 'package:library_app/data/models/tag_category.dart';
import 'package:library_app/data/models/track.dart';
import 'package:library_app/data/operations/operations.dart';

import '../../helpers/sample_library.dart';

import 'package:library_app/data/models/entry_kind.dart';

void main() {
  final all = <LibraryOperation>[
    SetStatus(mummy.id, EntryStatus.want),
    SetRating(mummy.id, 7),
    SetRating(mummy.id, null),
    SetKind(dirt.id, EntryKind.song),
    SetSeriesCover(mummy.id),
    AddEntry(dirt.copyWith(id: 'music/new-dirt-alice-in-chains')),
    UpdateEntry(mummy.copyWith(note: 'Rewatch with the kids')),
    DeleteEntry(dirt.id),
    RateTrack(dirt.id, const Track(title: 'Them Bones', id: 'mb:2', rating: 9)),
    ClearTrackRating(dirt.id, trackId: 'mb:1'),
    ClearTrackRating(dirt.id, title: 'Rooster'),
    AddPlan(const Plan(id: 'summer-2027', name: 'Summer', year: 2027)),
    UpdatePlan(halloweenPlan.copyWith(started: true)),
    const DeletePlan('christmas-2026'),
    SetPlanItem(
      halloweenPlan.id,
      PlanItem(entry: dirt.id, done: true, note: 'Loud'),
    ),
    RemovePlanItem(halloweenPlan.id, mummy.id),
    SetPlanStarted(halloweenPlan.id, true),
    const AddTag('grunge', [TagCategory.musicGenre]),
    const SetTagCategories('grunge', [
      TagCategory.genre,
      TagCategory.musicGenre,
    ]),
  ];

  test('every operation survives a JSON round trip', () {
    final library = sampleLibrary();
    for (final operation in all) {
      // Through text, as pending.json stores it.
      final text = jsonEncode(encodeOperation(operation));
      final decoded = decodeOperation(jsonDecode(text) as Map<String, Object?>);
      expect(decoded.runtimeType, operation.runtimeType, reason: text);
      expect(
        jsonEncode(encodeOperation(decoded)),
        text,
        reason: 'encoding is stable',
      );
      expect(
        decoded.apply(library),
        operation.apply(library),
        reason: 'applies the same: $text',
      );
      expect(decoded.summary(library), operation.summary(library));
    }
  });

  test('uses the models\' JSON values for enums', () {
    expect(
      encodeOperation(const SetStatus('x', EntryStatus.inProgress))['status'],
      'in_progress',
    );
    expect(
      encodeOperation(
        const AddTag('rpg', [TagCategory.gameGenre]),
      )['categories'],
      ['Game genres'],
    );
    // A queue written before tags could be in several categories.
    final old = decodeOperation({
      'op': 'addTag',
      'name': 'rpg',
      'category': 'Game genres',
    });
    expect((old as AddTag).categories, [TagCategory.gameGenre]);
  });

  test('an unknown op is a FormatException', () {
    expect(
      () => decodeOperation({'op': 'teleport'}),
      throwsA(isA<FormatException>()),
    );
  });
}
