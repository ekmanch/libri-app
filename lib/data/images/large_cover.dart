/// The larger version of a cover (Library › Cover, larger and the cover in
/// details): the same image at the size a 3x screen draws it large, made by
/// rewriting the size in the URL the lists already cache, so no lookup is
/// asked. Each source's own size option, never its "original":
///
/// - TMDB: `w780` (780 × 1170), from the `w342` the lists use.
/// - IGDB: `t_1080p` (810 × 1080), from `t_cover_big`.
/// - Deezer: 1000 × 1000 (`cover_xl`), from the 500 of `cover_big`.
/// - Apple: its image server renders any size: a 1170 box for a book
///   (780 wide at 2:3), 900 for a square album.
///
/// AniList (`extraLarge`), Open Library (`-L`) and Google Books are already
/// cached at the largest size they offer short of the original, and the
/// owner's own files ("repo:") are on the phone as they were uploaded: for
/// those there is no second image, and the one the lists use is shown.
library;

/// The width the larger view draws a 2:3 cover at: 260 dp on a 3x screen.
const largePosterWidth = 780;

/// TMDB's poster size for the larger view.
const tmdbLargeSize = 'w780';

/// IGDB's image size for the larger view: fits 1920 × 1080, so 810 × 1080
/// for a 3:4 cover.
const igdbLargeSize = 't_1080p';

/// Deezer's `cover_xl`.
const deezerLargeSide = 1000;

/// The box asked of Apple for a book, whose cover is 780 wide at 2:3.
const appleLargePosterBox = 1170;

/// The box asked of Apple for a square album cover.
const appleLargeSquareBox = 900;

final _tmdb = RegExp(r'^(https://image\.tmdb\.org/t/p/)w(\d+)(/.+)$');
final _igdb = RegExp(
  r'^(https://images\.igdb\.com/igdb/image/upload/)(t_[a-z0-9_]+)(/.+)$',
);
const _igdbSmaller = {
  't_thumb',
  't_micro',
  't_cover_small',
  't_cover_small_2x',
  't_cover_big',
  't_cover_big_2x',
  't_logo_med',
  't_720p',
};
final _deezer = RegExp(
  r'^(https://[a-z0-9.-]+\.dzcdn\.net/.+/)(\d+)x(\d+)(-[^/]+)$',
);
final _apple = RegExp(
  r'^(https://[a-z0-9.-]+\.mzstatic\.com/.+/)(\d+)x(\d+)([a-z-]*\.\w+)$',
);

/// The URL of the larger version of the cover at [url], or null when
/// there is none: the source has no larger size, [url] is already it, or
/// it is not a source's image at all. [square] is the entry's shape:
/// music, whose covers are 1:1.
String? largeCoverUrl(String url, {required bool square}) {
  if (_tmdb.firstMatch(url) case final m?) {
    final width = int.parse(m[2]!);
    return width < largePosterWidth ? '${m[1]}$tmdbLargeSize${m[3]}' : null;
  }
  if (_igdb.firstMatch(url) case final m?) {
    return _igdbSmaller.contains(m[2]) ? '${m[1]}$igdbLargeSize${m[3]}' : null;
  }
  if (_deezer.firstMatch(url) case final m?) {
    final width = int.parse(m[2]!);
    return width < deezerLargeSide
        ? '${m[1]}${deezerLargeSide}x$deezerLargeSide${m[4]}'
        : null;
  }
  if (_apple.firstMatch(url) case final m?) {
    final box = square ? appleLargeSquareBox : appleLargePosterBox;
    final width = int.parse(m[2]!);
    return width < box ? '${m[1]}${box}x$box${m[4]}' : null;
  }
  return null;
}
