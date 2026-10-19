import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/images/artwork_providers.dart';
import '../data/images/artwork_resolver.dart';
import '../data/models/entry.dart';
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
    this.fontSize = 7,
    this.labeled = false,
  });

  final Entry entry;
  final double width;
  final double fontSize;
  final bool labeled;

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

  void _resolve() {
    final resolver = _resolver;
    final entry = widget.entry;
    final cached = resolver.cachedCoverUrl(entry);
    if (cached != null) {
      _url = cached;
      return;
    }
    resolver.coverUrl(entry).then((url) {
      if (!mounted || url == null || widget.entry.id != entry.id) return;
      setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final placeholder = CoverPlaceholder(
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
