import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/images/artwork_providers.dart';
import '../data/images/large_cover_providers.dart';
import '../theme/app_theme.dart';

/// An image from the device cache, downloaded first when needed, with
/// [placeholder] until it is on the device and decoded. The file is
/// decoded at the shown width, and a fresh download fades in. A null
/// [url] is the placeholder for good.
///
/// With a [largeUrl] (Library › Cover, larger and the cover in details) the
/// larger version is drawn over it: at once when it is on the device, else
/// fetched now, on any connection and ahead of the background pass, and
/// faded in over the image the lists show. When that fails, or the phone
/// is offline, the smaller image stays and nothing is said.
///
/// Every cover, artist photo and album tile is one of these, so this is
/// where the light theme lifts them off the page: the theme's cover shadow
/// behind the image or its placeholder, the small one for the covers in
/// lists ([LibraryColors.coverShadowFor]). [lifted] false leaves it out.
class CachedImage extends ConsumerStatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    this.largeUrl,
    required this.width,
    required this.height,
    required this.placeholder,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.semanticLabel,
    this.lifted = true,
  });

  /// Whether the theme's cover shadow is drawn behind it.
  final bool lifted;

  final String? url;

  /// The same image at a larger size (`largeCoverUrl`), when it is wanted
  /// and the source has one.
  final String? largeUrl;
  final double width;
  final double height;
  final Widget placeholder;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  /// The screen reader's name for the image; without one the image is
  /// skipped (the row around it names the title).
  final String? semanticLabel;

  static const fadeIn = Duration(milliseconds: 200);

  @override
  ConsumerState<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends ConsumerState<CachedImage> {
  File? _file;
  bool _fresh = false;
  int _request = 0;
  File? _largeFile;
  int _largeRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLarge();
  }

  @override
  void didUpdateWidget(CachedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _fresh = false;
      _load();
    }
    if (old.largeUrl != widget.largeUrl) {
      _largeFile = null;
      _largeRequest++;
      _loadLarge();
    }
  }

  void _loadLarge() {
    final url = widget.largeUrl;
    if (url == null) return;
    final cache = ref.read(largeImageCacheProvider);
    final cached = cache.cachedFile(url);
    if (cached != null) {
      _largeFile = cached;
      return;
    }
    final id = ++_largeRequest;
    // Asked every time it is opened: a failure earlier is not held
    // against it.
    cache.get(url, retry: true).then((image) {
      if (!mounted || id != _largeRequest || image == null) return;
      if (image.downloadedNow) {
        PaintingBinding.instance.imageCache.evict(FileImage(image.file));
      }
      setState(() => _largeFile = image.file);
    });
  }

  void _load() {
    final url = widget.url;
    if (url == null) return;
    final cache = ref.read(imageCacheProvider);
    final cached = cache.cachedFile(url);
    if (cached != null) {
      _file = cached;
      return;
    }
    final id = ++_request;
    cache.get(url).then((image) {
      if (!mounted || id != _request || image == null) return;
      if (image.downloadedNow) {
        // The path may have been decoded before (a replaced file).
        PaintingBinding.instance.imageCache.evict(FileImage(image.file));
      }
      setState(() {
        _file = image.file;
        _fresh = image.downloadedNow;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final shadow = widget.lifted
        ? LibraryColors.of(context).coverShadowFor(widget.width)
        : const <BoxShadow>[];
    if (shadow.isEmpty) return _picture(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.circle
            ? null
            : widget.borderRadius,
        boxShadow: shadow,
      ),
      child: _picture(context),
    );
  }

  Widget _picture(BuildContext context) {
    final file = _file;
    final largeFile = _largeFile;
    final placeholder = SizedBox(
      width: widget.width,
      height: widget.height,
      child: widget.placeholder,
    );
    if (file == null && largeFile == null) return placeholder;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final Widget small = file == null
        ? placeholder
        : _image(file, ratio, placeholder);
    final image = largeFile == null
        ? small
        : Stack(
            children: [
              small,
              // Nothing until it is decoded, then faded in over the
              // smaller image, which stays if this one cannot be drawn.
              Image.file(
                largeFile,
                key: ValueKey(largeFile.path),
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                cacheWidth: (widget.width * ratio).round(),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                frameBuilder: (context, child, frame, loadedAtOnce) {
                  if (frame == null) return const SizedBox.shrink();
                  if (loadedAtOnce) return child;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: CachedImage.fadeIn,
                    builder: (_, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: child,
                  );
                },
              ),
            ],
          );
    return switch (widget.shape) {
      BoxShape.circle => ClipOval(child: image),
      BoxShape.rectangle => ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
        child: image,
      ),
    };
  }

  /// The image the lists show.
  Widget _image(File file, double ratio, Widget placeholder) {
    return Image.file(
      file,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      cacheWidth: (widget.width * ratio).round(),
      gaplessPlayback: true,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.semanticLabel == null,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (context, child, frame, loadedAtOnce) {
        if (frame == null) return placeholder;
        if (loadedAtOnce || !_fresh) return child;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: CachedImage.fadeIn,
          builder: (_, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: child,
        );
      },
    );
  }
}
