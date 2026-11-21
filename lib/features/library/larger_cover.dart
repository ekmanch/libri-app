import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/covers/artist_photos.dart';
import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/artist_photo.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/entry_row.dart';
import '../entry/cover_picker_sheet.dart';
import '../entry/series.dart';
import '../music/artist_index.dart';
import '../music/artist_photo_sheet.dart';
import '../settings/display_preferences.dart';
import 'series_groups.dart';

/// Opens Library › Cover, larger for [entry]: its cover (a song's is its
/// album's), the name, the second line and Change cover, which closes the
/// view and opens Add / edit entry › Pick a cover on the entry, saved at
/// once. With no cover (Cover, larger: no cover yet) the placeholder, "No
/// cover yet." and Add a cover. [title] names a row that is not the entry
/// itself: a rated track on its album.
///
/// A long press on a row or a tile in any list opens it, and so does a tap
/// on the cover in details. Nothing opens a picker from a long press.
Future<void> showLargerCover(
  BuildContext context,
  Entry entry, {
  String? title,
}) async {
  final subject = await _show<CoverSubject>(
    context,
    _LargerEntryCover(entry: entry, title: title),
  );
  if (subject == null || !context.mounted) return;
  await showCoverPicker(context, subject: subject, onPicked: (_) {});
}

/// Opens Library › Cover, larger: a series for [group]: the cover that
/// stands for the series, its name, "4 movies · 2008–2024" and Choose
/// series cover, which opens the covers of the parts in the library on top
/// (Cover, larger: choose the series cover); a tap on one makes it the
/// series cover and comes back here.
Future<void> showLargerSeriesCover(BuildContext context, SeriesGroup group) =>
    _show<void>(context, _LargerSeriesCover(group: group));

/// Opens Library › Cover, larger: an artist for the artist called [name]:
/// what the artist shows, round, the name, [subtitle] ("7 albums, 2 songs")
/// and Change photo, which closes the view and opens Music › Pick a photo.
/// For an artist with no file of their own it says so and the button reads
/// "Add a photo".
Future<void> showLargerArtistPhoto(
  BuildContext context, {
  required String name,
  String? subtitle,
}) async {
  final change = await _show<bool>(
    context,
    _LargerArtistPhoto(name: name, subtitle: subtitle),
  );
  if (change == true && context.mounted) {
    await showArtistPhotoPicker(context, name: name);
  }
}

/// The same for an artist of the list.
Future<void> showLargerArtist(BuildContext context, ArtistSummary artist) =>
    showLargerArtistPhoto(
      context,
      name: artist.name,
      subtitle: artist.countLabel,
    );

/// On the root navigator, over the floating navigation. The view is dark
/// in every theme, and so is what it lies on.
Future<T?> _show<T>(BuildContext context, Widget view) => showDialog<T>(
  context: context,
  useRootNavigator: true,
  useSafeArea: false,
  barrierColor: LibraryColors.dark.scrim.withValues(alpha: 0.9),
  builder: (_) => view,
);

class _LargerEntryCover extends ConsumerStatefulWidget {
  const _LargerEntryCover({required this.entry, this.title});

  final Entry entry;
  final String? title;

  @override
  ConsumerState<_LargerEntryCover> createState() => _LargerEntryCoverState();
}

class _LargerEntryCoverState extends ConsumerState<_LargerEntryCover> {
  /// Whether the entry has a cover; null until the lookup has said.
  bool? _cover;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).value;
    // The entry as it is now: a cover picked meanwhile is the one shown.
    final entry = library?.entryById(widget.entry.id) ?? widget.entry;
    final none = _cover == false;
    return LargerCoverView(
      label: 'Cover',
      shape: entry.type == MediaType.music
          ? LargerCoverShape.square
          : LargerCoverShape.poster,
      cover: (width) => CoverImage(
        entry: entry,
        width: width,
        large: true,
        radius: LargerCoverView.coverRadius,
        text: CoverPlaceholderText.title,
        placeholderTitle: widget.title,
        onCover: (cover) {
          if (mounted && cover != _cover) setState(() => _cover = cover);
        },
      ),
      name: widget.title ?? entry.title,
      subtitle: entrySubtitle(entry),
      note: none ? 'No cover yet.' : null,
      button: none ? 'Add a cover' : 'Change cover',
      onButton: () => Navigator.pop(
        context,
        library == null
            ? CoverSubject.saved(entry)
            : CoverSubject.of(library, entry),
      ),
    );
  }
}

class _LargerSeriesCover extends ConsumerWidget {
  const _LargerSeriesCover({required this.group});

  final SeriesGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider).value;
    // The parts as they are now, so a cover just chosen is the one shown.
    final parts = [
      for (final part in group.parts) library?.entryById(part.id) ?? part,
    ];
    final cover = seriesCoverEntry(parts);
    return LargerCoverView(
      label: 'Series cover',
      shape: group.type == MediaType.music
          ? LargerCoverShape.square
          : LargerCoverShape.poster,
      cover: (width) => CoverImage(
        // A new part is a new cover, looked up afresh.
        key: ValueKey(cover.id),
        entry: cover,
        width: width,
        large: true,
        radius: LargerCoverView.coverRadius,
        text: CoverPlaceholderText.title,
        placeholderTitle: group.title,
      ),
      name: group.title,
      subtitle: group.subtitle,
      button: 'Choose series cover',
      onButton: () => showSeriesCoverSheet(
        context,
        seriesName: group.title,
        parts: parts,
        pickAtOnce: true,
      ),
    );
  }
}

class _LargerArtistPhoto extends ConsumerStatefulWidget {
  const _LargerArtistPhoto({required this.name, this.subtitle});

  final String name;
  final String? subtitle;

  @override
  ConsumerState<_LargerArtistPhoto> createState() => _LargerArtistPhotoState();
}

class _LargerArtistPhotoState extends ConsumerState<_LargerArtistPhoto> {
  /// A cover from the library stands in for the photo.
  bool _cover = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final hasFile = ref.watch(
      artistPhotoFilesProvider.select(
        (files) => files.containsKey(artistSlug(name)),
      ),
    );
    return LargerCoverView(
      label: 'Artist photo',
      shape: LargerCoverShape.round,
      cover: (width) => ArtistPhoto(
        name: name,
        initials: artistInitials(name),
        size: width,
        large: true,
        initialsSize: width * 0.3,
        onCover: (cover) {
          if (mounted && cover != _cover) setState(() => _cover = cover);
        },
      ),
      name: name,
      subtitle: widget.subtitle,
      note: hasFile ? null : noArtistPhotoNote(cover: _cover),
      button: hasFile ? 'Change photo' : 'Add a photo',
      onButton: () => Navigator.pop(context, true),
    );
  }
}

/// The shape of what [LargerCoverView] shows, and how much of the screen's
/// width it takes (the canvas draws 260, 290 and 300 of 390).
enum LargerCoverShape {
  /// 2:3, a movie's, a show's, a book's, a game's or an anime's cover.
  poster(260 / 390, 2 / 3),

  /// An album's or a song's cover.
  square(290 / 390, 1),

  /// An artist's photo.
  round(300 / 390, 1);

  const LargerCoverShape(this.widthFactor, this.aspectRatio);

  final double widthFactor;

  /// Width over height.
  final double aspectRatio;
}

/// A cover or a photo seen large (Library › Cover, larger and its states):
/// the [cover], the [name], the second line ([subtitle]), a [note] such as
/// "No cover yet." and one [button] that says what it changes. Dark in
/// every theme. A tap outside, the close button, Back or a swipe down
/// closes it. One view for every type, for series and for artists.
class LargerCoverView extends ConsumerStatefulWidget {
  const LargerCoverView({
    super.key,
    required this.label,
    required this.shape,
    required this.cover,
    required this.name,
    this.subtitle,
    this.note,
    required this.button,
    required this.onButton,
  });

  /// What a screen reader calls the view: "Cover".
  final String label;
  final LargerCoverShape shape;

  /// The cover at the width the view gives it.
  final Widget Function(double width) cover;
  final String name;
  final String? subtitle;
  final String? note;
  final String button;
  final VoidCallback onButton;

  static const coverRadius = 16.0;

  @override
  ConsumerState<LargerCoverView> createState() => _LargerCoverViewState();
}

class _LargerCoverViewState extends ConsumerState<LargerCoverView> {
  /// How far a swipe down has pulled the view.
  double _pull = 0;
  bool _pulling = false;

  /// A pull this far, or a flick this fast, closes the view.
  static const _closeAfter = 90.0;
  static const _closeVelocity = 700.0;

  void _close() => Navigator.pop(context);

  void _endPull(DragEndDetails details) {
    if (_pull > _closeAfter ||
        (details.primaryVelocity ?? 0) > _closeVelocity) {
      _close();
      return;
    }
    setState(() {
      _pull = 0;
      _pulling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(
      displayPreferencesProvider.select((p) => p.accent),
    );
    return Theme(
      data: buildTheme(brightness: Brightness.dark, accent: accent),
      child: Builder(builder: _view),
    );
  }

  Widget _view(BuildContext context) {
    final theme = Theme.of(context);
    final lineStyle = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.normal,
      fontSize: 14,
      height: 1.45,
      color: LibraryColors.of(context).muted,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final lines = [
      widget.subtitle,
      widget.note,
    ].whereType<String>().where((line) => line.isNotEmpty).toList();
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: widget.label,
        // The whole screen takes the tap outside and the swipe down.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _close,
          onVerticalDragStart: (_) => setState(() => _pulling = true),
          onVerticalDragUpdate: (details) => setState(
            () => _pull = (_pull + details.delta.dy).clamp(0.0, 400.0),
          ),
          onVerticalDragEnd: _endPull,
          onVerticalDragCancel: () => setState(() {
            _pull = 0;
            _pulling = false;
          }),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Room for the name, the lines and the button under
                      // the cover, at the user's text size.
                      final below =
                          scaler.scale(32.0 + 21 * lines.length) + 18 + 18 + 48;
                      final width = [
                        constraints.maxWidth * widget.shape.widthFactor,
                        (constraints.maxHeight - below - 24) *
                            widget.shape.aspectRatio,
                      ].reduce((a, b) => a < b ? a : b).clamp(120.0, 400.0);
                      return AnimatedContainer(
                        duration: _pulling ? Duration.zero : AppMotion.slide,
                        curve: Curves.easeOut,
                        transform: Matrix4.translationValues(0, _pull, 0),
                        alignment: Alignment.center,
                        // A tap on the cover or the text is not a tap
                        // outside.
                        child: GestureDetector(
                          onTap: () {},
                          excludeFromSemantics: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.shape == LargerCoverShape.round)
                                widget.cover(width)
                              else
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      LargerCoverView.coverRadius,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.shadow
                                            .withValues(alpha: 0.5),
                                        blurRadius: 40,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: widget.cover(width),
                                ),
                              const SizedBox(height: 18),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  widget.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              for (final line in lines)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    0,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 330,
                                    ),
                                    child: Text(
                                      line,
                                      textAlign: TextAlign.center,
                                      style: lineStyle,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 18),
                              AppButton(
                                label: widget.button,
                                compact: true,
                                horizontalPadding: 22,
                                onPressed: widget.onButton,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: IconButton(
                    tooltip: 'Close',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _close,
                    icon: StrokeIcon(
                      AppIcons.close,
                      size: 24,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
