import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/artist_photo_fetcher.dart';
import '../../data/covers/cover_files.dart';
import '../../data/covers/cover_store.dart';
import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/operations/entry_operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/touch_target.dart';

/// "15 covers · 3 unused · 9.8 MB": the Uploaded covers row of Settings ›
/// Library connection.
String uploadedCoversSummary(List<CoverFile> files, Library library) {
  final unused = unusedCovers(files, library).length;
  final size = files.fold<int>(0, (sum, file) => sum + file.size);
  return [
    '${files.length} ${files.length == 1 ? 'cover' : 'covers'}',
    if (unused > 0) '$unused unused',
    coverSizeLabel(size),
  ].join(' · ');
}

/// The read-only Artist photos row of Settings › Library connection (and
/// its state "artist photos not ready yet"; DESIGN.md section 10e): the
/// phone never runs the first full run, so until the desktop has finished
/// it the row says it is waiting; after that, how many of the artists that
/// can have a photo have one. Null when the library has no artists. With
/// the library kept on this phone ([local]) there is no desktop run to
/// wait for, and nothing is looked up.
String? artistPhotosSummary(
  Library library,
  CoverStore covers, {
  bool local = false,
}) {
  final (:have, :total) = artistPhotoCounts(library, covers);
  if (total == 0) return null;
  final count =
      '$have of $total ${total == 1 ? 'artist has' : 'artists have'} one.';
  if (local) return count;
  if (covers.backfilled == null) {
    return 'Waiting for the first run on the desktop.';
  }
  return '$count New artists are looked up as you add them.';
}

void openYourCoversScreen(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const YourCoversScreen()));
}

/// One row of the review: the file, the title it goes with, and what the
/// row says about it.
class CoverReviewRow {
  const CoverReviewRow({
    required this.file,
    required this.name,
    required this.detail,
    required this.unused,
  });

  final CoverFile file;

  /// The path for an unused file (the one place a path is shown, since
  /// nothing else identifies it), the title for the others.
  final String name;
  final String detail;
  final bool unused;

  /// Every cover file of [library]: the unused first (no title uses them
  /// and their name matches no title), then the rest by title.
  static List<CoverReviewRow> of(List<CoverFile> files, Library library) {
    final unused = unusedCovers(files, library).toSet();
    final rows = <CoverReviewRow>[
      for (final file in files)
        if (unused.contains(file))
          CoverReviewRow(
            file: file,
            name: file.path,
            // A name the apps gave it was some title's upload.
            detail: isCoverUploadLabel(coverLabelAndExtension(file.name).$1)
                ? 'Its title was deleted'
                : 'Doesn’t match any title',
            unused: true,
          ),
    ];
    final used = <CoverReviewRow>[];
    for (final file in files) {
      if (unused.contains(file)) continue;
      final users = coverUsers(library, file.path);
      final entry = users.firstOrNull ?? coverTitleOf(library, file);
      used.add(
        CoverReviewRow(
          file: file,
          name: entry?.title ?? file.path,
          detail: [
            if (entry != null) ..._about(entry),
            ?file.label,
            if (users.isEmpty) 'not in use',
          ].join(' · '),
          unused: false,
        ),
      );
    }
    used.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...rows, ...used];
  }

  /// "Movie", "1999"; "Album", "Alice in Chains", "1994".
  static List<String> _about(Entry entry) => [
    if (entry.type == MediaType.music)
      entry.kind == EntryKind.song ? 'Song' : 'Album'
    else
      entry.type.singular,
    if (entry.type == MediaType.music) ?entry.creator,
    if (entry.year case final year?) '$year',
  ];
}

/// Settings › Your covers: review. Every cover file in the library repo:
/// Unused first, with its path and why ("Its title was deleted", "Doesn’t
/// match any title") and Delete preselected; then In use, with the title,
/// its type and year (and the file's label) and Keep preselected. Each row
/// has Delete | Keep, and the button counts what will go ("Delete 3
/// files", a neutral fill with red text). Deleting a cover that is in use
/// sends its title back to its online cover, or to none.
class YourCoversScreen extends ConsumerStatefulWidget {
  const YourCoversScreen({super.key});

  @override
  ConsumerState<YourCoversScreen> createState() => _YourCoversScreenState();
}

class _YourCoversScreenState extends ConsumerState<YourCoversScreen> {
  /// The rows whose choice was changed from the preselected one, by path.
  final _picked = <String, bool>{};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    ref.read(coverStoreProvider).refresh(ifStale: true);
  }

  bool _deletes(CoverReviewRow row) => _picked[row.file.path] ?? row.unused;

  Future<void> _apply(List<CoverReviewRow> rows) async {
    setState(() => _deleting = true);
    final repository = ref.read(libraryRepositoryProvider);
    final store = ref.read(coverStoreProvider);
    final library = await repository.load();
    for (final row in rows) {
      // The titles first: the library must not name a file that is gone.
      final users = coverUsers(library, row.file.path);
      for (final user in users) {
        await repository.apply(SetCover(user.id));
      }
      await store.delete(
        row.file.path,
        summary: users.isNotEmpty
            ? 'Delete a cover of ${users.first.title}'
            : 'Delete the cover ${row.file.path}',
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final files = ref.watch(coverFilesProvider);
    final library = ref.watch(libraryProvider).value;
    final onGitHub = ref.watch(coverStoreProvider).remote != null;
    final rows = library == null
        ? const <CoverReviewRow>[]
        : CoverReviewRow.of(files, library);
    final unused = [
      for (final row in rows)
        if (row.unused) row,
    ];
    final used = [
      for (final row in rows)
        if (!row.unused) row,
    ];
    final going = [
      for (final row in rows)
        if (_deletes(row)) row,
    ];
    final help = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.normal,
      fontSize: 13.5,
      height: 1.4,
      color: colors.muted,
    );

    List<Widget> group(String name, List<CoverReviewRow> rows, String? note) =>
        rows.isEmpty
        ? const []
        : [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 2),
              child: Row(
                children: [
                  Text(name.toUpperCase(), style: theme.textTheme.labelSmall),
                  const SizedBox(width: 8),
                  Text(
                    '${rows.length}',
                    style: help.copyWith(fontSize: 13, height: 1),
                  ),
                ],
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(note, style: help),
              ),
            for (final row in rows)
              _ReviewRow(
                row: row,
                delete: _deletes(row),
                onChanged: _deleting
                    ? null
                    : (delete) =>
                          setState(() => _picked[row.file.path] = delete),
              ),
          ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Your covers',
              onBack: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                'Covers you uploaded. Deleting one removes the file from '
                '${onGitHub ? 'GitHub' : 'your library'}; a title that used '
                'it goes back to its online cover.',
                style: help.copyWith(fontSize: 14.5, height: 1.45),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ...group(
                    'Unused',
                    unused,
                    'No title uses these, and their names match no title.',
                  ),
                  ...group('In use', used, null),
                  if (rows.isEmpty && library != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text('No covers uploaded.', style: help),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Cancel',
                      kind: AppButtonKind.outline,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: going.isEmpty
                          ? 'Nothing to delete'
                          : 'Delete ${going.length} '
                                '${going.length == 1 ? 'file' : 'files'}',
                      kind: AppButtonKind.neutralDestructive,
                      onPressed: going.isEmpty || _deleting
                          ? null
                          : () => _apply(going),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.row,
    required this.delete,
    required this.onChanged,
  });

  final CoverReviewRow row;
  final bool delete;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final square = row.file.folder == coverFolder(MediaType.music);
    const width = 40.0;
    final height = square ? width : width * 3 / 2;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          CachedImage(
            url: row.file.coverFrom,
            width: width,
            height: height,
            placeholder: ColoredBox(color: colors.surfaceHigh),
            borderRadius: BorderRadius.circular(7),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: row.unused
                      ? theme.textTheme.bodyMedium!.copyWith(
                          fontFamily: AppFonts.code,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        )
                      : theme.textTheme.labelLarge!.copyWith(fontSize: 16),
                ),
                if (row.detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    row.detail,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontStyle: FontStyle.normal,
                      fontSize: 13.5,
                      color: colors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            container: true,
            label: row.name,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Choice(
                  label: 'Delete',
                  picked: delete,
                  destructive: true,
                  onTap: onChanged == null ? null : () => onChanged!(true),
                ),
                const SizedBox(width: 6),
                _Choice(
                  label: 'Keep',
                  picked: !delete,
                  destructive: false,
                  onTap: onChanged == null ? null : () => onChanged!(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of a row's two answers: a 32 dp pill with a 48 dp touch area,
/// filled when picked, Delete in red.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.picked,
    required this.destructive,
    required this.onTap,
  });

  final String label;
  final bool picked;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return TouchTarget(
      child: Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        checked: picked,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: picked ? colors.selectedFill : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: picked ? Colors.transparent : theme.colorScheme.outline,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium!.copyWith(
                fontSize: 13,
                color: !picked
                    ? colors.muted
                    : destructive
                    ? colors.dangerText
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
