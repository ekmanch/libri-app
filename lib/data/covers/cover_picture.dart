import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../github/git_blob.dart';
import 'cover_files.dart';

/// The image work behind an upload, as the desktop does it (DESIGN.md
/// section 10d): the picked image is decoded upright, scaled so its
/// longer side is at most [coverUploadSide] and saved as JPEG on white.
/// Fit your cover keeps the largest frame of the type's shape (2:3, 1:1
/// for music), placed along the image's long side. Files committed by
/// hand never come through here.
///
/// Flutter's own decoder reads the image (so a HEIC photo works on the
/// phone) and scales it; the `image` package only writes the JPEG, which
/// Flutter cannot.

/// The file is not an image the phone can read.
class CoverPictureException implements Exception {
  const CoverPictureException();

  @override
  String toString() => 'CoverPictureException';
}

/// An image ready to be stored: the JPEG, its size and git's blob sha.
class PreparedCover {
  const PreparedCover({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sha,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String sha;
}

/// The largest frame of the type's shape inside an image of [width] ×
/// [height], placed [at] (0 to 1) along the side with room to spare:
/// left, top, width, height.
({int x, int y, int width, int height}) coverCropFrame(
  int width,
  int height, {
  required bool square,
  required double at,
}) {
  final target = square ? 1.0 : 2 / 3;
  final t = at.clamp(0.0, 1.0);
  if (width / (height < 1 ? 1 : height) > target) {
    // Wider than the shape: the frame keeps the height and slides
    // sideways.
    final w = (height * target).round().clamp(1, width);
    return (x: ((width - w) * t).round(), y: 0, width: w, height: height);
  }
  final h = (width / target).round().clamp(1, height < 1 ? 1 : height);
  final spare = height - h < 0 ? 0 : height - h;
  return (x: 0, y: (spare * t).round(), width: width, height: h);
}

/// [width] × [height] scaled down to fit in [maxWidth] × [maxHeight],
/// never up.
(int, int) _within(int width, int height, int maxWidth, int maxHeight) {
  var scale = maxWidth / (width < 1 ? 1 : width);
  final other = maxHeight / (height < 1 ? 1 : height);
  if (other < scale) scale = other;
  if (scale > 1) scale = 1;
  final w = (width * scale).round();
  final h = (height * scale).round();
  return (w < 1 ? 1 : w, h < 1 ? 1 : h);
}

/// The size Fit your cover saves an image of [width] × [height] at:
/// "Saved at 1333 × 2000.": its longer side is at most [coverUploadSide].
(int, int) coverFittedSize(int width, int height, {required bool square}) {
  final frame = coverCropFrame(width, height, square: square, at: 0.5);
  return _within(frame.width, frame.height, coverUploadSide, coverUploadSide);
}

/// Decodes, scales and encodes images. An interface so the tests and the
/// walks can stand in for it without a real image.
abstract interface class CoverPictures {
  /// The width and height of the image in [bytes], upright. Throws
  /// [CoverPictureException] when it is not an image.
  Future<(int, int)> sizeOf(Uint8List bytes);

  /// An upload: the image scaled so its longer side is at most
  /// [coverUploadSide], as JPEG.
  Future<PreparedCover> prepare(Uint8List bytes);

  /// Fit your cover: the image cropped to the type's shape with the frame
  /// [at] along its long side.
  Future<PreparedCover> fit(
    Uint8List bytes, {
    required double at,
    required bool square,
  });
}

/// [CoverPictures] with Flutter's decoder and the `image` JPEG encoder.
class EngineCoverPictures implements CoverPictures {
  const EngineCoverPictures();

  static Future<ui.Image> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        if (image.width == 0 || image.height == 0) {
          image.dispose();
          throw const CoverPictureException();
        }
        return image;
      } finally {
        codec.dispose();
      }
    } on CoverPictureException {
      rethrow;
    } on Object {
      throw const CoverPictureException();
    }
  }

  @override
  Future<(int, int)> sizeOf(Uint8List bytes) async {
    final image = await _decode(bytes);
    final size = (image.width, image.height);
    image.dispose();
    return size;
  }

  @override
  Future<PreparedCover> prepare(Uint8List bytes) async {
    final image = await _decode(bytes);
    final (w, h) = _within(
      image.width,
      image.height,
      coverUploadSide,
      coverUploadSide,
    );
    return _encode(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      w,
      h,
    );
  }

  @override
  Future<PreparedCover> fit(
    Uint8List bytes, {
    required double at,
    required bool square,
  }) async {
    final image = await _decode(bytes);
    final frame = coverCropFrame(
      image.width,
      image.height,
      square: square,
      at: at,
    );
    final (w, h) = coverFittedSize(image.width, image.height, square: square);
    return _encode(
      image,
      ui.Rect.fromLTWH(
        frame.x.toDouble(),
        frame.y.toDouble(),
        frame.width.toDouble(),
        frame.height.toDouble(),
      ),
      w,
      h,
    );
  }

  /// The part [source] of [image] at [width] × [height], on white where
  /// it was see-through, as JPEG. Disposes [image].
  static Future<PreparedCover> _encode(
    ui.Image image,
    ui.Rect source,
    int width,
    int height,
  ) async {
    final recorder = ui.PictureRecorder();
    final target = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    ui.Canvas(recorder, target)
      ..drawRect(target, ui.Paint()..color = const ui.Color(0xFFFFFFFF))
      ..drawImageRect(
        image,
        source,
        target,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
    final picture = recorder.endRecording();
    final ui.Image scaled;
    try {
      scaled = await picture.toImage(width, height);
    } finally {
      picture.dispose();
      image.dispose();
    }
    final ByteData? data;
    try {
      data = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      scaled.dispose();
    }
    if (data == null) throw const CoverPictureException();
    final jpeg = await compute(_jpeg, (
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width,
      height,
    ));
    return PreparedCover(
      bytes: jpeg,
      width: width,
      height: height,
      sha: gitBlobSha(jpeg),
    );
  }
}

Uint8List _jpeg((Uint8List, int, int) job) {
  final (rgba, width, height) = job;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: coverUploadQuality);
}
