/// The larger version of a cover (Library › Cover, larger and the cover in
/// details): the same image at the size a 3x screen draws it large, made by
/// rewriting the size in the URL the lists already cache, so no lookup is
/// asked. Each source's own size option, never its "original":
///
/// - TMDB: `w780` (780 × 1170), from the `w342` the lists use.
/// - IGDB: `t_1080p` (810 × 1080), from `t_cover_big`.
/// - Deezer: 1000 × 1000 (`cover_xl`), from the 500 of `cover_big`.
/// - Apple: its image server renders any size: a 1170 box for a book
///   (780 wide at 2:3), 900 for a square album. "Sharpest" counts a book's
///   box as 1200 ([appleSharpestPosterBox]).
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

/// The box Apple's book cover is counted at when the choices of Pick a
/// cover are compared ([largestCoverWidth]): the desktop's box, so both
/// apps mark the same tile "Sharpest" (owner's decision, 2026-11-22).
/// The larger view still asks for [appleLargePosterBox].
const appleSharpestPosterBox = 1200;

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

final _anilist = RegExp(
  r'^https://[a-z0-9.-]*anilist\.co/.+/cover/(small|medium|large)/',
);
final _openLibrary = RegExp(
  r'^https://covers\.openlibrary\.org/.+-([SML])\.jpg',
);
final _googleBooks = RegExp(
  r'^https?://books\.google\.[a-z.]+/.*[?&]zoom=(\d)',
);

/// IGDB's sizes as a 3:4 cover's width.
const _igdbWidths = {
  't_cover_small': 90,
  't_cover_small_2x': 180,
  't_cover_big': 264,
  't_cover_big_2x': 528,
  't_720p': 540,
  't_1080p': 810,
};

/// How wide, in pixels, the largest version of the cover at [url] is that
/// the app would fetch for the larger view ([largeCoverUrl], else [url]
/// itself), read from the URL alone: nothing is downloaded. Null when the
/// URL says nothing (one of the owner's own files, an unknown server).
///
/// Exact where the size is in the URL and the server renders it: TMDB's
/// `w780`, Deezer's 1000, Apple's box (a book's read as the desktop's
/// 1200 and its width taken as two thirds of that, 800, its shape being
/// unknown; a box already larger counts as it is). Assumed where the source names a
/// size without a width: IGDB's `t_1080p` as 810 (a 3:4 cover), AniList's
/// `extraLarge` as 460, Open Library's `-L` as 500, Google Books' medium
/// as 575. A source may also hold a smaller original than the size asked
/// for; that cannot be known without the file.
int? largestCoverWidth(String url, {required bool square}) {
  final largest = largeCoverUrl(url, square: square) ?? url;
  if (_tmdb.firstMatch(largest) case final m?) return int.parse(m[2]!);
  if (_igdb.firstMatch(largest) case final m?) return _igdbWidths[m[2]];
  if (_deezer.firstMatch(largest) case final m?) return int.parse(m[2]!);
  if (_apple.firstMatch(largest) case final m?) {
    final box = int.parse(m[2]!);
    if (square) return box;
    return (box > appleSharpestPosterBox ? box : appleSharpestPosterBox) *
        2 ~/
        3;
  }
  if (_anilist.firstMatch(largest) case final m?) {
    return const {'small': 100, 'medium': 230, 'large': 460}[m[1]];
  }
  if (_openLibrary.firstMatch(largest) case final m?) {
    return const {'S': 40, 'M': 180, 'L': 500}[m[1]];
  }
  if (_googleBooks.firstMatch(largest) case final m?) {
    return m[1] == '3' ? 575 : null;
  }
  return null;
}

/// How much wider the widest cover must be than another on offer to be
/// called the sharpest.
const sharpestCoverMargin = 1.25;

/// Which of the choices with these [widths] (null: unknown) Pick a cover
/// captions "Sharpest": the widest, when it is at least a quarter wider
/// than another choice on offer; every one of them when several are
/// equally wide. Empty when all are about the same.
Set<int> sharpestCovers(List<int?> widths) {
  final known = widths.nonNulls;
  if (known.length < 2) return const {};
  final widest = known.reduce((a, b) => a > b ? a : b);
  final narrowest = known.reduce((a, b) => a < b ? a : b);
  if (widest < narrowest * sharpestCoverMargin) return const {};
  return {
    for (final (i, width) in widths.indexed)
      if (width == widest) i,
  };
}
