import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/images/artwork_providers.dart';
import '../data/images/artwork_resolver.dart';
import '../theme/app_theme.dart';
import 'cached_image.dart';
import 'cover_placeholder.dart';

/// An artist's round photo (Library › Music: artists, list with photos; Music:
/// artists, grid with photos; Music › Artist, with photos): a colored disc with
/// the initials until the photo has been found and fetched. Only built in the
/// photo views.
class ArtistPhoto extends ConsumerStatefulWidget {
  const ArtistPhoto({
    super.key,
    required this.name,
    required this.initials,
    required this.size,
    this.initialsSize,
  });

  final String name;
  final String initials;
  final double size;

  /// Defaults to a third of the disc; the grid (Library › Music: artists, grid
  /// with photos) uses a fixed 22.
  final double? initialsSize;

  @override
  ConsumerState<ArtistPhoto> createState() => _ArtistPhotoState();
}

class _ArtistPhotoState extends ConsumerState<ArtistPhoto> {
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
  void didUpdateWidget(ArtistPhoto old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      _url = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    _resolver.releaseArtist(widget.name);
    super.dispose();
  }

  void _resolve() {
    final resolver = _resolver;
    final name = widget.name;
    final cached = resolver.cachedArtistPhotoUrl(name);
    if (cached != null) {
      _url = cached;
      return;
    }
    resolver.artistPhotoUrl(name).then((url) {
      if (!mounted || url == null || widget.name != name) return;
      setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = LibraryColors.of(context).coverPlaceholders;
    final color =
        palette[CoverPlaceholder.paletteIndex(widget.name, palette.length)];
    final placeholder = Semantics(
      excludeSemantics: true,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          widget.initials,
          style: TextStyle(
            fontSize: widget.initialsSize ?? widget.size * 0.34,
            fontWeight: FontWeight.w700,
            color: const Color(0xCCFFFFFF),
          ),
        ),
      ),
    );
    return CachedImage(
      url: _url,
      width: widget.size,
      height: widget.size,
      placeholder: placeholder,
      shape: BoxShape.circle,
    );
  }
}
