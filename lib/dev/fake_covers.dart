import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../data/covers/cover_files.dart';
import '../data/covers/cover_picture.dart';
import '../data/covers/cover_sources.dart';
import '../data/covers/cover_store.dart';
import '../data/github/git_blob.dart';
import '../data/github/github_api.dart';
import 'fake_images.dart';

/// The library repo's `covers/` folder in memory, for the widget tests and
/// the screenshot walks: no network, and every save and removal recorded.
class FakeCoverRemote implements CoverRemote {
  FakeCoverRemote([Map<String, Uint8List>? files]) : files = {...?files};

  final Map<String, Uint8List> files;

  /// Every save and removal, in order: "PUT movies/a.jpg", "DELETE …".
  final writes = <String>[];

  @override
  Future<List<CoverFile>> list() async => [
    for (final MapEntry(:key, :value) in files.entries)
      CoverFile(path: key, size: value.length, sha: gitBlobSha(value)),
  ];

  @override
  Future<Uint8List> download(String path) async {
    final bytes = files[path];
    if (bytes == null) {
      throw const GitHubException(GitHubFailure.notFound, status: 404);
    }
    return bytes;
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    required String message,
    String? sha,
  }) async {
    writes.add('PUT $path');
    files[path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(
    String path, {
    required String sha,
    required String message,
  }) async {
    writes.add('DELETE $path');
    files.remove(path);
  }
}

/// The cover files of the mockups (Settings › Your covers: review, Add /
/// edit entry › Pick a cover: with your own cover), drawn on the spot: a
/// cover of [yours] entries' own, named after their ids, and three files
/// that no title uses.
Map<String, Uint8List> demoCoverFiles({
  Iterable<String> yours = const [],
  bool unused = true,
}) => {
  for (final id in yours)
    '${coverIdFolder(id)}/${coverUploadName(coverSlug(id), gitBlobSha(id.codeUnits))}':
        fakeCoverPng('yours-$id', square: coverIdFolder(id) == 'music'),
  if (unused) ...{
    'movies/old-poster.png': fakeCoverPng('old-poster'),
    'movies/gatto-2027.a3f9c2e.jpg': fakeCoverPng('gatto'),
    'music/dirt-deluxe-alice-in-chains.91be04c.jpg': fakeCoverPng(
      'dirt-deluxe',
      square: true,
    ),
  },
};

/// The path [demoCoverFiles] gives the cover of the entry with [id].
String demoCoverPath(String id) =>
    '${coverIdFolder(id)}/${coverUploadName(coverSlug(id), gitBlobSha(id.codeUnits))}';

/// A store over a [FakeCoverRemote] holding [files]. With a [directory]
/// the copies are kept there and the covers draw (the walks); without one
/// nothing touches the disk (the widget tests) and a cover is its
/// placeholder. Call [CoverStore.refresh] before it is shown.
CoverStore fakeCoverStore({
  Map<String, Uint8List>? files,
  Directory? directory,
}) => CoverStore(directory: directory, remote: FakeCoverRemote(files));

/// [CoverPictures] without a decoder: every file is an image of [size]
/// unless it is empty or [notAnImage], and the "JPEG" is the file itself.
class FakeCoverPictures implements CoverPictures {
  FakeCoverPictures({this.size = (1000, 1500), this.notAnImage = false});

  (int, int) size;
  bool notAnImage;

  /// Where Fit your cover left the frame, for each fitted image.
  final fitted = <double>[];

  @override
  Future<(int, int)> sizeOf(Uint8List bytes) async {
    if (notAnImage || bytes.isEmpty) throw const CoverPictureException();
    return size;
  }

  @override
  Future<PreparedCover> prepare(Uint8List bytes) async => PreparedCover(
    bytes: bytes,
    width: size.$1,
    height: size.$2,
    sha: gitBlobSha(bytes),
  );

  @override
  Future<PreparedCover> fit(
    Uint8List bytes, {
    required double at,
    required bool square,
  }) async {
    fitted.add(at);
    final (width, height) = coverFittedSize(size.$1, size.$2, square: square);
    return PreparedCover(
      bytes: bytes,
      width: width,
      height: height,
      sha: gitBlobSha(bytes),
    );
  }
}

/// [CoverSources] that hand over what they were given. With a [gate] the
/// read waits for it, so "Reading…" shows.
class FakeCoverSources implements CoverSources {
  FakeCoverSources({this.photo, this.file, this.clipboard, this.gate});

  Uint8List? photo;
  Uint8List? file;

  /// The image on the clipboard; Paste image is only listed with one.
  Uint8List? clipboard;
  Completer<void>? gate;

  Future<Uint8List?> _after(Uint8List? bytes) async {
    await gate?.future;
    return bytes;
  }

  @override
  Future<Uint8List?> fromPhotos() => _after(photo);

  @override
  Future<Uint8List?> fromFiles() => _after(file);

  @override
  Future<bool> clipboardHasImage() async => clipboard != null;

  @override
  Future<Uint8List?> fromClipboard() => _after(clipboard);
}
