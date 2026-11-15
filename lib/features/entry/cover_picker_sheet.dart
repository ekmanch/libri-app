import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/cover_files.dart';
import '../../data/covers/cover_picture.dart';
import '../../data/images/artwork_providers.dart';
import '../../data/library_providers.dart';
import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../data/operations/entry_operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/chips.dart';
import '../../widgets/cover_choice.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/labels.dart';
import '../../widgets/lookup_notice.dart';
import '../../widgets/sheet_frame.dart';
import 'cover_upload_sheets.dart';

/// A cover picked in [CoverPickerSheet]: the id to store as `cover_from`
/// (null for the match's own cover, "repo:…" for one of your own files),
/// whether the title keeps your cover for good (`cover_keep_mine`), and
/// the image to show until the entry is saved.
typedef CoverPick = ({String? coverFrom, bool keepMine, String? url});

/// What Pick a cover works on: the entry the form is making or editing,
/// whose pick waits in the form for Save; or ([stored]) an entry of the
/// library, a song's album, whose pick is saved at once.
class CoverSubject {
  const CoverSubject({
    required this.id,
    required this.type,
    required this.title,
    this.year,
    this.creator,
    this.source,
    this.coverFrom,
    this.keepMine = false,
    this.stored = false,
    this.song,
  });

  /// The song's album [album], for the song titled [song].
  CoverSubject.album(Entry album, {required String this.song})
    : id = album.id,
      type = album.type,
      title = album.title,
      year = album.year,
      creator = album.creator,
      source = album.source,
      coverFrom = album.coverFrom,
      keepMine = album.coverKeepMine ?? false,
      stored = true;

  /// The entry's id, or the id a new entry would get now: its slug names
  /// the files.
  final String id;
  final MediaType type;
  final String title;
  final int? year;
  final String? creator;

  /// The entry's own lookup id; its match is not offered twice.
  final String? source;

  /// The `cover_from` in effect.
  final String? coverFrom;
  final bool keepMine;
  final bool stored;

  /// The song the picker was opened on, when this is its album.
  final String? song;
}

/// Opens Add / edit entry › Pick a cover on [subject]. [ownCoverUrl] is the
/// match's own cover when the caller knows it. A tap picks at once through
/// [onPicked]; Done closes.
Future<void> showCoverPicker(
  BuildContext context, {
  required CoverSubject subject,
  String? ownCoverUrl,
  bool askForMatchCover = false,
  required ValueChanged<CoverPick> onPicked,
}) => showAppSheet<void>(
  context,
  builder: (context) => CoverPickerSheet(
    subject: subject,
    ownCoverUrl: ownCoverUrl,
    askForMatchCover: askForMatchCover,
    onPicked: onPicked,
  ),
);

/// Add / edit entry › Pick a cover: "Pick a cover", "The Mummy · 1999. Only
/// the cover changes.", Done, then two sections, three covers to a row.
///
/// Your covers: an Upload tile, then the title's own files in the library
/// repo (DESIGN.md section 10d), each with a "Yours" badge; a long press
/// offers Delete file. Online, with its count: the match's own cover first,
/// captioned "The match’s cover", then the other matches for the title with
/// their year and edition. The picked one is ringed. No file names, folders
/// or source names are shown.
///
/// Upload opens the sources (Photo library, Files, Paste image); the tile
/// reads "Reading…" meanwhile, and a file that is not an image leaves one
/// red line. An image clearly off the cover's shape goes through Fit your
/// cover first. The new cover is picked at once and shown from the phone's
/// own copy.
///
/// While one of your files is the cover: an online cover that has turned
/// up since has a "New" badge with "Keep mine", and picking any online
/// cover asks whether your file goes too.
///
/// A song shows its album's cover, so its picker works on the album.
class CoverPickerSheet extends ConsumerStatefulWidget {
  const CoverPickerSheet({
    super.key,
    required this.subject,
    this.ownCoverUrl,
    this.askForMatchCover = false,
    required this.onPicked,
  });

  final CoverSubject subject;
  final String? ownCoverUrl;

  /// Opens with the match's cover tapped: "Use the match’s cover" in the
  /// form while one of your files is the cover, which asks about the file.
  final bool askForMatchCover;
  final ValueChanged<CoverPick> onPicked;

  /// "1975 · Hardcover": the edition's year (else the match's) and edition,
  /// the dot kept with the edition so a wrap never leaves it dangling.
  static String caption(LookupMatch match) =>
      captionOf(match.editionYear ?? match.released?.year, match.edition);

  static String captionOf(int? year, String? edition) =>
      [if (year != null) '$year', ?edition].join(' · ');

  @override
  ConsumerState<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends ConsumerState<CoverPickerSheet> {
  late String? _picked = widget.subject.coverFrom;
  late bool _keepMine = widget.subject.keepMine;
  late String? _ownCoverUrl = widget.ownCoverUrl;
  LookupResult? _result;

  /// More covers of an album from the second music catalog, asked for by
  /// the link under Online (Pick a cover: more covers found): null until
  /// asked, and whether the ask is on its way or failed.
  List<LookupMatch>? _more;
  bool _moreLoading = false;
  bool _moreFailed = false;

  /// An image is being read, or Fit your cover is open on it.
  bool _reading = false;

  /// The last file picked was not an image.
  bool _notAnImage = false;

  /// The files uploaded while the sheet was open: "Just uploaded".
  final _fresh = <String>{};

  CoverSubject get _subject => widget.subject;
  bool get _square => _subject.type == MediaType.music;

  @override
  void initState() {
    super.initState();
    _lookUp();
    // A file committed meanwhile is offered: the list is asked for again
    // when it is more than a minute old.
    ref.read(coverStoreProvider).refresh(ifStale: true);
    if (_ownCoverUrl == null && _subject.stored) _findOwnCover();
    if (widget.askForMatchCover) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickOnline(null, _ownCoverUrl);
      });
    }
  }

  /// The match's own cover of a library entry (a song's album).
  Future<void> _findOwnCover() async {
    final library = await ref.read(libraryRepositoryProvider).load();
    final entry = library.entryById(_subject.id);
    if (entry == null) return;
    final url = await ref.read(artworkResolverProvider).ownCoverUrl(entry);
    if (mounted && url != null) setState(() => _ownCoverUrl = url);
  }

  Future<void> _lookUp() async {
    setState(() => _result = null);
    final result = await ref
        .read(lookupServiceProvider)
        .coverChoices(
          _subject.title,
          type: _subject.type,
          creator: _subject.creator,
        );
    if (mounted) setState(() => _result = result);
  }

  /// "None of these? Search for more covers": asks the second catalog once
  /// for the album and adds its covers to the grid. Music only.
  Future<void> _searchMore() async {
    if (_moreLoading || _more != null) return;
    setState(() {
      _moreLoading = true;
      _moreFailed = false;
    });
    List<LookupMatch>? found;
    try {
      found = await ref
          .read(lookupServiceProvider)
          .moreMusicCovers(_subject.title, creator: _subject.creator);
    } on LookupException {
      found = null;
    }
    if (!mounted) return;
    setState(() {
      _moreLoading = false;
      _more = found;
      _moreFailed = found == null;
    });
  }

  /// Whether the lookup is known to have a cover for the title: picking
  /// your own over it is then a choice made, and no online cover is
  /// pointed out for the title later.
  bool get _onlineKnown =>
      (_picked != null && !isRepoCover(_picked)) ||
      _keepMine ||
      _ownCoverUrl != null;

  void _choose(String? coverFrom, String? url, {bool? keepMine}) {
    final keep =
        isRepoCover(coverFrom) && (keepMine ?? (_keepMine || _onlineKnown));
    if (coverFrom == _picked && keep == _keepMine) return;
    setState(() {
      _picked = coverFrom;
      _keepMine = keep;
    });
    if (_subject.stored) {
      ref
          .read(libraryRepositoryProvider)
          .apply(SetCover(_subject.id, coverFrom: coverFrom, keepMine: keep));
    }
    widget.onPicked((coverFrom: coverFrom, keepMine: keep, url: url));
  }

  /// An online cover: while one of your files is in use, "Delete your file
  /// too?" first.
  Future<void> _pickOnline(String? coverFrom, String? url) async {
    final own = repoCoverPath(_picked);
    if (own == null) {
      _choose(coverFrom, url);
      return;
    }
    final store = ref.read(coverStoreProvider);
    final choice = await showDeleteOwnFileDialog(
      context,
      title: _subject.title,
      onGitHub: store.remote != null,
    );
    if (choice == null || !mounted) return;
    _choose(coverFrom, url);
    if (choice == OwnFileChoice.delete) {
      final library = await ref.read(libraryRepositoryProvider).load();
      // Another title showing the same file keeps it.
      if (!coverUsedElsewhere(library, own, _subject.id)) {
        await _deleteFile(own);
      }
    }
  }

  /// Removes one of your files. Every title that shows it goes back to its
  /// match's cover, or to none: the library never names a file that is
  /// gone.
  Future<void> _deleteFile(String path) async {
    final repository = ref.read(libraryRepositoryProvider);
    final library = await repository.load();
    final current = repoCoverPath(_picked) == path;
    for (final user in coverUsers(library, path)) {
      await repository.apply(
        SetCover(
          user.id,
          // The form's entry takes the cover picked here meanwhile.
          coverFrom: user.id == _subject.id && !current ? _picked : null,
          keepMine: user.id == _subject.id && !current && _keepMine,
        ),
      );
    }
    await ref
        .read(coverStoreProvider)
        .delete(path, summary: 'Delete a cover of ${_subject.title}');
    _fresh.remove(path);
    if (mounted && current) _choose(null, _ownCoverUrl);
  }

  Future<void> _openFileMenu(CoverFile file, Widget cover) async {
    final library = ref.read(libraryProvider).value;
    final users = library == null
        ? const <Entry>[]
        : coverUsers(library, file.path);
    final used = users.isNotEmpty || repoCoverPath(_picked) == file.path;
    final store = ref.read(coverStoreProvider);
    final where = store.remote == null ? 'your library' : 'GitHub';
    final delete = await showCoverFileSheet(
      context,
      cover: cover,
      detail:
          '${used ? 'Used as the cover of' : 'Uploaded for'} '
          '${users.isEmpty ? _subject.title : users.first.title}. Deleting '
          'removes the file from $where.',
    );
    if (delete == true && mounted) await _deleteFile(file.path);
  }

  /// Upload: the sources, the image read and scaled, Fit your cover when
  /// its shape is clearly another, then stored and picked at once.
  Future<void> _upload() async {
    if (_reading) return;
    final sources = ref.read(coverSourcesProvider);
    final withPaste = await sources.clipboardHasImage();
    if (!mounted) return;
    final choice = await showCoverSourceSheet(context, withPaste: withPaste);
    if (choice == null || !mounted) return;
    setState(() {
      _reading = true;
      _notAnImage = false;
    });
    try {
      final bytes = await switch (choice) {
        CoverSourceChoice.photos => sources.fromPhotos(),
        CoverSourceChoice.files => sources.fromFiles(),
        CoverSourceChoice.clipboard => sources.fromClipboard(),
      };
      if (bytes == null || !mounted) return;
      final pictures = ref.read(coverPicturesProvider);
      final (width, height) = await pictures.sizeOf(bytes);
      final PreparedCover prepared;
      if (coverShapeFits(width, height, square: _square)) {
        prepared = await pictures.prepare(bytes);
      } else {
        if (!mounted) return;
        final at = await showCoverFitSheet(
          context,
          bytes: bytes,
          width: width,
          height: height,
          square: _square,
        );
        // Back: nothing is added.
        if (at == null) return;
        prepared = await pictures.fit(bytes, at: at, square: _square);
      }
      final name = coverUploadName(coverSlug(_subject.id), prepared.sha);
      final path = '${coverFolder(_subject.type)}/$name';
      await ref
          .read(coverStoreProvider)
          .add(
            path,
            prepared.bytes,
            sha: prepared.sha,
            summary: 'Add a cover for ${_subject.title}',
          );
      _fresh.add(path);
      if (mounted) _choose(repoCoverFrom(path), repoCoverFrom(path));
    } on CoverPictureException {
      if (mounted) setState(() => _notAnImage = true);
    } on Exception catch (e) {
      // A picker that failed, or a file that could not be read or kept.
      debugPrint('Upload failed: $e');
      if (mounted) setState(() => _notAnImage = true);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final subject = _subject;
    final result = _result;
    final files = ref.watch(coverFilesProvider);
    final pickedPath = repoCoverPath(_picked);
    final own = coverCandidates(files, subject.type, subject.id);
    // The file in use is listed even when its name is another title's (a
    // new entry whose title changed after the upload).
    if (pickedPath != null && !own.any((f) => f.path == pickedPath)) {
      final file = files.where((f) => f.path == pickedPath).firstOrNull;
      if (file != null) own.add(file);
    }
    // This session's uploads come last, in the order they were made.
    final earlier = [
      for (final file in own)
        if (!_fresh.contains(file.path)) file,
    ];
    final fresh = [
      for (final path in _fresh) ...own.where((f) => f.path == path),
    ];
    own
      ..clear()
      ..addAll(earlier)
      ..addAll(fresh);
    final choices = [
      for (final match in result?.matches ?? const <LookupMatch>[])
        if (match.source != subject.source &&
            match.cacheCoverUrl != _ownCoverUrl)
          match,
    ];
    final listed = choices.length;
    for (final match in _more ?? const <LookupMatch>[]) {
      final url = match.cacheCoverUrl;
      if (url != _ownCoverUrl && !choices.any((c) => c.cacheCoverUrl == url)) {
        choices.add(match);
      }
    }
    final moreFound = choices.length - listed;
    final hasOwnOnline = _ownCoverUrl != null;
    final onlineCount = (hasOwnOnline ? 1 : 0) + choices.length;
    // An online cover turned up for a title that has been using yours.
    final isNew = pickedPath != null && !_keepMine && hasOwnOnline;
    final hint = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.normal,
      fontSize: 13.5,
      height: 1.4,
      color: colors.muted,
    );
    // A placeholder for a cover not found yet, drawn like the library's.
    final placeholderEntry = Entry(
      id: '',
      type: subject.type,
      title: subject.title,
      status: EntryStatus.want,
      added: DateTime(2000),
    );
    final ratio = CoverPlaceholder.aspectRatio(subject.type);
    Widget cover(String? url, double width, {double radius = 8}) {
      return CachedImage(
        url: url,
        width: width,
        height: width / ratio,
        placeholder: CoverPlaceholder(
          entry: placeholderEntry,
          width: width,
          fontSize: 11,
        ),
        borderRadius: BorderRadius.circular(radius),
      );
    }

    final song = subject.song;
    return SheetFrame(
      scrollable: true,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick a cover', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  song != null
                      ? '$song uses its album’s cover. Changing it here '
                            'changes ${subject.title}’s cover.'
                      : '${subject.title}'
                            '${subject.year == null ? '' : ' · ${subject.year}'}'
                            '. Only the cover changes.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Done',
            compact: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            (song != null ? '${subject.title}’s covers' : 'Your covers')
                .toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 10),
          CoverChoiceGrid(
            count: 1 + own.length,
            runSpacing: 16,
            itemBuilder: (i, width) {
              if (i == 0) {
                return _UploadTile(
                  width: width,
                  ratio: ratio,
                  reading: _reading,
                  onTap: _upload,
                );
              }
              final file = own[i - 1];
              return CoverChoice(
                cover: cover(file.coverFrom, CoverChoice.imageWidth(width)),
                title: file.label ?? 'Your cover',
                width: width,
                picked: _picked == file.coverFrom,
                badge: 'Yours',
                lines: [if (_fresh.contains(file.path)) 'Just uploaded'],
                onTap: () => _choose(file.coverFrom, file.coverFrom),
                onLongPress: () =>
                    _openFileMenu(file, cover(file.coverFrom, 44)),
              );
            },
          ),
          if (_notAnImage)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'That file isn’t an image.',
                  style: hint.copyWith(color: colors.dangerText),
                ),
              ),
            ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Text('ONLINE', style: theme.textTheme.labelSmall),
                if (onlineCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$onlineCount',
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontStyle: FontStyle.normal,
                      fontSize: 13,
                      color: colors.muted,
                    ),
                  ),
                ],
                const Spacer(),
                if (isNew)
                  TextButton(
                    onPressed: () => _choose(_picked, _picked, keepMine: true),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: theme.textTheme.labelMedium,
                    ),
                    child: const Text('Keep mine'),
                  ),
              ],
            ),
          ),
          if (isNew)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'An online cover is available now. You’ve been using your '
                'own.',
                style: hint,
              ),
            ),
          CoverChoiceGrid(
            count: onlineCount,
            runSpacing: 16,
            itemBuilder: (i, width) {
              final w = CoverChoice.imageWidth(width);
              if (hasOwnOnline && i == 0) {
                return CoverChoice(
                  cover: cover(_ownCoverUrl, w),
                  title: subject.title,
                  width: width,
                  picked: _picked == null,
                  badge: isNew ? 'New' : null,
                  badgeAccent: true,
                  lines: [
                    if (subject.year case final year?) '$year',
                    'The match’s cover',
                  ],
                  onTap: () => _pickOnline(null, _ownCoverUrl),
                );
              }
              final match = choices[i - (hasOwnOnline ? 1 : 0)];
              final caption = CoverPickerSheet.caption(match);
              return CoverChoice(
                cover: cover(match.coverUrl ?? match.cacheCoverUrl, w),
                title: match.title,
                width: width,
                picked: _picked == match.coverFrom,
                lines: [if (caption.isNotEmpty) caption],
                onTap: () => _pickOnline(match.coverFrom, match.cacheCoverUrl),
              );
            },
          ),
          if (result == null)
            const LookupNotice('Looking for covers…', spinner: true)
          else if (result.notConfigured && onlineCount == 0)
            LookupNotice(
              'Lookups for ${subject.type.label.toLowerCase()} are not set '
              'up on this build (no API key).',
            )
          else if (result.allFailed case final failure?)
            LookupNotice(
              failure == LookupFailure.offline
                  ? 'Could not reach the lookup. Check your connection and '
                        'try again.'
                  : 'The lookup did not answer. Try again in a moment.',
              onRetry: _lookUp,
            )
          else if (result.partlyFailed)
            LookupNotice(
              'Some lookups could not be reached, so a cover may be '
              'missing. Try again in a moment.',
              onRetry: _lookUp,
            )
          else if (onlineCount == 0)
            Text(
              'No online cover found for this title. Upload your own '
              'above.',
              style: hint.copyWith(fontSize: 14.5, height: 1.45),
            ),
          // Albums and songs only: one more ask, of the second catalog.
          if (_square && result != null)
            if (_more == null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _moreLoading ? null : _searchMore,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    disabledForegroundColor: colors.muted,
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    alignment: AlignmentDirectional.centerStart,
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  child: Text(
                    _moreLoading
                        ? 'Searching…'
                        : _moreFailed
                        ? 'The search did not answer. Try again'
                        : 'None of these? Search for more covers',
                  ),
                ),
              )
            else if (moreFound == 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text('No more covers found.', style: hint),
                ),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The first tile of Your covers: a dashed frame of a cover's shape with
/// an upload arrow and "Upload", or "Reading…" while an image is read.
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.width,
    required this.ratio,
    required this.reading,
    required this.onTap,
  });

  final double width;
  final double ratio;
  final bool reading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final inner = CoverChoice.imageWidth(width);
    return Semantics(
      button: true,
      label: reading ? 'Reading the image' : 'Upload a cover',
      excludeSemantics: true,
      child: InkWell(
        onTap: reading ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // The room a cover's ring takes, so the tiles line up.
                padding: const EdgeInsets.all(4),
                child: CustomPaint(
                  painter: DashedStadiumPainter(
                    theme.colorScheme.outline,
                    radius: 8,
                  ),
                  child: SizedBox(
                    width: inner,
                    height: inner / ratio,
                    // No spinner: the caption changes, as in the mockup.
                    child: Center(
                      child: StrokeIcon(
                        AppIcons.upload,
                        size: 24,
                        color: reading ? colors.placeholder : colors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                reading ? 'Reading…' : 'Upload',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium!.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
