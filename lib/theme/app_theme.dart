// Theme for Libri.
//
// Colors and fonts come from the design canvas (design/canvas.html) and
// docs/DESIGN.md. Widgets read colors from Theme.of(context) or from
// LibraryColors.of(context), never from literals.
//
// Accent mapping. The stored accent is one of [Accents]; each has a value
// for the dark themes ([AccentOption.fill]) and one for the light theme
// ([AccentOption.light]).
//
// Dark: the accent is a fill, a text color and an icon color alike.
//
// Light (the Library "Light theme, the rule" note): colors are fills, text
// is neutral. The light accent is used at three strengths, all worked out
// from that one color in [AccentColors]: full for thin fills, half on white
// for a ticked box, a fifth on white (the tint) for selections and main
// buttons. Links and icons that wear the accent on dark are dark gray.
// In Material terms:
//   colorScheme.primary          = the accent at full strength
//   colorScheme.primaryContainer = the accent on dark, its tint on light
// Text and icons never read colorScheme.primary; they read
// AccentColors.of(context).link.
//
// One font is bundled: Figtree (Regular, Italic, Medium, SemiBold, Bold,
// ExtraBold) in assets/fonts/, declared in pubspec.yaml. Titles are the
// ExtraBold cut, tightened a little.

import 'package:flutter/material.dart';

import '../data/models/media_type.dart';

enum AccentGroup { vivid, pastel }

/// One selectable accent color: [fill] in the dark themes, [light] in the
/// light theme (Settings, "Accent colors in the light theme"). The stored
/// setting is the same on both.
class AccentOption {
  const AccentOption(this.group, this.name, this.fill, this.light);

  final AccentGroup group;
  final String name;
  final Color fill;
  final Color light;

  /// The accent as the theme with [brightness] shows it.
  Color of(Brightness brightness) =>
      brightness == Brightness.dark ? fill : light;

  /// Stable id for device preferences, e.g. `vivid/Hot pink`. Names repeat
  /// across groups (Blue, Green), so the group is part of it.
  String get id => '${group.name}/$name';
}

class Accents {
  static const hotPink = AccentOption(
    AccentGroup.vivid,
    'Hot pink',
    Color(0xFFFF7AB6),
    Color(0xFFF74F9E),
  );

  static const vivid = <AccentOption>[
    AccentOption(
      AccentGroup.vivid,
      'Violet',
      Color(0xFFA78BFA),
      Color(0xFF8B5CF6),
    ),
    hotPink,
    AccentOption(
      AccentGroup.vivid,
      'Amber',
      Color(0xFFF2B544),
      Color(0xFFFFB300),
    ),
    AccentOption(
      AccentGroup.vivid,
      'Green',
      Color(0xFF5EE08A),
      Color(0xFF34C759),
    ),
    AccentOption(
      AccentGroup.vivid,
      'Blue',
      Color(0xFF5AA9FF),
      Color(0xFF0A84FF),
    ),
  ];

  static const pastel = <AccentOption>[
    AccentOption(
      AccentGroup.pastel,
      'Beige',
      Color(0xFFF9E2AF),
      Color(0xFFDF8E1D),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Rosewater',
      Color(0xFFF5E0DC),
      Color(0xFFDC8A78),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Flamingo',
      Color(0xFFF2CDCD),
      Color(0xFFDD7878),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Pink',
      Color(0xFFF5C2E7),
      Color(0xFFEA76CB),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Red',
      Color(0xFFF38BA8),
      Color(0xFFD20F39),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Mauve',
      Color(0xFFCBA6F7),
      Color(0xFF8839EF),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Lavender',
      Color(0xFFB4BEFE),
      Color(0xFF7287FD),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Blue',
      Color(0xFF89B4FA),
      Color(0xFF1E66F5),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Sky',
      Color(0xFF89DCEB),
      Color(0xFF04A5E5),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Green',
      Color(0xFFA6E3A1),
      Color(0xFF40A02B),
    ),
  ];

  static const all = <AccentOption>[...vivid, ...pastel];

  static const defaultAccent = hotPink;

  static AccentOption? byId(String id) {
    for (final accent in all) {
      if (accent.id == id) return accent;
    }
    return null;
  }
}

/// Seasonal accents, used only inside a plan with the seasonal theme on.
class SeasonalAccents {
  static const halloween = Color(0xFFF08A3C);
  static const christmas = Color(0xFF35A56A);
}

/// Font families. Figtree is bundled; the code font falls back to the
/// platform's monospace face (the First run › Create a new library preview).
class AppFonts {
  AppFonts._();
  static const body = 'Figtree';
  static const code = 'monospace';
}

/// The Libri mark (First run › Splash; Welcome): a peach left half with a play
/// triangle and a paper right half with three lines. Fixed colors, the same on
/// both themes.
class BrandColors {
  BrandColors._();
  static const peach = Color(0xFFF8B289);
  static const paper = Color(0xFFEDEEF0);
  static const ink = Color(0xFF232428);
}

/// Motion timings shared by widgets.
class AppMotion {
  /// Anchored popup menus (the view menu, the plan menu, the year chip).
  /// Material's default 300 ms reveal feels sluggish for a small menu, so
  /// they open in 150 ms and close in 100 ms.
  static const menu = AnimationStyle(
    duration: Duration(milliseconds: 150),
    reverseDuration: Duration(milliseconds: 100),
  );

  /// A short list or row sliding to a new position on its own, such as the
  /// chip row returning to All. Quick, but visible, so the move is not a
  /// jump.
  static const slide = Duration(milliseconds: 200);

  /// A pushed screen opening and closing ([QuickPageTransitionsBuilder]).
  /// Flutter's 450 ms made every tap feel slow.
  static const page = Duration(milliseconds: 200);
}

/// Flutter's own Android page transition (the new screen fades and slides
/// in a little from the right; the back gesture peeks at the screen
/// below), only quicker: [AppMotion.page] instead of 450 ms. Used on every
/// platform, so the Linux runs show what the phone does.
class QuickPageTransitionsBuilder extends PredictiveBackPageTransitionsBuilder {
  const QuickPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;
}

/// Colors that Material's ColorScheme has no slot for.
@immutable
class LibraryColors extends ThemeExtension<LibraryColors> {
  const LibraryColors({
    required this.surfaceHigh,
    required this.dialog,
    required this.divider,
    required this.muted,
    required this.soft,
    required this.placeholder,
    required this.dangerText,
    required this.neutralFill,
    required this.selectedFill,
    required this.navFill,
    required this.navBorder,
    required this.tray,
    required this.trayBorder,
    required this.scrim,
    required this.movies,
    required this.shows,
    required this.books,
    required this.games,
    required this.music,
    required this.anime,
    required this.cardShadow,
    required this.navShadow,
    required this.coverPlaceholders,
    required this.coverBadge,
    required this.dangerFill,
    required this.success,
    required this.skeleton,
    required this.buttonOutline,
    required this.caution,
    required this.track,
    required this.rail,
    required this.typeColorsAreFills,
    required this.dotRing,
    required this.tagHash,
    required this.coverShadow,
    required this.smallCoverShadow,
    required this.doneDisc,
    required this.doneDiscShadow,
  });

  /// Raised fill: tag chips, the floating navigation pill, sheet buttons.
  final Color surfaceHigh;
  final Color dialog;
  final Color divider;

  /// Secondary text: subtitles, labels, unselected items.
  final Color muted;

  /// Body text that is softer than the main text: dialog bodies, "About".
  final Color soft;
  final Color placeholder;

  /// Destructive actions: red text only. Buttons use [neutralFill] behind it,
  /// never a red fill, and never sit next to an accent-colored button.
  final Color dangerText;
  final Color neutralFill;

  /// Fill of a selected item in a neutral control: pill tabs, type chips,
  /// the "In progress" status mark.
  final Color selectedFill;

  /// Fill of the floating navigation pill: raised on dark, white on light.
  final Color navFill;

  /// Border of the floating navigation pill; transparent on light.
  final Color navBorder;

  /// A translucent dark well behind a segmented pair or a chip on a plan header
  /// (Plans › Plan checklist): darker than the page on dark, a neutral fill on
  /// light.
  final Color tray;

  /// Hairline around a chip on that tray.
  final Color trayBorder;
  final Color scrim;

  final Color movies;
  final Color shows;
  final Color books;
  final Color games;
  final Color music;
  final Color anime;

  /// Empty on dark (cards use a fill); a soft shadow on light.
  final List<BoxShadow> cardShadow;

  /// Shadow under the floating navigation and the "+" button.
  final List<BoxShadow> navShadow;

  /// Fills for cover placeholders until real images arrive (phase 5).
  final List<Color> coverPlaceholders;

  /// Round badge over a cover, e.g. behind the Done check in the grid.
  final Color coverBadge;

  /// Fill of an error banner (Library › Sync and errors); the text on it stays
  /// the main color.
  final Color dangerFill;

  /// The "connected" dot (Settings › Library connection).
  final Color success;

  /// Placeholder blocks while the library loads (First run › First load).
  final Color skeleton;

  /// Outline of an outline button (Cancel, Delete, Replace token): a step
  /// lighter than the field outline.
  final Color buttonOutline;

  /// A heads-up that is not an error yet: the key in the amber circle of the
  /// Library › Token expires soon dialog.
  /// Its field is this at 14% alpha.
  final Color caution;

  /// The track of a progress bar.
  final Color track;

  /// A line that is not a divider: a switch that is off, the part of a
  /// plan's timeline still ahead.
  final Color rail;

  /// True on light, where a type color is too bright to read as text
  /// (yellow is 1.6:1 on white) and is only ever a fill: a dot, the line
  /// under a tab, a bar. What dark writes in the type color, light writes
  /// in neutral text beside a dot ([TypeKicker]) or in the heading gray
  /// ([typeHeading]).
  final bool typeColorsAreFills;

  /// Hairline around a type dot that stands alone with no label (the index
  /// rail in results with several types), so yellow does not vanish on
  /// white. Transparent on dark.
  final Color dotRing;

  /// The "#" of a tag: mid gray on light, the text's own color (null) on
  /// dark.
  final Color? tagHash;

  /// Lifts a cover, an artist photo or an album tile off a white page: a
  /// hairline and a soft shadow. Empty on dark.
  final List<BoxShadow> coverShadow;

  /// The same for the small covers in lists.
  final List<BoxShadow> smallCoverShadow;

  /// The disc behind the Done check on a cover: white with a ring and a
  /// small shadow on light, so it reads on a white cover too.
  final Color doneDisc;
  final List<BoxShadow> doneDiscShadow;

  /// The shadow for a cover [width] dp wide: the small one for the covers
  /// in lists, the large one for tiles, headers and grids.
  List<BoxShadow> coverShadowFor(double width) =>
      width < smallCoverBelow ? smallCoverShadow : coverShadow;

  /// Covers narrower than this are the small ones in lists (40 to 56 dp).
  static const smallCoverBelow = 64.0;

  /// The color of a section heading that names a type or is in a type's
  /// list: the type's color on dark, the heading gray on light.
  Color typeHeading(MediaType t) => typeColorsAreFills ? muted : forType(t);

  Color forType(MediaType t) => switch (t) {
    MediaType.movies => movies,
    MediaType.shows => shows,
    MediaType.books => books,
    MediaType.games => games,
    MediaType.music => music,
    MediaType.anime => anime,
  };

  static LibraryColors of(BuildContext context) =>
      Theme.of(context).extension<LibraryColors>()!;

  static const dark = LibraryColors(
    surfaceHigh: Color(0xFF2A2D31),
    dialog: Color(0xFF26292D),
    divider: Color(0xFF26292D),
    muted: Color(0xFFA3A8AE),
    soft: Color(0xFFD0D4D9),
    // 5:1 on the surface, as the Plans › Edit plan hint color (#8A8F96).
    placeholder: Color(0xFF8A8F96),
    dangerText: Color(0xFFFF6B6B),
    neutralFill: Color(0xFF3A3E44),
    selectedFill: Color(0x24FFFFFF),
    navFill: Color(0xFF2A2D31),
    navBorder: Color(0xFF3A3E44),
    tray: Color(0x660A090D),
    trayBorder: Color(0x38FFFFFF),
    scrim: Color(0xCC08090A),
    movies: Color(0xFFF2B544),
    shows: Color(0xFF7FB7FF),
    books: Color(0xFF8FD694),
    games: Color(0xFFFF8F7A),
    music: Color(0xFFC4A7FF),
    anime: Color(0xFFFF8CC1),
    cardShadow: [],
    navShadow: [
      BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
    coverPlaceholders: _coverPlaceholders,
    coverBadge: Color(0xD9131416),
    dangerFill: Color(0xFF3A2323),
    success: Color(0xFF8FD694),
    skeleton: Color(0xFF1D1F22),
    buttonOutline: Color(0xFF4A4F57),
    caution: Color(0xFFF2B544),
    track: Color(0x24FFFFFF),
    rail: Color(0xFF3A3E44),
    typeColorsAreFills: false,
    dotRing: Color(0x00000000),
    tagHash: null,
    coverShadow: [],
    smallCoverShadow: [],
    doneDisc: Color(0xD9131416),
    doneDiscShadow: [],
  );

  // Values from the Library "Type colors" and "Light theme, the rule" notes
  // (canvas revision of 2026-11-19). The type colors are bright fills, never
  // text. Grays: dividers and tracks #E1E4E8, raised surfaces #EEF0F2, a gray
  // selection #ECEEF0; the outline of a control stays #D5D9DE (the color
  // scheme's outline), since #E1E4E8 is too faint for an edge outdoors.
  static const light = LibraryColors(
    surfaceHigh: Color(0xFFEEF0F2),
    dialog: Color(0xFFFFFFFF),
    divider: Color(0xFFE1E4E8),
    muted: Color(0xFF5B616B),
    soft: Color(0xFF3C424A),
    // 4.6:1 on white.
    placeholder: Color(0xFF6F757E),
    dangerText: Color(0xFFC62828),
    neutralFill: Color(0xFFEEF0F2),
    selectedFill: Color(0xFFECEEF0),
    navFill: Color(0xFFFFFFFF),
    navBorder: Color(0x00000000),
    tray: Color(0xFFE9EBEE),
    trayBorder: Color(0xFFD5D9DE),
    scrim: Color(0x99000000),
    movies: Color(0xFFFFC400),
    shows: Color(0xFF0A84FF),
    books: Color(0xFF34C759),
    games: Color(0xFFFF5A4F),
    music: Color(0xFFAF52DE),
    anime: Color(0xFFF74F9E),
    cardShadow: [
      BoxShadow(color: Color(0x1A14161C), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1A14161C), blurRadius: 18, offset: Offset(0, 6)),
    ],
    navShadow: [
      BoxShadow(color: Color(0x1F14161C), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x2914161C),
        blurRadius: 28,
        offset: Offset(0, 10),
      ),
    ],
    coverPlaceholders: _coverPlaceholders,
    coverBadge: Color(0xD9FFFFFF),
    dangerFill: Color(0xFFFBE9E7),
    success: Color(0xFF1E7B34),
    skeleton: Color(0xFFEEF0F2),
    buttonOutline: Color(0xFFC9CED4),
    // The amber of the dark theme darkened for white: 4.5:1.
    caution: Color(0xFF8A5A00),
    track: Color(0xFFE1E4E8),
    rail: Color(0xFFE1E4E8),
    typeColorsAreFills: true,
    dotRing: Color(0x1A14161C),
    tagHash: Color(0xFF9AA0A8),
    // 0 0 0 1px rgba(20,22,28,0.06), 0 1px 3px rgba(20,22,28,0.11),
    // 0 6px 14px rgba(20,22,28,0.13).
    coverShadow: [
      BoxShadow(color: Color(0x0F14161C), spreadRadius: 1),
      BoxShadow(color: Color(0x1C14161C), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x2114161C), blurRadius: 14, offset: Offset(0, 6)),
    ],
    // 0 0 0 1px rgba(20,22,28,0.06), 0 1px 2px rgba(20,22,28,0.10),
    // 0 3px 8px rgba(20,22,28,0.12).
    smallCoverShadow: [
      BoxShadow(color: Color(0x0F14161C), spreadRadius: 1),
      BoxShadow(color: Color(0x1A14161C), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1F14161C), blurRadius: 8, offset: Offset(0, 3)),
    ],
    doneDisc: Color(0xFFFFFFFF),
    // A hairline ring, rgba(20,22,28,0.12), and a small shadow.
    doneDiscShadow: [
      BoxShadow(color: Color(0x1F14161C), spreadRadius: 1),
      BoxShadow(color: Color(0x4014161C), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  static const _coverPlaceholders = [
    Color(0xFF4B5F8A),
    Color(0xFF8A6E3F),
    Color(0xFF3F6B8A),
    Color(0xFF8A553F),
  ];

  @override
  LibraryColors copyWith() => this;

  @override
  LibraryColors lerp(ThemeExtension<LibraryColors>? other, double t) =>
      t < 0.5 || other is! LibraryColors ? this : other;
}

/// The accent at the strengths a theme uses it. Built per theme by
/// [buildTheme], since every value follows the chosen accent.
///
/// Dark: one color for everything. Light: [full] for thin fills (progress
/// bars, switches that are on, the outline of a focused search box, the
/// line under Home), [tick] (half on white) for a ticked box, [tint] (a
/// fifth on white) under normal dark text for selections and main buttons,
/// and no accent-colored text at all: [link] is dark gray. Inside a plan
/// with a seasonal look every strength is the seasonal color, as before
/// the light theme was reworked (its light look is not decided yet).
@immutable
class AccentColors extends ThemeExtension<AccentColors> {
  const AccentColors({
    required this.full,
    required this.tint,
    required this.onTint,
    required this.selection,
    required this.tick,
    required this.onTick,
    required this.tickShadow,
    required this.boxFill,
    required this.boxBorder,
    required this.link,
  });

  /// Thin fills. The same as `colorScheme.primary`.
  final Color full;

  /// Main buttons, the "+" button, chosen chips, the picked rating. The
  /// same as `colorScheme.primaryContainer`.
  final Color tint;
  final Color onTint;

  /// A selection that is neutral gray on dark and the tint on light: the
  /// Library / Plans pill, a status chip, an active filter or tag chip, the
  /// index rail's current label. Other selections stay gray
  /// ([LibraryColors.selectedFill]).
  final Color selection;

  /// A ticked box (plan items, checkboxes) and the check on it.
  final Color tick;
  final Color onTick;

  /// Raises a tick box, ticked or empty, on light. Empty on dark.
  final List<BoxShadow> tickShadow;

  /// An empty tick box: a white disc with a hairline on light, an outline
  /// on dark.
  final Color boxFill;
  final BorderSide boxBorder;

  /// Links and icons that wear the accent on dark ("See all", "Clear all",
  /// "Rate", "Try again", "Edit tracks", the Done check in a list, an
  /// outlined badge): dark gray on light, drawn semibold, not underlined.
  final Color link;

  /// [strength] of [color] on white: `mix(#F74F9E, 0.2)` is the hot pink
  /// tint.
  static Color mix(Color color, double strength) =>
      Color.lerp(const Color(0xFFFFFFFF), color, strength)!;

  static const tintStrength = 0.2;
  static const tickStrength = 0.5;

  /// One color at every strength: the dark themes, and a seasonal plan.
  factory AccentColors.solid(
    Color accent, {
    required Color onAccent,
    required LibraryColors colors,
  }) => AccentColors(
    full: accent,
    tint: accent,
    onTint: onAccent,
    selection: colors.selectedFill,
    tick: accent,
    onTick: onAccent,
    tickShadow: const [],
    boxFill: const Color(0x00000000),
    boxBorder: BorderSide(color: colors.placeholder, width: 2),
    link: accent,
  );

  /// The light theme's three strengths of [accent].
  factory AccentColors.light(Color accent) {
    final tint = mix(accent, tintStrength);
    return AccentColors(
      full: accent,
      tint: tint,
      onTint: const Color(0xFF17181B),
      selection: tint,
      tick: mix(accent, tickStrength),
      onTick: const Color(0xFF17181B),
      // 0 1px 3px rgba(20,22,28,0.20).
      tickShadow: const [
        BoxShadow(
          color: Color(0x3314161C),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
      boxFill: const Color(0xFFFFFFFF),
      boxBorder: const BorderSide(color: Color(0x1F14161C)),
      link: const Color(0xFF2F343B),
    );
  }

  static AccentColors of(BuildContext context) =>
      Theme.of(context).extension<AccentColors>()!;

  @override
  AccentColors copyWith() => this;

  @override
  AccentColors lerp(ThemeExtension<AccentColors>? other, double t) =>
      t < 0.5 || other is! AccentColors ? this : other;
}

/// Builds the app theme.
///
/// [accent] is the user's choice from Settings. Inside a plan with the
/// seasonal theme on, wrap that screen in a Theme built with [seasonal] set.
ThemeData buildTheme({
  required Brightness brightness,
  AccentOption accent = Accents.defaultAccent,
  Color? seasonal,
}) {
  final isDark = brightness == Brightness.dark;
  final ext = isDark ? LibraryColors.dark : LibraryColors.light;

  final background = isDark ? const Color(0xFF131416) : const Color(0xFFFFFFFF);
  final surface = isDark ? const Color(0xFF1D1F22) : const Color(0xFFFFFFFF);
  final outline = isDark ? const Color(0xFF3A3E44) : const Color(0xFFD5D9DE);
  final text = isDark ? const Color(0xFFEEF0F2) : const Color(0xFF17181B);
  final onFill = isDark ? const Color(0xFF131416) : const Color(0xFF17181B);
  final accents = isDark || seasonal != null
      ? AccentColors.solid(
          seasonal ?? accent.fill,
          onAccent: onFill,
          colors: ext,
        )
      : AccentColors.light(accent.light);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: accents.full,
    onPrimary: onFill,
    primaryContainer: accents.tint,
    onPrimaryContainer: accents.onTint,
    secondary: accents.full,
    onSecondary: onFill,
    error: ext.dangerText,
    onError: isDark ? const Color(0xFF131416) : const Color(0xFFFFFFFF),
    surface: surface,
    onSurface: text,
    onSurfaceVariant: ext.muted,
    surfaceContainerHighest: ext.surfaceHigh,
    outline: outline,
    outlineVariant: ext.divider,
    scrim: ext.scrim,
  );

  final body =
      (isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme).apply(
        fontFamily: AppFonts.body,
        bodyColor: text,
        displayColor: text,
      );

  // Headings (screen titles, plan names, dialog titles): Figtree ExtraBold
  // with -0.03em letter spacing (canvas revision of 2026-10-18).
  TextStyle title(double size, {double? height}) => TextStyle(
    fontFamily: AppFonts.body,
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.03 * size,
    height: height,
    color: text,
  );

  final textTheme = body.copyWith(
    // Screen titles: 34 on top-level screens, 28 with a back arrow, 26 in sheets.
    headlineLarge: title(34),
    headlineMedium: title(28),
    headlineSmall: title(26, height: 1.15),
    // Dialog titles and plan card titles.
    titleLarge: title(22, height: 1.2),
    // Row title.
    titleMedium: body.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    // Row subtitle: use with FontStyle.italic.
    bodySmall: body.bodySmall?.copyWith(fontSize: 13.5, color: ext.muted),
    bodyMedium: body.bodyMedium?.copyWith(fontSize: 15.5, height: 1.45),
    // Section and field labels: uppercase, set in the widget.
    labelSmall: body.labelSmall?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.04,
      color: ext.muted,
    ),
    // Chips, navigation items and small buttons.
    labelMedium: body.labelMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    // Buttons.
    labelLarge: body.labelLarge?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // The same sizes on every platform: Material would shrink buttons and
    // fields by 8 px on desktop, and the Linux build is for checking
    // screens against the canvas.
    visualDensity: VisualDensity.standard,
    fontFamily: AppFonts.body,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: textTheme,
    extensions: [ext, accents],
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const QuickPageTransitionsBuilder(),
      },
    ),
    dividerTheme: DividerThemeData(color: ext.divider, thickness: 1, space: 1),
    // Messages at the bottom are swiped away sideways, as on Android.
    snackBarTheme: const SnackBarThemeData(
      dismissDirection: DismissDirection.horizontal,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: title(28),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBarrierColor: ext.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ext.dialog,
      barrierColor: ext.scrim,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accents.tint,
        foregroundColor: accents.onTint,
        disabledBackgroundColor: ext.surfaceHigh,
        disabledForegroundColor: ext.muted,
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
        foregroundColor: text,
        side: BorderSide(color: ext.buttonOutline),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: text,
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: ext.muted,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accents.tint,
      foregroundColor: accents.onTint,
      shape: const CircleBorder(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accents.full,
      linearTrackColor: ext.track,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? ext.surfaceHigh : ext.dialog,
      elevation: 12,
      shadowColor: const Color(0x99000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: ext.navBorder),
      ),
      textStyle: textTheme.titleMedium,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? onFill : ext.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accents.full : ext.rail,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      // An (empty) thumb icon keeps the thumb 24 px when off too, as in
      // the mockups, instead of Material's shrunken 16 px dot.
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: accents.tint,
      textColor: accents.onTint,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? background : ext.surfaceHigh,
      hintStyle: TextStyle(color: ext.placeholder),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accents.full),
      ),
    ),
  );
}
