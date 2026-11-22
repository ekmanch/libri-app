import 'dart:convert';

import '../models/entry_id.dart';

/// Artist photos: the rules, with nothing fetched or stored here (DESIGN.md
/// section 10e, the desktop's "Artist photos"). They are the desktop's
/// (`src/covers/artists.rs`) and must never differ from them: both apps run
/// the cases in `artist_photos.json`. The desktop's file
/// (`assets/fixtures/` in `ekmanch/libri-kde`) is the source; the one here,
/// in `test/fixtures/`, is a byte-identical copy of it.
///
/// An artist has one fixed file in the library repo,
/// `covers/artists/<slug>.jpg`, whoever put it there: fetched from the
/// artist's Apple Music page, picked in Pick a photo or uploaded. With no
/// file an artist shows a cover from the library, else their initials.
/// `covers/artists/_missing.json` records "tried, nothing found", so no
/// device asks Apple about the same artist again for ninety days, and with
/// it the size new photos are fetched at and the artists whose photo the
/// owner chose.

/// The folder under `covers/`.
const artistsFolder = 'artists';

/// The record of artists tried with nothing found, in that folder.
const artistsMissingFile = '_missing.json';

/// The last segment of a photo's URL as it is read from Apple's page and
/// kept: the 640 × 640 square JPEG. [artistPhotoAt] makes it the size
/// that is fetched.
const artistPhotoSize = '640x640cc.jpg';

/// The side of an artist's photo, in pixels, until the record says
/// otherwise ([MissingArtists.photoSize]).
const artistPhotoSide = 640;

/// The side once the desktop has re-fetched the existing photos and
/// written `"photo_size": 1200` into the record.
const artistPhotoLargeSide = 1200;

/// The photo at [url] ([artistPhotoUrl]) as a [side] × [side] JPEG. Any
/// other URL is left as it is.
String artistPhotoAt(String url, int side) =>
    side != artistPhotoSide && url.endsWith('/$artistPhotoSize')
    ? '${url.substring(0, url.length - artistPhotoSize.length)}'
          '${side}x${side}cc.jpg'
    : url;

/// How long "nothing found" stands before the artist is tried again.
const artistRetryDays = 90;

/// The `_missing.json` format.
const artistsMissingVersion = 1;

/// A name as names and titles are compared: case, accents and
/// punctuation aside, "&" as "and", a leading "The" ignored. It is the slug
/// of the name with " and " for each "&", without a leading "the-" (kept
/// when nothing else is left: "The The" is "the"). Empty for a name with no
/// letters or digits, which matches nothing.
String artistNameKey(String name) {
  final key = slugify(name.replaceAll('&', ' and '));
  return key.startsWith('the-') && key.length > 4 ? key.substring(4) : key;
}

/// Whether two artist names are the same by [artistNameKey].
bool sameArtistName(String a, String b) {
  final key = artistNameKey(a);
  return key.isNotEmpty && key == artistNameKey(b);
}

/// A title without the notes at its end: a trailing " - Single" or " - EP"
/// (whatever the case) and a trailing part in round or square brackets,
/// from its last opening bracket, taken off one after another until none
/// is left. A title that would end up empty keeps what it had: "(What's
/// the Story) Morning Glory?" and "(I)" stay whole.
String titleCore(String title) {
  var core = title.trim();
  while (true) {
    final shorter =
        (_withoutSuffix(core, ' - single') ??
                _withoutSuffix(core, ' - ep') ??
                _withoutBracket(core, '(', ')') ??
                _withoutBracket(core, '[', ']'))
            ?.trimRight();
    if (shorter == null || shorter.isEmpty) return core;
    core = shorter;
  }
}

/// [title] without [suffix] (lower case, ASCII) at its end, compared
/// whatever the case of the ASCII letters; null when it does not end so.
String? _withoutSuffix(String title, String suffix) {
  final at = title.length - suffix.length;
  if (at < 0) return null;
  for (var i = 0; i < suffix.length; i++) {
    var unit = title.codeUnitAt(at + i);
    if (unit >= 0x41 && unit <= 0x5A) unit += 0x20;
    if (unit != suffix.codeUnitAt(i)) return null;
  }
  return title.substring(0, at);
}

String? _withoutBracket(String title, String open, String close) {
  if (!title.endsWith(close)) return null;
  final at = title.lastIndexOf(open);
  return at < 0 ? null : title.substring(0, at);
}

/// The keys a title is compared by: the title's own and its core's
/// ([titleCore]), the empty ones left out. The core's comes last.
List<String> _titleKeys(String title) {
  final own = artistNameKey(title);
  final core = artistNameKey(titleCore(title));
  return [if (own.isNotEmpty) own, if (core.isNotEmpty && core != own) core];
}

/// Whether two album titles, or two song titles, are the same: by
/// [artistNameKey], each as it is written or without the notes at its end,
/// so "Texas Moon" is "Texas Moon - EP", "Abbey Road" is "Abbey Road
/// (Remastered)" and "Another Green World (2004 Remaster)" is "Another
/// Green World". Words outside the brackets still have to agree.
bool sameTitle(String a, String b) {
  final other = _titleKeys(b);
  return _titleKeys(a).any(other.contains);
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

/// How many of an artist's saved songs Apple is asked about, at most.
const artistSongsAsked = 3;

/// An Apple artist a name search found, with the titles of their albums
/// and, when their songs were searched for ([chooseArtist]), the names of
/// the tracks those searches found under this artist's id.
class ArtistCandidate {
  const ArtistCandidate({
    required this.id,
    required this.name,
    this.albums = const [],
    this.songs = const [],
    this.page,
  });

  final String id;
  final String name;
  final List<String> albums;
  final List<String> songs;

  /// The artist's `music.apple.com` page, when the search gave one.
  final String? page;

  ArtistCandidate withSongs(List<String> songs) => ArtistCandidate(
    id: id,
    name: name,
    albums: albums,
    songs: songs,
    page: page,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'page': ?page,
    'albums': albums,
    if (songs.isNotEmpty) 'songs': songs,
  };

  static ArtistCandidate? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    List<String> strings(String key) => [
      for (final item in json[key] as List<Object?>? ?? const [])
        if (item is String) item,
    ];
    return ArtistCandidate(
      id: id,
      name: name,
      albums: strings('albums'),
      songs: strings('songs'),
      page: json['page'] as String?,
    );
  }
}

/// How many of [saved] (titles saved for the artist) are among [listed] by
/// [sameTitle]. Saved titles that differ only in the notes at their end
/// ("Birthdays" and "Birthdays (Deluxe)") count once.
int _listedCount(Iterable<String> listed, Iterable<String> saved) {
  final keys = {for (final title in listed) ..._titleKeys(title)};
  final counted = <String>{};
  for (final title in saved) {
    final own = _titleKeys(title);
    // The core's key comes last and names the title.
    if (own.isNotEmpty && own.any(keys.contains)) counted.add(own.last);
  }
  return counted.length;
}

/// How many of [owned] (the album titles saved for the artist) the
/// candidate lists, each owned title counted once.
int ownedAlbumCount(ArtistCandidate candidate, Iterable<String> owned) =>
    _listedCount(candidate.albums, owned);

/// The one with the highest count above zero among the candidates named
/// [name]; none when nobody counts or two tie for the most.
ArtistCandidate? _most(
  String name,
  List<ArtistCandidate> candidates,
  int Function(ArtistCandidate candidate) count,
) {
  final counted = [
    for (final candidate in candidates)
      if (sameArtistName(candidate.name, name)) (count(candidate), candidate),
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

/// The Apple artist that is the library's [name], by albums: among the
/// candidates of the same name, the one listing the most owned albums. One
/// that lists none is no match, even as the only namesake, and a tie for
/// the most is no match either.
ArtistCandidate? chooseByAlbums(
  String name,
  Iterable<String> owned,
  List<ArtistCandidate> candidates,
) => _most(name, candidates, (c) => ownedAlbumCount(c, owned));

/// Whether some candidate of the name lists an owned album. When none
/// does, the artist's saved songs are searched for instead.
bool listsOwned(
  String name,
  Iterable<String> owned,
  List<ArtistCandidate> candidates,
) => candidates.any(
  (c) => sameArtistName(c.name, name) && ownedAlbumCount(c, owned) > 0,
);

/// The saved songs Apple is asked about: the first [artistSongsAsked] of
/// [songs] (the artist's saved song titles in the library's order), a
/// title counted once by [sameTitle] and one with no key left out.
List<String> songsAsked(Iterable<String> songs) {
  final asked = <String>[];
  for (final song in songs) {
    if (asked.length == artistSongsAsked) break;
    if (artistNameKey(song).isNotEmpty &&
        !asked.any((other) => sameTitle(other, song))) {
      asked.add(song);
    }
  }
  return asked;
}

/// The Apple artist that is the library's [name], by songs: among the
/// candidates of the same name, the one under whose id the searches found
/// the most of the songs asked about ([songsAsked]); none found is no
/// match, and so is a tie for the most.
ArtistCandidate? chooseBySongs(
  String name,
  Iterable<String> songs,
  List<ArtistCandidate> candidates,
) {
  final asked = songsAsked(songs);
  return _most(name, candidates, (c) => _listedCount(c.songs, asked));
}

/// The Apple artist that is the library's [name]: by albums
/// ([chooseByAlbums]); by songs ([chooseBySongs]) only when no candidate of
/// the name lists an owned album, so a tie between albums is never broken
/// by a song.
ArtistCandidate? chooseArtist(
  String name,
  Iterable<String> owned,
  Iterable<String> songs,
  List<ArtistCandidate> candidates,
) => listsOwned(name, owned, candidates)
    ? chooseByAlbums(name, owned, candidates)
    : chooseBySongs(name, songs, candidates);

/// Why an artist has no photo.
enum MissingReason {
  /// No Apple artist of the name lists an owned album or was found with
  /// a saved song, or two tie.
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
    if (json['pick'] case final String slug) return MissingPick(slug);
    if (json['unpick'] case final String slug) return MissingUnpick(slug);
    if (json['photo_size'] case final int side) {
      return side >= 0 && side <= _maxSide ? MissingPhotoSize(side) : null;
    }
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

/// The owner picked or uploaded the artist's photo: the slug joins
/// `picked`, the artists whose photo no fetch may replace.
class MissingPick extends MissingEdit {
  const MissingPick(this.slug);

  final String slug;

  @override
  Map<String, Object?> toJson() => {'pick': slug};
}

/// "Use automatic", or the Suggested photo picked again: the photo is no
/// longer the owner's own choice, and the slug leaves `picked`.
class MissingUnpick extends MissingEdit {
  const MissingUnpick(this.slug);

  final String slug;

  @override
  Map<String, Object?> toJson() => {'unpick': slug};
}

/// New photos are fetched at this side from now on. Only the desktop
/// writes it, once it has re-fetched the existing photos; the phone
/// applies it in a merge like any edit and never queues one.
class MissingPhotoSize extends MissingEdit {
  const MissingPhotoSize(this.side);

  final int side;

  @override
  Map<String, Object?> toJson() => {'photo_size': side};
}

/// The largest `photo_size` read: the desktop keeps it in 32 bits.
const _maxSide = 0xFFFFFFFF;

/// A top-level key of `_missing.json` this build does not know (or a
/// `photo_size` or `picked` it cannot read), with its value's text exactly
/// as the file had it and the known key it followed (null at the start of
/// the file).
typedef MissingExtra = ({String? after, String key, String text});

/// `_missing.json` could not be read: another version or shape. The file
/// is left as it is.
class MissingFormatException implements Exception {
  const MissingFormatException(this.message);

  final String message;

  @override
  String toString() => 'MissingFormatException: $message';
}

/// `_missing.json`: the artists tried with nothing found, by slug, the day
/// the desktop's backfill finished, the size photos are fetched at and the
/// artists whose photo the owner chose.
class MissingArtists {
  MissingArtists({
    this.backfilled,
    this.photoSize,
    Set<String>? picked,
    Map<String, TriedArtist>? artists,
    List<MissingExtra>? extra,
  }) : picked = picked ?? {},
       artists = artists ?? {},
       _extra = extra ?? const [];

  /// Written by the backfill's last batch; the phone fetches nothing until
  /// it is there.
  DateTime? backfilled;

  /// `photo_size`: the side new artists' photos are fetched at, written
  /// by the desktop once it has re-fetched the existing ones. Null until
  /// then, which means [artistPhotoSide] ([photoSide]).
  int? photoSize;

  /// `picked`: the slugs of the artists whose photo the owner picked or
  /// uploaded, on any device. A fetch never replaces theirs.
  final Set<String> picked;
  final Map<String, TriedArtist> artists;

  /// What this build does not know, written back as it was read.
  final List<MissingExtra> _extra;

  /// The top-level keys this build reads and writes, in the order it
  /// writes them.
  static const _known = [
    'version',
    'backfilled',
    'photo_size',
    'picked',
    'artists',
  ];

  /// The side a new photo is fetched at.
  int get photoSide => photoSize ?? artistPhotoSide;

  /// Reads the file. Anything but version 1 in the shape below throws
  /// [MissingFormatException], and such a file is left as it is. A
  /// top-level key this build does not know is kept with its value as
  /// written, and so is a `photo_size` that is no positive number or a
  /// `picked` that is no list of slugs.
  static MissingArtists decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw MissingFormatException(e.message);
    }
    if (json is! Map<String, Object?> ||
        json['version'] is! int ||
        json['version'] != artistsMissingVersion) {
      throw const MissingFormatException('not version $artistsMissingVersion');
    }
    DateTime? backfilled;
    if (json['backfilled'] case final Object value) {
      backfilled =
          parseArtistDay(value) ??
          (throw const MissingFormatException('backfilled is not a date'));
    }
    final size = json['photo_size'];
    final photoSize = size is int && size > 0 && size <= _maxSide ? size : null;
    final list = json['picked'];
    final picked = list is List<Object?> && list.every((slug) => slug is String)
        ? {for (final slug in list) slug! as String}
        : null;
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
    final extra = <MissingExtra>[];
    String? after;
    for (final MapEntry(:key, value: written) in _topLevelText(text).entries) {
      final known = _known.contains(key);
      final understood = switch (key) {
        'photo_size' => photoSize != null,
        'picked' => picked != null,
        _ => known,
      };
      if (!understood) extra.add((after: after, key: key, text: written));
      if (known) after = key;
    }
    return MissingArtists(
      backfilled: backfilled,
      photoSize: photoSize,
      picked: picked,
      artists: artists,
      extra: extra,
    );
  }

  /// The top-level keys of the JSON object [text] (valid JSON, an object),
  /// each with the text of its value as written. A key written twice keeps
  /// its first place and its last value, as a JSON reader would have it.
  static Map<String, String> _topLevelText(String text) {
    const space = ' \n\r\t';
    int past(int i) {
      while (i < text.length && space.contains(text[i])) {
        i++;
      }
      return i;
    }

    // [i] is at a string's opening quote; the index after its closing one.
    int afterString(int i) {
      i++;
      while (text[i] != '"') {
        if (text[i] == r'\') i++;
        i++;
      }
      return i + 1;
    }

    final out = <String, String>{};
    var i = text.indexOf('{') + 1;
    while (true) {
      i = past(i);
      if (i >= text.length || text[i] != '"') break;
      final keyEnd = afterString(i);
      final key = jsonDecode(text.substring(i, keyEnd)) as String;
      i = past(past(keyEnd) + 1);
      final start = i;
      var depth = 0;
      while (i < text.length) {
        final c = text[i];
        if (c == '"') {
          i = afterString(i);
          continue;
        }
        if (c == '{' || c == '[') depth++;
        if (c == '}' || c == ']') {
          if (depth == 0) break;
          depth--;
        }
        if (c == ',' && depth == 0) break;
        i++;
      }
      out[key] = text.substring(start, i).trimRight();
      if (i < text.length && text[i] == ',') i++;
    }
    return out;
  }

  /// The file's text: two-space indent, `version`, then `backfilled` when
  /// set, `photo_size` when set, `picked` while it has a slug (one per
  /// line, in order), then `artists` with one artist per line in slug
  /// order (by code unit; a slug is ASCII), each with `name`, `tried` and
  /// `reason` in that order, and a newline at the end. Every key this
  /// build does not know keeps its value's text and its place after the
  /// known key it followed, or before all of them when it followed none.
  String encode() {
    final parts = <String>[];
    void extras(String? after) {
      for (final extra in _extra) {
        if (extra.after == after) {
          parts.add('  ${jsonEncode(extra.key)}: ${extra.text}');
        }
      }
    }

    extras(null);
    for (final key in _known) {
      switch (key) {
        case 'version':
          parts.add('  "version": $artistsMissingVersion');
        case 'backfilled' when backfilled != null:
          parts.add('  "backfilled": "${formatArtistDay(backfilled!)}"');
        case 'photo_size' when photoSize != null:
          parts.add('  "photo_size": $photoSize');
        case 'picked' when picked.isNotEmpty:
          final slugs = picked.toList()..sort();
          parts.add(
            '  "picked": [\n'
            '${[for (final slug in slugs) '    ${jsonEncode(slug)}'].join(',\n')}'
            '\n  ]',
          );
        case 'artists' when artists.isEmpty:
          parts.add('  "artists": {}');
        case 'artists':
          final slugs = artists.keys.toList()..sort();
          parts.add(
            '  "artists": {\n${[for (final slug in slugs) '    ${jsonEncode(slug)}: '
                  '{"name": ${jsonEncode(artists[slug]!.name)}, '
                  '"tried": "${formatArtistDay(artists[slug]!.tried)}", '
                  '"reason": "${artists[slug]!.reason.key}"}'].join(',\n')}\n  }',
          );
      }
      extras(key);
    }
    return '{\n${parts.join(',\n')}\n}\n';
  }

  /// Whether Apple is asked about the artist with [slug] on [today]:
  /// always without an entry here, else by [TriedArtist.isDue].
  bool isDue(String slug, DateTime today, DateTime? added) =>
      artists[slug]?.isDue(today, added) ?? true;

  /// One edit. The first `backfilled` day stands, and the first
  /// `photo_size`.
  void apply(MissingEdit edit) {
    switch (edit) {
      case MissingSet(:final slug, :final tried):
        artists[slug] = tried;
      case MissingRemove(:final slug):
        artists.remove(slug);
      case MissingBackfilled(:final day):
        backfilled ??= day;
      case MissingPick(:final slug):
        picked.add(slug);
      case MissingUnpick(:final slug):
        picked.remove(slug);
      case MissingPhotoSize(:final side):
        photoSize ??= side;
    }
  }

  /// This record with [edits] applied in order and without the artists
  /// that have a file ([hasFile], by slug) or are no longer in the library
  /// ([inLibrary], by slug; everyone when left out): an entry leaves when a
  /// file for the artist appears, whoever put it there, or when no entry
  /// names the artist any more, and for no other reason. The other way
  /// round for `picked`: a slug stays only while the artist has a file and
  /// is in the library.
  MissingArtists merged(
    Iterable<MissingEdit> edits,
    bool Function(String slug) hasFile, {
    bool Function(String slug)? inLibrary,
  }) {
    final out = MissingArtists(
      backfilled: backfilled,
      photoSize: photoSize,
      picked: {...picked},
      artists: {...artists},
      extra: _extra,
    );
    edits.forEach(out.apply);
    bool here(String slug) => inLibrary?.call(slug) ?? true;
    out.artists.removeWhere((slug, _) => hasFile(slug) || !here(slug));
    out.picked.removeWhere((slug) => !hasFile(slug) || !here(slug));
    return out;
  }

  bool get isEmpty =>
      backfilled == null &&
      photoSize == null &&
      picked.isEmpty &&
      artists.isEmpty &&
      _extra.isEmpty;
}

/// `_missing.json` as a sync writes it: the repo's copy ([theirs], null
/// when there is no file yet) with this device's [edits] on top, per
/// artist and per picked slug, without the artists that have a file or
/// have left the library and without the picked ones that have no file or
/// have left it ([MissingArtists.merged]). Null when that changes nothing, and no file
/// is made for an empty record. A copy that cannot be read throws
/// [MissingFormatException] and is left as it is; the edits are then
/// dropped.
String? mergedMissing(
  String? theirs,
  Iterable<MissingEdit> edits,
  bool Function(String slug) hasFile, {
  bool Function(String slug)? inLibrary,
}) {
  final base = theirs == null
      ? MissingArtists()
      : MissingArtists.decode(theirs);
  final merged = base.merged(edits, hasFile, inLibrary: inLibrary);
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
