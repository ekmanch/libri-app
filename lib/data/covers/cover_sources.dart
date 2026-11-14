import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Where an uploaded cover comes from (Add / edit entry › Pick a cover:
/// upload from): the photo library, the files, or an image on the
/// clipboard. Each gives the file's bytes as they are, or null when
/// nothing was picked. The tests and the walks stand in for it.
abstract interface class CoverSources {
  Future<Uint8List?> fromPhotos();
  Future<Uint8List?> fromFiles();

  /// Whether the clipboard holds an image right now: Paste image is only
  /// listed then.
  Future<bool> clipboardHasImage();
  Future<Uint8List?> fromClipboard();
}

/// [CoverSources] on the phone: the system photo picker (`image_picker`),
/// the system file picker (`file_selector`) and, for the clipboard, a
/// channel of the app's own in `MainActivity.kt`, since Flutter's
/// clipboard is text only. Elsewhere the clipboard never holds an image.
class PlatformCoverSources implements CoverSources {
  const PlatformCoverSources();

  static const _clipboard = MethodChannel('libri/clipboard');

  @override
  Future<Uint8List?> fromPhotos() async {
    // No size or quality is asked for: the picker then hands over the
    // photo as it is, and the app scales it itself.
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    return picked?.readAsBytes();
  }

  @override
  Future<Uint8List?> fromFiles() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          mimeTypes: ['image/*'],
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'avif'],
        ),
      ],
    );
    return picked?.readAsBytes();
  }

  @override
  Future<bool> clipboardHasImage() async {
    try {
      return await _clipboard.invokeMethod<bool>('hasImage') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Uint8List?> fromClipboard() async {
    try {
      return await _clipboard.invokeMethod<Uint8List>('readImage');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
