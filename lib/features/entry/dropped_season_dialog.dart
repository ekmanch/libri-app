import 'package:flutter/material.dart';

import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/labels.dart';

/// What was picked in Show & seasons › Announced season dropped. Null when the
/// dialog was dismissed otherwise; then it is asked again after the next daily
/// check.
enum DroppedSeasonChoice { keep, remove }

/// "Season 2 of Carrie is no longer listed" (Show & seasons › Announced season
/// dropped): a season Libri added that TMDB no longer lists, or a show it marks
/// Canceled, which the user had given [status]. Keep it marks the season
/// manual, so it is never asked about again; Remove takes it out.
Future<DroppedSeasonChoice?> showDroppedSeasonDialog(
  BuildContext context, {
  required Entry show,
  required int season,
  required EntryStatus status,
}) {
  return showAppDialog<DroppedSeasonChoice>(
    context,
    builder: (context) => AppDialog(
      title: 'Season $season of ${show.title} is no longer listed',
      body:
          'TMDB has dropped it, so it was probably canceled. '
          'You had it as ${status.label}.',
      note: droppedSeasonNote(show, season),
      actions: [
        AppButton(
          label: 'Keep it',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context, DroppedSeasonChoice.keep),
        ),
        AppButton(
          label: 'Remove',
          kind: AppButtonKind.destructive,
          onPressed: () => Navigator.pop(context, DroppedSeasonChoice.remove),
        ),
      ],
    ),
  );
}

/// "Season 1 and the show stay as they are.", or "The other seasons and
/// the show …" when there are more.
String droppedSeasonNote(Entry show, int season) {
  final others = [
    for (final s in show.seasons ?? const [])
      if (s.season != season) s.season,
  ];
  final who = others.length == 1
      ? 'Season ${others.single}'
      : 'The other seasons';
  return '$who and the show stay as they are.';
}
