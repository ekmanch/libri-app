import '../models/entry.dart';
import '../models/entry_kind.dart';
import '../models/library.dart';
import '../models/media_type.dart';

/// The owner's own covers: the rules both apps share (DESIGN.md section
/// 10d, the desktop's "Your own covers"). They must never differ from the
/// desktop's, which reads and writes the same folders.
///
/// The files live in `covers/<type>/` beside the library file, the type
/// folders named as entry ids name the types (movies, shows, books, games,
/// anime, music), everything in lower case. A file is named
/// `<slug>[.<label>].<ext>`, the slug being the entry id without its
/// type; a slug has no dot, so a file belongs to a title when its name is
/// the slug followed by one. The name only makes a file a candidate: the
/// cover shown is the one `cover_from` names, "repo:" and the path under
/// `covers/`.

/// What a `cover_from` naming one of the owner's files starts with.
const repoCoverScheme = 'repo:';

/// The folder beside the library file.
const coversFolder = 'covers';

/// How long a listing is trusted before Pick a cover asks again.
const coverListingAge = Duration(minutes: 1);

/// The longer side of an upload, in pixels.
const coverUploadSide = 2000;

/// The JPEG quality of an upload.
const coverUploadQuality = 88;

/// How far from the type's shape (2:3, 1:1 for music) an image may be
/// before Fit your cover opens: a tenth.
const coverShapeTolerance = 0.10;

/// The type's folder under `covers/`: "movies", the type's name in entry
/// ids.
String coverFolder(MediaType type) => type.name;

/// The entry id without its type: `movies/the-mummy-1999` is
/// `the-mummy-1999`.
String coverSlug(String id) {
  final slash = id.indexOf('/');
  return slash < 0 ? id : id.substring(slash + 1);
}

/// The folder of the type the id was made for, which stays when the
/// entry's type changes: `movies/the-mummy-1999` is "movies".
String? coverIdFolder(String id) {
  final slash = id.indexOf('/');
  if (slash < 0) return null;
  final key = id.substring(0, slash);
  for (final type in MediaType.values) {
    if (type.name == key) return coverFolder(type);
  }
  return null;
}

/// The path under `covers/` a `cover_from` names, when it names one of
/// the owner's files.
String? repoCoverPath(String? coverFrom) =>
    coverFrom != null && coverFrom.startsWith(repoCoverScheme)
    ? coverFrom.substring(repoCoverScheme.length)
    : null;

/// Whether the `cover_from` names one of the owner's files.
bool isRepoCover(String? coverFrom) =>
    coverFrom != null && coverFrom.startsWith(repoCoverScheme);

/// The `cover_from` for the file at [path] under `covers/`.
String repoCoverFrom(String path) => '$repoCoverScheme$path';

/// "movies/the-mummy-1999.jpg" is ("movies", "the-mummy-1999.jpg"); a
/// file right under `covers/` has no folder.
(String folder, String name) splitCoverPath(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0
      ? ('', path)
      : (path.substring(0, slash), path.substring(slash + 1));
}

/// The slug a file name is for: all of it before the first dot.
String coverSlugOfName(String name) {
  final dot = name.indexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

/// Whether the file [name] belongs to the title with [slug]: the slug
/// followed by a dot.
bool coverBelongs(String name, String slug) =>
    slug.isNotEmpty && name.startsWith('$slug.');

/// The label between the slug and the extension, and the extension:
/// "the-mummy-1999.steelbook.jpg" is ("steelbook", "jpg"), and
/// "the-mummy-1999.jpg" is ("", "jpg").
(String label, String extension) coverLabelAndExtension(String name) {
  final dot = name.indexOf('.');
  final rest = dot < 0 ? '' : name.substring(dot + 1);
  final last = rest.lastIndexOf('.');
  return last < 0
      ? ('', rest)
      : (rest.substring(0, last), rest.substring(last + 1));
}

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

/// Whether the file is an image the apps draw, by its extension.
bool isCoverImage(String name) {
  final dot = name.lastIndexOf('.');
  return dot >= 0 &&
      _imageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// The name an upload gets: the slug, the first seven characters of the
/// file's git blob sha and "jpg", so two devices never pick the same name
/// for different images and a new image never hides behind a cached one.
/// All in lower case, like the folders.
String coverUploadName(String slug, String sha) =>
    '$slug.${sha.length > 7 ? sha.substring(0, 7) : sha}.jpg'.toLowerCase();

final _uploadLabel = RegExp(r'^[0-9a-f]{7}$');

/// Whether a label is the short sha of an upload from the apps.
bool isCoverUploadLabel(String label) => _uploadLabel.hasMatch(label);

/// The folder in the repo: `covers` beside the library file, so
/// `data/library.json` has `data/covers`.
String coversRoot(String libraryFile) {
  final slash = libraryFile.lastIndexOf('/');
  return slash <= 0
      ? coversFolder
      : '${libraryFile.substring(0, slash)}/$coversFolder';
}

/// "1.4 MB", "240 KB".
String coverSizeLabel(int bytes) => bytes >= 1000000
    ? '${(bytes / 1000000).toStringAsFixed(1)} MB'
    : '${((bytes + 999) ~/ 1000).clamp(1, 999)} KB';

/// Whether an image of [width] × [height] is close enough to the shape of
/// a cover ([square] for music, else upright 2:3) to be center-cropped
/// with no step of its own.
bool coverShapeFits(int width, int height, {required bool square}) {
  if (width <= 0 || height <= 0) return true;
  final wanted = square ? 1.0 : 2 / 3;
  final ratio = width / height;
  return (ratio / wanted - 1).abs() <= coverShapeTolerance;
}

/// One file under `covers/`: its path there
/// ("movies/the-mummy-1999.jpg"), its size and git's blob sha.
class CoverFile {
  const CoverFile({required this.path, required this.size, required this.sha});

  static CoverFile? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final path = json['path'];
    final size = json['size'];
    final sha = json['sha'];
    if (path is! String || sha is! String) return null;
    return CoverFile(
      path: path,
      size: size is num ? size.toInt() : 0,
      sha: sha,
    );
  }

  final String path;
  final int size;
  final String sha;

  String get folder => splitCoverPath(path).$1;
  String get name => splitCoverPath(path).$2;

  /// The label in the name, unless it is an upload's short sha:
  /// "steelbook", or null.
  String? get label {
    final label = coverLabelAndExtension(name).$1;
    return label.isEmpty || isCoverUploadLabel(label) ? null : label;
  }

  /// What `cover_from` holds for the file, and its key as an image.
  String get coverFrom => repoCoverFrom(path);

  Map<String, Object?> toJson() => {'path': path, 'size': size, 'sha': sha};

  @override
  bool operator ==(Object other) =>
      other is CoverFile &&
      other.path == path &&
      other.size == size &&
      other.sha == sha;

  @override
  int get hashCode => Object.hash(path, size, sha);

  @override
  String toString() => 'CoverFile($path, $size, $sha)';
}

String _norm(String? text) => (text ?? '').trim().toLowerCase();

/// The entry whose cover [entry] shows and changes: its album for a song
/// whose album is in the library (same artist, the album's title is the
/// song's `album`, as `albumOfSong` matches them), else itself.
Entry coverOwner(Library library, Entry entry) {
  if (entry.type != MediaType.music ||
      entry.kind != EntryKind.song ||
      _norm(entry.album).isEmpty ||
      _norm(entry.creator).isEmpty) {
    return entry;
  }
  for (final other in library.entries) {
    if (other.type == MediaType.music &&
        other.kind != EntryKind.song &&
        other.id != entry.id &&
        _norm(other.creator) == _norm(entry.creator) &&
        _norm(other.title) == _norm(entry.album)) {
      return other;
    }
  }
  return entry;
}

/// The files of [files] named after the entry with [id] of [type]: in
/// its type's folder and, after a type change, in the folder of the type
/// its id was made for.
List<CoverFile> coverCandidates(
  Iterable<CoverFile> files,
  MediaType type,
  String id,
) {
  final slug = coverSlug(id);
  final here = coverFolder(type);
  final before = coverIdFolder(id);
  return [
    for (final file in files)
      if ((file.folder == here || file.folder == before) &&
          isCoverImage(file.name) &&
          coverBelongs(file.name, slug))
        file,
  ];
}

/// Every "folder/slug" a file can be named after.
Set<String> _titleKeys(Library library) {
  final keys = <String>{};
  for (final entry in library.entries) {
    final slug = coverSlug(entry.id);
    keys.add('${coverFolder(entry.type)}/$slug');
    final before = coverIdFolder(entry.id);
    if (before != null) keys.add('$before/$slug');
  }
  return keys;
}

/// The entry a file is named after, when there is one.
Entry? coverTitleOf(Library library, CoverFile file) {
  final slug = coverSlugOfName(file.name);
  for (final entry in library.entries) {
    if (coverSlug(entry.id) != slug) continue;
    if (coverFolder(entry.type) == file.folder ||
        coverIdFolder(entry.id) == file.folder) {
      return entry;
    }
  }
  return null;
}

/// The entries that show the file at [path].
List<Entry> coverUsers(Library library, String path) => [
  for (final entry in library.entries)
    if (repoCoverPath(entry.coverFrom) == path) entry,
];

/// The files no title uses as its cover and whose name matches no title.
List<CoverFile> unusedCovers(Iterable<CoverFile> files, Library library) {
  final titles = _titleKeys(library);
  final used = {
    for (final entry in library.entries) ?repoCoverPath(entry.coverFrom),
  };
  return [
    for (final file in files)
      if (!used.contains(file.path) &&
          !titles.contains('${file.folder}/${coverSlugOfName(file.name)}'))
        file,
  ];
}

/// Whether another entry than [id] shows the file at [path].
bool coverUsedElsewhere(Library library, String path, String id) => library
    .entries
    .any((entry) => entry.id != id && repoCoverPath(entry.coverFrom) == path);

/// The path a file takes when its title moves to [type]: the same name in
/// that type's folder.
String coverPathIn(MediaType type, String path) =>
    '${coverFolder(type)}/${splitCoverPath(path).$2}';
