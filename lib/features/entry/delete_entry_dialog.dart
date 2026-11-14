import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/cover_files.dart';
import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/library.dart';
import '../../data/operations/entry_operations.dart';
import '../../data/models/plan.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/check_box_mark.dart';
import '../plans/plan_progress.dart';

/// Delete confirmation (Library › Delete confirmation, and Delete
/// confirmation: with a cover file). [plans] are the plans the entry is
/// in, which the body names. With [coverFiles], the entry's own cover
/// files (DESIGN.md section 10d), a ticked checkbox above the buttons
/// offers to delete them too: "Also delete its cover file", "Also delete
/// its 3 cover files". Resolves null when the user cancels, else whether
/// the files go too.
Future<({bool deleteCovers})?> askDeleteEntry(
  BuildContext context, {
  required Entry entry,
  required List<Plan> plans,
  int coverFiles = 0,
}) async {
  final names = plans.map(planTitle).toList();
  final where = switch (names.length) {
    0 => '',
    1 => ' and from the plan ${names.single}',
    _ =>
      ' and from the plans '
          '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
  var alsoCovers = coverFiles > 0;
  final confirmed = await showAppDialog<bool>(
    context,
    builder: (context) => AppDialog(
      title: 'Delete ${entry.title}?',
      body: 'It will be removed from your library$where.',
      note:
          'The change is saved to your GitHub repo, where earlier versions '
          'stay in the history.',
      footer: coverFiles == 0
          ? null
          : StatefulBuilder(
              builder: (context, setState) => Semantics(
                checked: alsoCovers,
                container: true,
                child: InkWell(
                  onTap: () => setState(() => alsoCovers = !alsoCovers),
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        CheckBoxMark(checked: alsoCovers),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            coverFiles == 1
                                ? 'Also delete its cover file'
                                : 'Also delete its $coverFiles cover files',
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      actions: [
        AppButton(
          label: 'Cancel',
          kind: AppButtonKind.outline,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: 'Delete',
          kind: AppButtonKind.destructive,
          icon: const StrokeIcon(AppIcons.trash),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return confirmed == true ? (deleteCovers: alsoCovers) : null;
}

/// The entry's own cover files: the ones named after it and the one it
/// shows, unless another title shows the file too.
List<CoverFile> ownCoverFiles(
  List<CoverFile> files,
  Library library,
  Entry entry,
) {
  final own = coverCandidates(files, entry.type, entry.id);
  final shown = repoCoverPath(entry.coverFrom);
  if (shown != null && !own.any((f) => f.path == shown)) {
    own.addAll(files.where((f) => f.path == shown));
  }
  return [
    for (final file in own)
      if (!coverUsedElsewhere(library, file.path, entry.id)) file,
  ];
}

/// Asks (Library › Delete confirmation), then deletes [entry], and with the
/// box ticked its own cover files after it. [beforeDelete] runs once the
/// user confirmed, before anything changes: a sheet showing the entry
/// closes itself there. True when the entry was deleted.
Future<bool> confirmDeleteEntry(
  BuildContext context,
  WidgetRef ref, {
  required Entry entry,
  required List<Plan> plans,
  VoidCallback? beforeDelete,
}) async {
  final repository = ref.read(libraryRepositoryProvider);
  final store = ref.read(coverStoreProvider);
  final library = await repository.load();
  await store.load();
  final files = ownCoverFiles(store.files, library, entry);
  if (!context.mounted) return false;
  final answer = await askDeleteEntry(
    context,
    entry: entry,
    plans: plans,
    coverFiles: files.length,
  );
  if (answer == null || !context.mounted) return false;
  beforeDelete?.call();
  // The entry first: the library must not name a file that is gone.
  await repository.apply(DeleteEntry(entry.id));
  if (answer.deleteCovers) {
    for (final file in files) {
      await store.delete(
        file.path,
        summary: 'Delete a cover of ${entry.title}',
      );
    }
  }
  return true;
}
