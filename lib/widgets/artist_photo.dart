import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/covers/artist_photos.dart';
import '../data/covers/cover_files.dart';
import '../data/images/artwork_providers.dart';
import '../data/images/artwork_resolver.dart';
import '../data/library_providers.dart';
import '../data/models/entry.dart';
import '../data/models/entry_kind.dart';
import '../theme/app_theme.dart';
import 'cached_image.dart';
import 'cover_placeholder.dart';

/// An artist's round photo (Library › Music: artists, list with photos; Music:
/// artists, grid with photos; Music › Artist, text view and with photos): the
/// artist's file in the library repo, `covers/artists/<slug>.jpg`; without one
/// a cover from the library, the artist's albums most recently added first and
/// then their songs; else a colored disc with the initials (DESIGN.md section
/// 10e). An artist whose file is listed but not on this phone yet shows the
/// initials, not a cover the photo would then replace. Nothing is looked up
/// for the photo here: the music source's own artist photos are no longer
/// used.
class ArtistPhoto extends ConsumerStatefulWidget {
  const ArtistPhoto({
    super.key,
    required this.name,
    required this.initials,
    required this.size,
    this.initialsSize,
    this.borderRadius,
    this.onCover,
  });

  final String name;
  final String initials;
  final double size;

  /// Told whether a cover from the library stands in for the photo, once
  /// that is known and when it changes (Music › Artist photo, larger says
  /// so). Never called during a build.
  final ValueChanged<bool>? onCover;

  /// Defaults to a third of the disc; the grid (Library › Music: artists, grid
  /// with photos) uses a fixed 22.
  final double? initialsSize;

  /// Square with these corners instead of round (Music › Artist photo,
  /// larger).
  final BorderRadius? borderRadius;

  @override
  ConsumerState<ArtistPhoto> createState() => _ArtistPhotoState();
}

class _ArtistPhotoState extends ConsumerState<ArtistPhoto> {
  /// The library cover shown while the artist has no file.
  String? _coverUrl;

  /// The ids of the entries the cover was looked for among.
  List<String> _asked = const [];
  int _run = 0;
  String? _waitingFor;

  // Kept for dispose, where ref may not be used.
  late final ArtworkResolver _resolver;

  @override
  void initState() {
    super.initState();
    _resolver = ref.read(artworkResolverProvider);
  }

  @override
  void didUpdateWidget(ArtistPhoto old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      _coverUrl = null;
      _asked = const [];
      _release();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  void _release() {
    _run++;
    if (_waitingFor case final id?) _resolver.release(id);
    _waitingFor = null;
  }

  /// The entry whose cover an entry shows: a song's album while it is in
  /// the library with one of the owner's own covers, else the entry.
  Entry _shown(Entry entry) {
    if (entry.kind != EntryKind.song || isRepoCover(entry.coverFrom)) {
      return entry;
    }
    final library = ref.read(libraryProvider).value;
    if (library == null) return entry;
    final owner = coverOwner(library, entry);
    return isRepoCover(owner.coverFrom) ? owner : entry;
  }

  /// The first of [entries] that has a cover, asked best first up to the
  /// first that has one.
  Future<void> _findCover(List<Entry> entries) async {
    _release();
    final run = _run;
    for (final entry in entries) {
      final shown = _shown(entry);
      var url = _resolver.cachedCoverUrl(shown);
      if (url == null) {
        _waitingFor = shown.id;
        url = await _resolver.coverUrl(shown);
        if (!mounted || run != _run) return;
        _waitingFor = null;
      }
      if (url != null) {
        if (url != _coverUrl) setState(() => _coverUrl = url);
        widget.onCover?.call(true);
        return;
      }
    }
    if (_coverUrl != null) setState(() => _coverUrl = null);
    widget.onCover?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final square = widget.borderRadius != null;
    final placeholder = ArtistInitials(
      name: widget.name,
      initials: widget.initials,
      size: widget.size,
      initialsSize: widget.initialsSize,
      borderRadius: widget.borderRadius,
    );
    final file = ref.watch(
      artistPhotoFilesProvider.select(
        (files) => files[artistSlug(widget.name)],
      ),
    );
    final String? url;
    final Key key;
    if (file != null) {
      _release();
      url = file.coverFrom;
      // A replaced photo keeps its name: the blob tells them apart.
      key = ValueKey('${file.path}@${file.sha}');
    } else {
      final entries =
          ref.watch(
            artistCoverEntriesProvider.select(
              (saved) => saved[artistCoverKey(widget.name)],
            ),
          ) ??
          const <Entry>[];
      final ids = [
        for (final entry in entries) '${entry.id}|${entry.coverFrom ?? ''}',
      ];
      if (!_sameIds(ids, _asked)) {
        _asked = ids;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _findCover(entries);
        });
      }
      url = _coverUrl;
      key = ValueKey('cover:$url');
    }
    return CachedImage(
      key: key,
      url: url,
      width: widget.size,
      height: widget.size,
      placeholder: placeholder,
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: widget.borderRadius,
    );
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Up to two initials for an artist's disc: "AC" for Alice in Chains.
String artistInitials(String name) {
  final words = name
      .replaceAll('&', '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  return (words[0][0] + (words.length > 1 ? words[1][0] : '')).toUpperCase();
}

/// The colored disc with an artist's initials: what an artist shows with
/// no photo and no cover, and under a photo until it is drawn.
class ArtistInitials extends StatelessWidget {
  const ArtistInitials({
    super.key,
    required this.name,
    required this.initials,
    required this.size,
    this.initialsSize,
    this.borderRadius,
  });

  final String name;
  final String initials;
  final double size;
  final double? initialsSize;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = LibraryColors.of(context).coverPlaceholders;
    final color = palette[CoverPlaceholder.paletteIndex(name, palette.length)];
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: initialsSize ?? size * 0.34,
            fontWeight: FontWeight.w700,
            color: const Color(0xCCFFFFFF),
          ),
        ),
      ),
    );
  }
}
