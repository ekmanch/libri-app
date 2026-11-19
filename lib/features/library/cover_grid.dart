import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The two lines of text under a cover or a photo in a grid (the Library
/// "Grid cells" note): the title on up to [titleLines] lines and, directly
/// under it, one second line (the year, "3 movies", the artist).
///
/// A tile draws its text with these styles and the grid measures its rows
/// with the same object, so a row is exactly as tall as what is drawn in it.
@immutable
class GridTileText {
  const GridTileText({
    required this.title,
    required this.caption,
    required this.scaler,
    required this.direction,
    this.locale,
    this.titleLines = 2,
  });

  /// The styles as a [Text] at [context] would resolve them, at the user's
  /// text size up to [maxTextScale].
  factory GridTileText.of(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    var base = DefaultTextStyle.of(context).style;
    if (MediaQuery.boldTextOf(context)) {
      base = base.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return GridTileText(
      title: base.merge(
        theme.labelMedium!.copyWith(
          fontSize: titleFontSize,
          height: titleLineHeight / titleFontSize,
        ),
      ),
      caption: base.merge(
        theme.bodySmall!.copyWith(
          fontSize: captionFontSize,
          fontStyle: FontStyle.normal,
          height: captionLineHeight / captionFontSize,
        ),
      ),
      scaler: MediaQuery.textScalerOf(context)
          .clamp(maxScaleFactor: maxTextScale),
      direction: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
    );
  }

  final TextStyle title;
  final TextStyle caption;
  final TextScaler scaler;
  final TextDirection direction;
  final Locale? locale;
  final int titleLines;

  static const titleFontSize = 13.5;
  static const titleLineHeight = 17.0;
  static const captionFontSize = 12.0;
  static const captionLineHeight = 16.0;

  /// Between the cover and the title, and between the title and the second
  /// line.
  static const coverGap = 6.0;
  static const captionGap = 1.0;

  /// A third of a 360 dp phone has no room for larger text; the title on a
  /// placeholder cover stops at the same size.
  static const maxTextScale = 1.3;

  TextPainter _painter(String text, TextStyle style, int maxLines) =>
      TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: maxLines,
        ellipsis: '…',
      );

  /// The height [text] takes as a title in a tile [width] wide.
  double measureTitle(String text, double width) {
    final painter = _painter(text, title, titleLines)..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// The height of the second line, whatever it says.
  double measureCaption(double width) {
    final painter = _painter(' ', caption, 1)..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  bool operator ==(Object other) =>
      other is GridTileText &&
      other.title == title &&
      other.caption == caption &&
      other.scaler == scaler &&
      other.direction == direction &&
      other.locale == locale &&
      other.titleLines == titleLines;

  @override
  int get hashCode =>
      Object.hash(title, caption, scaler, direction, locale, titleLines);
}

/// The rows of a grid, measured: each row is as tall as its tallest cell,
/// so rows differ by one line of title.
@immutable
class GridRowLayout {
  const GridRowLayout._(this.tileWidth, this._extents, this._tops, this.height);

  static const empty = GridRowLayout._(0, [], [], 0);

  /// The width of one cell, the one its title was measured at.
  final double tileWidth;
  final List<double> _extents;
  final List<double> _tops;

  /// All the rows with the spacing between them.
  final double height;

  int get rowCount => _extents.length;

  /// The height of [row] with the spacing under it (none under the last),
  /// or null past the end.
  double? extentOf(int row) => row < _extents.length ? _extents[row] : null;

  /// Where [row] starts, from the top of the first row.
  double topOf(int row) => _tops.isEmpty
      ? 0
      : row >= _tops.length
      ? height
      : _tops[row];
}

/// What a grid shows, as far as its row heights go: the titles in order,
/// the text styles and the shape of the cover. Both the grid and the long
/// list's thumb ask it for the layout at their width, and get the same one.
@immutable
class CoverGridSpec {
  const CoverGridSpec({
    required this.titles,
    required this.text,
    required this.coverAspectRatio,
    this.columns = 3,
    this.crossSpacing = 12,
    this.mainSpacing = 16,
  });

  /// The title of every cell, in order.
  final List<String> titles;
  final GridTileText text;

  /// Width over height of the cover or the photo above the text.
  final double coverAspectRatio;
  final int columns;
  final double crossSpacing;
  final double mainSpacing;

  double tileWidth(double width) =>
      (width - crossSpacing * (columns - 1)) / columns;

  /// The rows for a grid [width] wide. Measured once: the same titles at
  /// the same width, text size and styles come back from the cache.
  GridRowLayout layoutFor(double width) {
    if (titles.isEmpty || width <= 0) return GridRowLayout.empty;
    final tile = tileWidth(width);
    final measured = _MeasuredText.of(text, tile);
    for (final cached in measured.layouts) {
      if (cached.fits(this)) return cached.layout;
    }
    final layout = _measure(tile, measured);
    measured.layouts.addFirst(_CachedLayout(this, layout));
    if (measured.layouts.length > _MeasuredText.maxLayouts) {
      measured.layouts.removeLast();
    }
    return layout;
  }

  GridRowLayout _measure(double tile, _MeasuredText measured) {
    final cell =
        tile / coverAspectRatio +
        GridTileText.coverGap +
        GridTileText.captionGap +
        measured.caption;
    final rows = (titles.length / columns).ceil();
    final extents = List<double>.filled(rows, 0);
    final tops = List<double>.filled(rows, 0);
    var y = 0.0;
    for (var row = 0; row < rows; row++) {
      var title = 0.0;
      final end = math.min(titles.length, (row + 1) * columns);
      for (var i = row * columns; i < end; i++) {
        title = math.max(title, measured.title(titles[i]));
      }
      tops[row] = y;
      extents[row] = cell + title + (row == rows - 1 ? 0 : mainSpacing);
      y += extents[row];
    }
    return GridRowLayout._(tile, extents, tops, y);
  }
}

/// A layout and what it was measured from.
class _CachedLayout {
  _CachedLayout(CoverGridSpec spec, this.layout)
    : titles = spec.titles,
      aspectRatio = spec.coverAspectRatio,
      columns = spec.columns,
      mainSpacing = spec.mainSpacing;

  final List<String> titles;
  final double aspectRatio;
  final int columns;
  final double mainSpacing;
  final GridRowLayout layout;

  bool fits(CoverGridSpec spec) =>
      spec.coverAspectRatio == aspectRatio &&
      spec.columns == columns &&
      spec.mainSpacing == mainSpacing &&
      listEquals(spec.titles, titles);
}

/// Text heights for one set of styles, text size and tile width, kept so a
/// title is laid out once however often its grid is built. A new width or
/// text size is a new set; only the few most recent are kept.
class _MeasuredText {
  _MeasuredText(this.text, this.width) : caption = text.measureCaption(width);

  static const maxSets = 4;
  static const maxLayouts = 16;
  // A map literal keeps the order things were put in.
  static final _sets = <(GridTileText, double), _MeasuredText>{};

  static _MeasuredText of(GridTileText text, double width) {
    final key = (text, width);
    // Taken out and put back, so the most recently used is last.
    final set = _sets.remove(key) ?? _MeasuredText(text, width);
    _sets[key] = set;
    if (_sets.length > maxSets) _sets.remove(_sets.keys.first);
    return set;
  }

  final GridTileText text;
  final double width;
  final double caption;
  final _titles = <String, double>{};
  final layouts = Queue<_CachedLayout>();

  double title(String title) =>
      _titles[title] ??= text.measureTitle(title, width);
}

/// Forgets every measured height: for tests that swap fonts between runs.
@visibleForTesting
void debugClearGridMeasurements() => _MeasuredText._sets.clear();

/// A grid of covers with text under them, as a sliver (Library › Movies,
/// grid with covers; Music: artists, grid with photos). Each row of
/// [CoverGridSpec.columns] cells is one item of a lazily built list whose
/// extents are known up front, so the scroll extent is exact from the first
/// frame and only the rows near the screen are built.
class CoverGridSliver extends StatelessWidget {
  const CoverGridSliver({
    super.key,
    required this.spec,
    required this.itemBuilder,
    this.topPadding = 0,
  });

  final CoverGridSpec spec;

  /// The cell for the item at an index of [CoverGridSpec.titles].
  final IndexedWidgetBuilder itemBuilder;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.only(top: topPadding),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final layout = spec.layoutFor(constraints.crossAxisExtent);
          final count = spec.titles.length;
          return _ExactExtentList(
            height: layout.height,
            itemExtentBuilder: (row, _) => layout.extentOf(row),
            delegate: SliverChildBuilderDelegate(
              childCount: layout.rowCount,
              (context, row) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: spec.crossSpacing,
                children: [
                  for (
                    var i = row * spec.columns;
                    i < math.min(count, (row + 1) * spec.columns);
                    i++
                  )
                    SizedBox(
                      width: layout.tileWidth,
                      child: itemBuilder(context, i),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A [SliverVariedExtentList] that reports its real height. The framework's
/// own answer, while the last row is not built, is the average of the rows
/// built so far times the row count, which moves as rows of other heights
/// scroll in and would make the fast-scroll thumb drift.
class _ExactExtentList extends SliverVariedExtentList {
  const _ExactExtentList({
    required this.height,
    required super.delegate,
    required super.itemExtentBuilder,
  });

  final double height;

  @override
  double? estimateMaxScrollOffset(
    SliverConstraints? constraints,
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => height;
}
