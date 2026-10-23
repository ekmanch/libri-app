import 'package:flutter/material.dart';

import '../../data/models/entry_status.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/entry_row.dart';
import 'cover_grid_tile.dart';
import 'series_groups.dart';

/// A series as one row of a type's list (Library › Movies, text view and
/// list with covers, with the Library › Series page (from a series row)
/// note): the series name, a stack icon with "4 movies · 2008–2024", and
/// "2 of 4 done", or the check when every part is done. The list with
/// covers shows the cover of the part that stands for the series.
class SeriesGroupRow extends StatelessWidget {
  const SeriesGroupRow({
    super.key,
    required this.group,
    required this.onTap,
    this.withCover = false,
  });

  final SeriesGroup group;
  final VoidCallback onTap;
  final bool withCover;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${group.title}, series, ${group.subtitle}, ${group.doneLabel}',
      button: true,
      excludeSemantics: true,
      child: EntryRow(
        title: group.title,
        subtitle: group.subtitle,
        subtitleIcon: AppIcons.stack,
        onTap: onTap,
        leading: withCover
            ? CoverImage(entry: group.coverEntry, width: 40)
            : null,
        trailing: group.allDone
            ? const StatusMark(EntryStatus.done)
            : StatusPill(group.doneLabel, filled: true),
      ),
    );
  }
}

/// A series as one tile of the grid (Library › Movies, grid with covers):
/// the cover of the part that stands for it with a stack badge and the
/// count, the series name, and "4 movies" under it.
class SeriesGridTile extends StatelessWidget {
  const SeriesGridTile({super.key, required this.group, required this.onTap});

  final SeriesGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${group.title}, series, ${group.subtitle}, ${group.doneLabel}',
      button: true,
      excludeSemantics: true,
      child: CoverGridTile(
        entry: group.coverEntry,
        title: group.title,
        caption: group.countLabel,
        seriesCount: group.count,
        done: group.allDone,
        onTap: onTap,
      ),
    );
  }
}
