import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/artist_photo_fetcher.dart';
import '../../data/covers/artist_photo_providers.dart';
import '../../data/covers/artist_photos.dart';
import '../../data/covers/cover_files.dart';
import '../../data/covers/cover_picture.dart';
import '../../data/covers/cover_store.dart';
import '../../data/images/artwork_providers.dart';
import '../../data/library_providers.dart';
import '../../data/lookup/apple_artists.dart';
import '../../data/lookup/lookup_failure.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_kind.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/artist_photo.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/chips.dart';
import '../../widgets/cover_choice.dart';
import '../../widgets/sheet_frame.dart';
import '../entry/cover_upload_sheets.dart';

/// Opens Music › Pick a photo for the artist called [name].
Future<void> showArtistPhotoPicker(
  BuildContext context, {
  required String name,
}) => showAppSheet<void>(context, builder: (_) => ArtistPhotoSheet(name: name));

/// What the larger view (Music › Artist photo, larger: no photo yet;
/// `showLargerArtistPhoto`) says under the name of an artist with no file of
/// their own, showing one of the library's covers ([cover]) or initials.
String noArtistPhotoNote({required bool cover}) => cover
    ? 'No photo yet. One of your album covers is shown.'
    : 'No photo yet.';

/// What Music › Artist photo: your pick wasn't saved says for [name]. A
/// refused "Use automatic" is reported the same way.
String droppedPhotoMessage(String name) =>
    'Another device chose a photo for $name first, so your pick was '
    'dropped.';

/// Tells the owner that a sync dropped their photo for an artist (GitHub
/// already had one this phone never saw), with Pick again, which opens
/// Music › Pick a photo for that artist. One message per artist.
void showDroppedPhotos(
  BuildContext context,
  List<DroppedPhoto> dropped, {
  EdgeInsets margin = const EdgeInsets.fromLTRB(16, 0, 16, 24),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (messenger == null) return;
  final theme = Theme.of(context);
  final colors = LibraryColors.of(context);
  final told = <String>{};
  for (final photo in dropped) {
    if (!told.add(photo.path)) continue;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          droppedPhotoMessage(photo.name),
          style: theme.textTheme.bodyMedium!.copyWith(
            fontSize: 14,
            height: 1.4,
            color: theme.colorScheme.onSurface,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        // A snackbar with an action stays until it is used unless told
        // otherwise.
        persist: false,
        duration: const Duration(seconds: 10),
        margin: margin,
        // The raised card of the mockup, not the inverse bar.
        backgroundColor: colors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        action: SnackBarAction(
          label: 'Pick again',
          textColor: AccentColors.of(context).link,
          onPressed: () {
            final context = navigator?.context;
            if (context != null && context.mounted) {
              showArtistPhotoPicker(context, name: photo.name);
            }
          },
        ),
      ),
    );
  }
}

/// One round tile of the picker: its caption, the image it shows, and how
/// a tap on it is saved.
class _Tile {
  const _Tile({
    required this.caption,
    required this.url,
    this.badge,
    this.current = false,
    this.asServed = false,
    this.suggested = false,
  });

  final String caption;

  /// The image's key in the device cache: a URL, or "repo:" and a path.
  final String url;
  final String? badge;

  /// It is the photo in use: ringed, and a tap changes nothing.
  final bool current;

  /// Apple's own square JPEG, stored exactly as it was served.
  final bool asServed;

  /// The automatic choice: picking it counts as the fetch's, not a pick.
  final bool suggested;
}

/// Music › Pick a photo (and its states: others with the same name, your
/// own upload, no photo found, upload from): the Pick a cover sheet with
/// round tiles, one list with no headings, no file names and no source
/// names. Upload first; your own photo when the file is one you picked or
/// uploaded on this phone; "Suggested", the photo found for the artist;
/// "Another photo", a second one asked for only when the sheet opens; then
/// the covers of what you saved by the artist. A tap is the choice: it is
/// saved at once as the artist's one file and shown everywhere from the
/// phone's own copy (DESIGN.md section 10e).
class ArtistPhotoSheet extends ConsumerStatefulWidget {
  const ArtistPhotoSheet({super.key, required this.name});

  final String name;

  /// How many other artists of the name are loaded at most.
  static const othersLimit = 10;

  @override
  ConsumerState<ArtistPhotoSheet> createState() => _ArtistPhotoSheetState();
}

class _ArtistPhotoSheetState extends ConsumerState<ArtistPhotoSheet> {
  /// What Apple offers; null until it answered, or when it could not be
  /// asked ([_appleAsked] then says the ask is over).
  ArtistChoices? _choices;
  bool _appleAsked = false;

  /// The music source's own photo of the artist.
  String? _another;

  /// The covers of what is saved by the artist, in the order they are
  /// lent: the entry and its cover.
  List<(Entry, String)> _covers = const [];

  /// The other artists of the name whose photos were loaded.
  final _others = <(OtherArtist, String)>[];
  bool _othersLoading = false;
  bool _othersDone = false;

  /// An image is being read, or Fit your cover is open on it.
  bool _reading = false;
  bool _notAnImage = false;

  /// A tile's image is being saved.
  bool _saving = false;

  String get _name => widget.name;

  @override
  void initState() {
    super.initState();
    // A photo set on another device meanwhile is offered: the list is
    // asked for again when it is more than a minute old.
    ref.read(coverStoreProvider).refresh(ifStale: true);
    unawaited(_askApple());
    unawaited(_askAnother());
    // The covers follow what is saved by the artist, also when the
    // library comes after the sheet.
    ref.listenManual(
      artistCoverEntriesProvider.select(
        (saved) => saved[artistCoverKey(_name)],
      ),
      (_, entries) => unawaited(_findCovers(entries ?? const [])),
      fireImmediately: true,
    );
  }

  int _coverRun = 0;

  Future<void> _askApple() async {
    ArtistChoices? choices;
    if (!isSkippedArtist(_name) && artistSlug(_name) != null) {
      try {
        final library = await ref.read(libraryProvider.future);
        if (!mounted) return;
        final apple = ref.read(appleArtistsProvider)
          ..photoSide = ref.read(coverStoreProvider).photoSize;
        choices = await apple.choices(
          _name,
          ownedTitlesOf(library, _name),
          savedSongsOf(library, _name),
        );
      } on LookupException {
        // Not an answer: no Suggested tile, and nothing is said.
        choices = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _choices = choices;
      _appleAsked = true;
    });
  }

  Future<void> _askAnother() async {
    if (isSkippedArtist(_name)) return;
    final url = await ref
        .read(artworkResolverProvider)
        .anotherArtistPhoto(_name);
    if (mounted && url != null) setState(() => _another = url);
  }

  /// The covers of the artist's saved albums, then of their songs, one of
  /// each image.
  Future<void> _findCovers(List<Entry> entries) async {
    final run = ++_coverRun;
    final resolver = ref.read(artworkResolverProvider);
    final library = ref.read(libraryProvider).value;
    final found = <(Entry, String)>[];
    for (final entry in entries) {
      var shown = entry;
      if (library != null && entry.kind == EntryKind.song) {
        final owner = coverOwner(library, entry);
        if (isRepoCover(owner.coverFrom)) shown = owner;
      }
      final url = await resolver.coverUrl(shown);
      if (!mounted || run != _coverRun) return;
      if (url == null || found.any((c) => c.$2 == url)) continue;
      found.add((entry, url));
      setState(() => _covers = [...found]);
    }
    if (found.isEmpty && _covers.isNotEmpty) setState(() => _covers = const []);
  }

  /// "Not the right artist? Show others named …": their pages are read
  /// only now, at most ten, one after another, each tile added as it
  /// comes.
  Future<void> _loadOthers() async {
    final others = _choices?.others ?? const <OtherArtist>[];
    if (_othersLoading || _othersDone || others.isEmpty) return;
    setState(() => _othersLoading = true);
    final apple = ref.read(appleArtistsProvider);
    for (final other in others.take(ArtistPhotoSheet.othersLimit)) {
      final String? url;
      try {
        final found = await apple.photoOf(other.id, other.page);
        url = found == null ? null : artistPhotoAt(found, apple.photoSide);
      } on LookupException catch (e) {
        // Apple refusing ends it; one page failing does not.
        if (e.failure == LookupFailure.rateLimited ||
            e.failure == LookupFailure.offline) {
          break;
        }
        continue;
      }
      if (!mounted) return;
      final photo = url;
      if (photo != null) setState(() => _others.add((other, photo)));
    }
    if (!mounted) return;
    setState(() {
      _othersLoading = false;
      _othersDone = true;
    });
  }

  static bool _isJpeg(Uint8List bytes) =>
      bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

  /// A tile was tapped: its picture, read from this phone (one not here
  /// yet is not picked), becomes the artist's file. Apple's JPEG is kept
  /// as it was served; any other image is made a JPEG like an upload.
  Future<void> _pick(_Tile tile) async {
    if (tile.current || _saving) return;
    setState(() => _saving = true);
    try {
      final image = await ref.read(imageCacheProvider).get(tile.url);
      if (image == null) return;
      var bytes = await image.file.readAsBytes();
      if (!(tile.asServed && _isJpeg(bytes))) {
        bytes =
            (await ref
                    .read(coverPicturesProvider)
                    .prepare(bytes, side: artistUploadSide))
                .bytes;
      }
      await ref
          .read(coverStoreProvider)
          .putArtistPhoto(
            _name,
            bytes,
            picked: !tile.suggested,
            summary: tile.suggested
                ? 'Add a photo of $_name'
                : 'Set the photo of $_name',
          );
    } on CoverPictureException {
      // Not an image after all: nothing changes.
    } on Exception catch (e) {
      debugPrint('Picking a photo failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Upload: the same sources as for a cover, and Fit your cover at 1:1
  /// for a picture that is not square.
  Future<void> _upload() async {
    if (_reading) return;
    final sources = ref.read(coverSourcesProvider);
    final withPaste = await sources.clipboardHasImage();
    if (!mounted) return;
    final choice = await showCoverSourceSheet(
      context,
      withPaste: withPaste,
      title: 'Upload a photo',
    );
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
      if (coverShapeFits(width, height, square: true)) {
        prepared = await pictures.prepare(bytes, side: artistUploadSide);
      } else {
        if (!mounted) return;
        final at = await showCoverFitSheet(
          context,
          bytes: bytes,
          width: width,
          height: height,
          square: true,
          side: artistUploadSide,
        );
        if (at == null) return;
        prepared = await pictures.fit(
          bytes,
          at: at,
          square: true,
          side: artistUploadSide,
        );
      }
      await ref
          .read(coverStoreProvider)
          .putArtistPhoto(
            _name,
            prepared.bytes,
            picked: true,
            uploaded: true,
            summary: 'Set the photo of $_name',
          );
    } on CoverPictureException {
      if (mounted) setState(() => _notAnImage = true);
    } on Exception catch (e) {
      debugPrint('Upload failed: $e');
      if (mounted) setState(() => _notAnImage = true);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _useAutomatic() => ref
      .read(coverStoreProvider)
      .removeArtistPhoto(_name, summary: 'Remove the photo of $_name');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final file = ref.watch(
      artistPhotoFilesProvider.select((files) => files[artistSlug(_name)]),
    );
    final kind = ref.read(coverStoreProvider).photoKindOf(_name);
    final suggested = _choices?.suggested;
    final hint = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.normal,
      fontSize: 14,
      height: 1.45,
      color: colors.muted,
    );

    final tiles = <_Tile>[
      // The file is one the owner chose on this phone.
      if (file != null && kind != null)
        _Tile(
          caption: 'Your photo',
          url: file.coverFrom,
          badge: 'Yours',
          current: true,
        ),
      // The file itself while it is the automatic one; else what Apple
      // has for the artist.
      if (file != null && kind == null)
        _Tile(caption: 'Suggested', url: file.coverFrom, current: true)
      else if (suggested != null)
        _Tile(
          caption: 'Suggested',
          url: suggested,
          asServed: true,
          suggested: true,
        ),
      if (_another case final url?) _Tile(caption: 'Another photo', url: url),
      for (final (other, url) in _others)
        _Tile(
          caption: other.album ?? 'Another artist',
          url: url,
          asServed: true,
        ),
      for (final (i, (entry, url)) in _covers.indexed)
        _Tile(
          caption: entry.year == null
              ? 'Album cover'
              : 'Album cover · ${entry.year}',
          url: url,
          // With no file the first of them is what the artist shows.
          current: file == null && i == 0,
        ),
    ];
    final noneFound = _appleAsked && suggested == null && file == null;
    final offersOthers = (_choices?.others.isNotEmpty ?? false) && !_othersDone;
    final initials = artistInitials(_name);

    return SheetFrame(
      scrollable: true,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick a photo', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  _name,
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
          CoverChoiceGrid(
            count: tiles.length + 1,
            runSpacing: 16,
            itemBuilder: (i, width) {
              if (i == 0) {
                return _UploadTile(
                  width: width,
                  reading: _reading,
                  onTap: _upload,
                );
              }
              final tile = tiles[i - 1];
              final w = CoverChoice.imageWidth(width);
              return CoverChoice(
                round: true,
                cover: CachedImage(
                  // The file keeps its name whatever the picture.
                  key: ValueKey('${tile.url}@${file?.sha}'),
                  url: tile.url,
                  width: w,
                  height: w,
                  shape: BoxShape.circle,
                  placeholder: ArtistInitials(
                    name: _name,
                    initials: initials,
                    size: w,
                  ),
                ),
                title: tile.caption,
                width: width,
                picked: tile.current,
                badge: tile.badge,
                onTap: () => _pick(tile),
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
          if (noneFound)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _covers.isEmpty
                    ? 'No photo was found for this artist.'
                    : 'No photo was found for this artist, so one of your '
                          'album covers is shown.',
                style: hint,
              ),
            ),
          if (offersOthers)
            _Link(
              label: _othersLoading
                  ? 'Loading…'
                  : 'Not the right artist? Show others named $_name',
              onTap: _othersLoading ? null : _loadOthers,
            ),
          // Only while a picked or uploaded photo is in effect.
          if (kind != null) _Link(label: 'Use automatic', onTap: _useAutomatic),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A text link under the tiles, 48 dp to touch.
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AccentColors.of(context).link,
          disabledForegroundColor: LibraryColors.of(context).muted,
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          alignment: AlignmentDirectional.centerStart,
          textStyle: theme.textTheme.labelMedium,
        ),
        child: Text(label),
      ),
    );
  }
}

/// The first tile: a dashed disc with an upload arrow and "Upload", or
/// "Reading…" while an image is read.
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.width,
    required this.reading,
    required this.onTap,
  });

  final double width;
  final bool reading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final inner = CoverChoice.imageWidth(width);
    return Semantics(
      button: true,
      label: reading ? 'Reading the image' : 'Upload a photo',
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
                // The room a tile's ring takes, so the tiles line up.
                padding: const EdgeInsets.all(4),
                child: CustomPaint(
                  painter: DashedStadiumPainter(theme.colorScheme.outline),
                  child: SizedBox(
                    width: inner,
                    height: inner,
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
