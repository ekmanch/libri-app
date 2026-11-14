import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/covers/cover_files.dart';
import '../data/images/artwork_providers.dart';
import '../data/images/artwork_resolver.dart';
import '../data/library_providers.dart';
import '../data/models/entry.dart';
import '../data/models/entry_kind.dart';
import 'cached_image.dart';
import 'cover_placeholder.dart';

/// An entry's cover (Library › Movies, list with covers; Movies, grid with
/// covers; Entry details and the rest): the placeholder until the cover has
/// been found and fetched, then the image. Only built in the photo views, so a
/// text view fetches nothing. [labeled] gives the image the title as its screen
/// reader name, for the details header. [placeholder] replaces the lettered
/// [CoverPlaceholder] (a [CoverTile] on Library › Home and Library › Coming
/// soon: list with covers).
class CoverImage extends ConsumerStatefulWidget {
  const CoverImage({
    super.key,
    required this.entry,
    required this.width,
    this.fontSize = 7,
    this.labeled = false,
    this.placeholder,
  });

  final Entry entry;
  final double width;
  final double fontSize;
  final bool labeled;
  final Widget? placeholder;

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
      return;
    }
    resolver.coverUrl(entry).then((url) {
      if (!mounted || url == null || _shown.id != entry.id) return;
      setState(() => _url = url);
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
    final placeholder =
        widget.placeholder ??
        CoverPlaceholder(
          entry: entry,
          width: widget.width,
          fontSize: widget.fontSize,
        );
    return CachedImage(
      url: _url,
      width: widget.width,
      height: widget.width / CoverPlaceholder.aspectRatio(entry.type),
      placeholder: placeholder,
      borderRadius: BorderRadius.circular(8),
      semanticLabel: widget.labeled ? entry.title : null,
    );
  }
}
