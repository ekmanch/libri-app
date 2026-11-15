import 'dart:convert';

import '../models/entry_id.dart';

/// Artist photos: the rules, with nothing fetched or stored here (DESIGN.md
/// section 10e, the desktop's "Artist photos"). They are the desktop's
/// (`src/covers/artists.rs`) and must never differ from them: both apps run
/// the cases in `artist_photos.json` (here `test/fixtures/`, a byte-identical
/// copy of the desktop's `assets/fixtures/`).
///
/// An artist has one fixed file in the library repo,
/// `covers/artists/<slug>.jpg`, whoever put it there: fetched from the
/// artist's Apple Music page, picked in Pick a photo or uploaded. With no
/// file an artist shows a cover from the library, else their initials.
/// `covers/artists/_missing.json` records "tried, nothing found", so no
/// device asks Apple about the same artist again for ninety days.

/// The folder under `covers/`.
const artistsFolder = 'artists';

/// The record of artists tried with nothing found, in that folder.
const artistsMissingFile = '_missing.json';

/// The last segment of a photo's URL as it is fetched and stored: Apple's
/// 640 × 640 square JPEG.
const artistPhotoSize = '640x640cc.jpg';

/// The side of an artist's photo, in pixels.
const artistPhotoSide = 640;

/// How long "nothing found" stands before the artist is tried again.
const artistRetryDays = 90;

/// The `_missing.json` format.
const artistsMissingVersion = 1;

/// A name as names and album titles are compared: case, accents and
/// punctuation aside, "&" as "and", a leading "The" ignored. It is the slug
/// of the name with " and " for each "&", without a leading "the-" (kept
/// when nothing else is left: "The The" is "the"). Empty for a name with no
/// letters or digits, which matches nothing.
String artistNameKey(String name) {
  final key = slugify(name.replaceAll('&', ' and '));
  return key.startsWith('the-') && key.length > 4 ? key.substring(4) : key;
}

/// Whether two names or two album titles are the same by [artistNameKey].
bool sameArtistName(String a, String b) {
  final key = artistNameKey(a);
  return key.isNotEmpty && key == artistNameKey(b);
}

/// The artist's slug, the entry ids' slug of the name; null for a name with
/// no letters or digits, which never gets a file.
String? artistSlug(String name) {
  final slug = slugify(name);
  return slug.isEmpty ? null : slug;
}

/// The artist's file under `covers/`: "artists/massive-attack.jpg".
String? artistPhotoPath(String name) => switch (artistSlug(name)) {
  final slug? => '$artistsFolder/$slug.jpg',
  null => null,
};

/// `_missing.json` under `covers/`.
const artistsMissingPath = '$artistsFolder/$artistsMissingFile';

/// Whether a path under `covers/` is in the artists folder, which the
/// review of uploaded covers leaves alone.
bool isArtistPath(String path) => path.startsWith('$artistsFolder/');

/// The slug of an artist's file at [path] under `covers/`:
/// "artists/adele.jpg" is "adele".
String? artistSlugOfPath(String path) {
  if (!isArtistPath(path) || !path.endsWith('.jpg')) return null;
  final slug = path.substring(artistsFolder.length + 1, path.length - 4);
  return slug.isEmpty || slug.contains('/') ? null : slug;
}

/// The names no photo is ever looked for: "Various Artists" and "Unknown
/// artist", compared like any name.
bool isSkippedArtist(String name) =>
    const {'various-artists', 'unknown-artist'}.contains(artistNameKey(name));

/// The `og:image` of an artist's `music.apple.com` page: the `content` of
/// the first `<meta>` whose `property` is exactly "og:image".
String? ogImage(String html) {
  var rest = html;
  while (true) {
    final at = rest.indexOf('<meta');
    if (at < 0) return null;
    final from = rest.substring(at);
    final end = from.indexOf('>');
    if (end < 0) return null;
    final tag = from.substring(0, end);
    rest = from.substring(end);
    if (_attribute(tag, 'property') == 'og:image') {
      final url = _attribute(tag, 'content');
      return url == null || url.isEmpty ? null : url.replaceAll('&amp;', '&');
    }
  }
}

/// The value of `name="…"` in a tag.
String? _attribute(String tag, String name) {
  var rest = tag;
  var offset = 0;
  while (true) {
    final at = rest.indexOf(name);
    if (at < 0) return null;
    final before = offset + at == 0 ? null : tag[offset + at - 1];
    final after = rest.substring(at + name.length);
    offset += at + name.length;
    rest = after;
    if (before != null && before.trim().isEmpty && after.startsWith('="')) {
      final value = after.substring(2);
      final close = value.indexOf('"');
      return close < 0 ? null : value.substring(0, close);
    }
  }
}

/// What an `og:image` shows, told by the bucket in its URL (the segment
/// after `/image/thumb/`).
enum ArtistArt {
  /// `AMCArtistImages…` or `Features…`: a photo of the artist.
  photo,

  /// `Music…`: an album cover Apple puts there for an artist without a
  /// photo.
  album,

  /// Any other bucket, which counts as no photo.
  unknown,
}

ArtistArt artistArtOf(String ogImage) {
  const marker = '/image/thumb/';
  final at = ogImage.indexOf(marker);
  final bucket = at < 0
      ? ''
      : ogImage.substring(at + marker.length).split('/').first;
  if (bucket.startsWith('AMCArtistImages') || bucket.startsWith('Features')) {
    return ArtistArt.photo;
  }
  return bucket.startsWith('Music') ? ArtistArt.album : ArtistArt.unknown;
}

/// The photo to fetch for an `og:image`: the same image as a 640 × 640
/// square JPEG (the share card's last segment, `1200x630cw.png`, replaced
/// by `640x640cc.jpg`); null unless the image is a photo of the artist.
String? artistPhotoUrl(String ogImage) {
  if (artistArtOf(ogImage) != ArtistArt.photo) return null;
  final slash = ogImage.lastIndexOf('/');
  if (slash < 0 || slash == ogImage.length - 1) return null;
  return '${ogImage.substring(0, slash)}/$artistPhotoSize';
}

/// An Apple artist a name search found, with the titles of their albums.
class ArtistCandidate {
  const ArtistCandidate({
    required this.id,
    required this.name,
    this.albums = const [],
    this.page,
  });

  final String id;
  final String name;
  final List<String> albums;

  /// The artist's `music.apple.com` page, when the search gave one.
  final String? page;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'page': ?page,
    'albums': albums,
  };

  static ArtistCandidate? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return ArtistCandidate(
      id: id,
      name: name,
      albums: [
        for (final album in json['albums'] as List<Object?>? ?? const [])
          if (album is String) album,
      ],
      page: json['page'] as String?,
    );
  }
}

/// How many of [owned] (the album titles saved for the artist) the
/// candidate lists, each owned title counted once.
int ownedAlbumCount(ArtistCandidate candidate, Iterable<String> owned) {
  final listed = {for (final album in candidate.albums) artistNameKey(album)};
  final keys = {for (final title in owned) artistNameKey(title)};
  return keys.where((key) => key.isNotEmpty && listed.contains(key)).length;
}

/// The Apple artist that is the library's [name]: among the candidates of
/// the same name, the one listing the most owned albums. One that lists
/// none is no match, even as the only namesake, and a tie for the most is
/// no match either.
ArtistCandidate? chooseArtist(
  String name,
  Iterable<String> owned,
  List<ArtistCandidate> candidates,
) {
  final counted = [
    for (final candidate in candidates)
      if (sameArtistName(candidate.name, name))
        (ownedAlbumCount(candidate, owned), candidate),
  ].where((c) => c.$1 > 0).toList();
  if (counted.isEmpty) return null;
  var best = counted.first;
  var tied = false;
  for (final other in counted.skip(1)) {
    if (other.$1 > best.$1) {
      best = other;
      tied = false;
    } else if (other.$1 == best.$1) {
      tied = true;
    }
  }
  return tied ? null : best.$2;
}

/// Why an artist has no photo.
enum MissingReason {
  /// No Apple artist of the name lists an owned album, or two tie.
  noMatch('no-match'),

  /// The matched artist's page shows no photo of the artist.
  noPhoto('no-photo');

  const MissingReason(this.key);

  final String key;

  static MissingReason? parse(Object? key) {
    for (final reason in values) {
      if (reason.key == key) return reason;
    }
    return null;
  }
}

final _day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// A calendar day from "2026-11-15", at UTC midnight; null for any other
/// shape or a day that does not exist.
DateTime? parseArtistDay(Object? text) {
  if (text is! String) return null;
  final match = _day.firstMatch(text);
  if (match == null) return null;
  final (y, m, d) = (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  final day = DateTime.utc(y, m, d);
  return day.year == y && day.month == m && day.day == d ? day : null;
}

/// "2026-11-15".
String formatArtistDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// [day]'s calendar day at UTC midnight, so days subtract evenly.
DateTime artistDayOf(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day);

/// One artist of `_missing.json`: the name as the library spells it, the
/// day Apple was asked and what came of it.
class TriedArtist {
  const TriedArtist({
    required this.name,
    required this.tried,
    required this.reason,
  });

  final String name;
  final DateTime tried;
  final MissingReason reason;

  /// Whether the artist is asked about again on [today]: ninety days after
  /// the try, or sooner once an entry by the artist was added on a later
  /// day than the try ([added] is the latest `added` among the artist's
  /// entries). The device that adds an entry tries at once, whatever the
  /// day.
  bool isDue(DateTime today, DateTime? added) =>
      artistDayOf(today).difference(artistDayOf(tried)).inDays >=
          artistRetryDays ||
      (added != null && artistDayOf(added).isAfter(artistDayOf(tried)));

  @override
  bool operator ==(Object other) =>
      other is TriedArtist &&
      other.name == name &&
      other.tried == tried &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(name, tried, reason);
}

/// One change to `_missing.json`, queued until the sync that carries it:
/// the file is never sent whole, since another device may have added to it
/// meanwhile.
sealed class MissingEdit {
  const MissingEdit();

  Map<String, Object?> toJson();

  static MissingEdit? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    if (json['set'] case final String slug) {
      final name = json['name'];
      final tried = parseArtistDay(json['tried']);
      final reason = MissingReason.parse(json['reason']);
      if (name is! String || tried == null || reason == null) return null;
      return MissingSet(
        slug,
        TriedArtist(name: name, tried: tried, reason: reason),
      );
    }
    if (json['remove'] case final String slug) return MissingRemove(slug);
    if (parseArtistDay(json['backfilled']) case final day?) {
      return MissingBackfilled(day);
    }
    return null;
  }
}

/// Apple was asked about the artist and nothing was found.
class MissingSet extends MissingEdit {
  const MissingSet(this.slug, this.tried);

  final String slug;
  final TriedArtist tried;

  @override
  Map<String, Object?> toJson() => {
    'set': slug,
    'name': tried.name,
    'tried': formatArtistDay(tried.tried),
    'reason': tried.reason.key,
  };
}

/// The artist has a file now, or is asked about again.
class MissingRemove extends MissingEdit {
  const MissingRemove(this.slug);

  final String slug;

  @override
  Map<String, Object?> toJson() => {'remove': slug};
}

/// The backfill finished on this day. Only the desktop writes it; the
/// phone reads it and applies it in a merge like any edit.
class MissingBackfilled extends MissingEdit {
  const MissingBackfilled(this.day);

  final DateTime day;

  @override
  Map<String, Object?> toJson() => {'backfilled': formatArtistDay(day)};
}

/// `_missing.json` could not be read: another version or shape. The file
/// is left as it is.
class MissingFormatException implements Exception {
  const MissingFormatException(this.message);

  final String message;

  @override
  String toString() => 'MissingFormatException: $message';
}

/// `_missing.json`: the artists tried with nothing found, by slug, and the
/// day the desktop's backfill finished.
class MissingArtists {
  MissingArtists({this.backfilled, Map<String, TriedArtist>? artists})
    : artists = artists ?? {};

  /// Written by the backfill's last batch; the phone fetches nothing until
  /// it is there.
  DateTime? backfilled;
  final Map<String, TriedArtist> artists;

  /// Reads the file. Anything but version 1 in the shape below throws
  /// [MissingFormatException], and such a file is left as it is.
  static MissingArtists decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw MissingFormatException(e.message);
    }
    if (json is! Map<String, Object?> ||
        json['version'] != artistsMissingVersion) {
      throw const MissingFormatException('not version $artistsMissingVersion');
    }
    DateTime? backfilled;
    if (json['backfilled'] case final Object value) {
      backfilled =
          parseArtistDay(value) ??
          (throw const MissingFormatException('backfilled is not a date'));
    }
    final listed = json['artists'];
    if (listed is! Map<String, Object?>) {
      throw const MissingFormatException('no artists');
    }
    final artists = <String, TriedArtist>{};
    for (final MapEntry(key: slug, value: entry) in listed.entries) {
      if (entry is! Map<String, Object?>) {
        throw MissingFormatException('$slug is not an object');
      }
      final name = entry['name'];
      if (name is! String) throw MissingFormatException('$slug has no name');
      final reason =
          MissingReason.parse(entry['reason']) ??
          (throw MissingFormatException('$slug has no known reason'));
      final tried =
          parseArtistDay(entry['tried']) ??
          (throw const MissingFormatException('tried is not a date'));
      artists[slug] = TriedArtist(name: name, tried: tried, reason: reason);
    }
    return MissingArtists(backfilled: backfilled, artists: artists);
  }

  /// The file's text: two-space indent, `version`, then `backfilled` when
  /// set, then `artists` with one artist per line in slug order (by code
  /// unit; a slug is ASCII), each with `name`, `tried` and `reason` in
  /// that order, and a newline at the end.
  String encode() {
    final out = StringBuffer('{\n  "version": $artistsMissingVersion,\n');
    if (backfilled case final day?) {
      out.write('  "backfilled": "${formatArtistDay(day)}",\n');
    }
    if (artists.isEmpty) {
      out.write('  "artists": {}\n}\n');
      return '$out';
    }
    out.write('  "artists": {\n');
    final slugs = artists.keys.toList()..sort();
    out.write(
      [
        for (final slug in slugs)
          '    ${jsonEncode(slug)}: {"name": ${jsonEncode(artists[slug]!.name)}, '
              '"tried": "${formatArtistDay(artists[slug]!.tried)}", '
              '"reason": "${artists[slug]!.reason.key}"}',
      ].join(',\n'),
    );
    out.write('\n  }\n}\n');
    return '$out';
  }

  /// Whether Apple is asked about the artist with [slug] on [today]:
  /// always without an entry here, else by [TriedArtist.isDue].
  bool isDue(String slug, DateTime today, DateTime? added) =>
      artists[slug]?.isDue(today, added) ?? true;

  /// One edit. The first `backfilled` day stands.
  void apply(MissingEdit edit) {
    switch (edit) {
      case MissingSet(:final slug, :final tried):
        artists[slug] = tried;
      case MissingRemove(:final slug):
        artists.remove(slug);
      case MissingBackfilled(:final day):
        backfilled ??= day;
    }
  }

  /// This record with [edits] applied in order and without the artists
  /// that have a file ([hasFile], by slug): an entry is removed when a file
  /// for the artist appears, whoever put it there.
  MissingArtists merged(
    Iterable<MissingEdit> edits,
    bool Function(String slug) hasFile,
  ) {
    final out = MissingArtists(backfilled: backfilled, artists: {...artists});
    edits.forEach(out.apply);
    out.artists.removeWhere((slug, _) => hasFile(slug));
    return out;
  }

  bool get isEmpty => backfilled == null && artists.isEmpty;
}

/// `_missing.json` as a sync writes it: the repo's copy ([theirs], null
/// when there is no file yet) with this device's [edits] on top, per
/// artist. Null when that changes nothing, and no file is made for an empty
/// record. A copy that cannot be read throws [MissingFormatException] and
/// is left as it is; the edits are then dropped.
String? mergedMissing(
  String? theirs,
  Iterable<MissingEdit> edits,
  bool Function(String slug) hasFile,
) {
  final base = theirs == null
      ? MissingArtists()
      : MissingArtists.decode(theirs);
  final merged = base.merged(edits, hasFile);
  if (theirs == null && merged.isEmpty) return null;
  final text = merged.encode();
  return text == theirs ? null : text;
}

/// One of an artist's entries, as the library cover is picked from them.
typedef SavedByArtist = ({bool song, DateTime added});

/// The order in which an artist's entries lend their cover when the artist
/// has no file, as indexes into [saved] (the artist's entries in the
/// file's order): the albums, most recently added first, then the songs (a
/// song shows its album's cover) the same way; of two added on the same
/// day the one later in the file comes first. The artist shows the first of
/// them that has a cover, else their initials.
List<int> artistCoverOrder(List<SavedByArtist> saved) {
  final order = [for (var i = 0; i < saved.length; i++) i];
  order.sort((a, b) {
    if (saved[a].song != saved[b].song) return saved[a].song ? 1 : -1;
    final byDay = artistDayOf(saved[b].added)
        .compareTo(artistDayOf(saved[a].added));
    return byDay != 0 ? byDay : b.compareTo(a);
  });
  return order;
}
