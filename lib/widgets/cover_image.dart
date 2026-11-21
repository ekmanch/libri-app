import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/covers/cover_files.dart';
import '../data/images/artwork_providers.dart';
import '../data/images/artwork_resolver.dart';
import '../data/images/large_cover.dart';
import '../data/models/media_type.dart';
import '../data/library_providers.dart';
import '../data/models/entry.dart';
import '../data/models/entry_kind.dart';
import 'cached_image.dart';
import 'cover_placeholder.dart';

/// An entry's cover (Library › Movies, list with covers; Movies, grid with
/// covers; Entry details and the rest): the placeholder until the cover has
/// been found and fetched, then the image. Only built in the photo views, so a
/// text view fetches nothing. [labeled] gives the image the title as its screen
/// reader name, for the details header.
class CoverImage extends ConsumerStatefulWidget {
  const CoverImage({
    super.key,
    required this.entry,
    required this.width,
    this.labeled = false,
    this.text = CoverPlaceholderText.none,
    this.placeholderTitle,
    this.badgeBelow = false,
    this.radius = 8,
    this.onCover,
    this.large = false,
  });

  /// Whether the larger version of the cover is shown where the source
  /// has one (Library › Cover, larger and the cover in details), fetched
  /// now when it is not on the phone yet. The lists never ask for it.
  final bool large;

  final Entry entry;
  final double width;
  final bool labeled;

  /// What the placeholder writes on itself: nothing for a small cover.
  final CoverPlaceholderText text;

  /// The title on the placeholder when it is not the entry's own (a
  /// series tile).
  final String? placeholderTitle;

  /// Whether a series badge sits on the cover's bottom-left corner.
  final bool badgeBelow;

  /// The corners: 8, and 16 on the larger cover.
  final double radius;

  /// Told whether the entry has a cover, once that is known and when it
  /// changes (the larger cover says "No cover yet."). Never called during
  /// a build.
  final ValueChanged<bool>? onCover;

  @override
  ConsumerState<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends ConsumerState<CoverImage> {
  String? _url;

  // Kept for dispose, where ref may not be used.
  late final ArtworkResolver _resolver;

  @override
  void initState() {
    super.initState();
    _resolver = ref.read(artworkResolverProvider);
    _resolve();
  }

  @override
  void didUpdateWidget(CoverImage old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id ||
        old.entry.source != widget.entry.source ||
        old.entry.coverFrom != widget.entry.coverFrom ||
        old.entry.title != widget.entry.title) {
      _url = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    _resolver.release(widget.entry.id);
    super.dispose();
  }

  /// The entry whose cover is shown: a song's album while the album is in
  /// the library and shows one of the owner's own covers (DESIGN.md
  /// section 10d), else the entry itself, whose lookup finds the album's
  /// cover anyway.
  Entry get _shown {
    final entry = widget.entry;
    if (entry.kind != EntryKind.song || isRepoCover(entry.coverFrom)) {
      return entry;
    }
    final library = ref.read(libraryProvider).value;
    if (library == null) return entry;
    final owner = coverOwner(library, entry);
    return isRepoCover(owner.coverFrom) ? owner : entry;
  }

  void _resolve() {
    final resolver = _resolver;
    final entry = _shown;
    final cached = resolver.cachedCoverUrl(entry);
    if (cached != null) {
      _url = cached;
      if (widget.onCover != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCover?.call(true);
        });
      }
      return;
    }
    resolver.coverUrl(entry).then((url) {
      if (!mounted || _shown.id != entry.id) return;
      widget.onCover?.call(url != null);
      if (url != null) setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    if (entry.kind == EntryKind.song) {
      // The album's own cover changing changes the song's.
      ref.listen(
        libraryProvider.select((library) {
          final value = library.value;
          return value == null ? null : coverOwner(value, entry).coverFrom;
        }),
        (before, after) {
          if (before == after) return;
          setState(() {
            _url = null;
            _resolve();
          });
        },
      );
    }
    final placeholder = CoverPlaceholder.of(
      entry,
      width: widget.width,
      title: widget.placeholderTitle,
      text: widget.text,
      badgeBelow: widget.badgeBelow,
    );
    final url = _url;
    return CachedImage(
      url: url,
      largeUrl: widget.large && url != null
          ? largeCoverUrl(url, square: entry.type == MediaType.music)
          : null,
      width: widget.width,
      height: widget.width / CoverPlaceholder.aspectRatio(entry.type),
      placeholder: placeholder,
      borderRadius: BorderRadius.circular(widget.radius),
      semanticLabel: widget.labeled ? entry.title : null,
    );
  }
}
