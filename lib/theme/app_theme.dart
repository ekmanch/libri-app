// Theme for Libri.
//
// Colors and fonts come from the design canvas (design/canvas.html) and
// docs/DESIGN.md. Widgets read colors from Theme.of(context) or from
// LibraryColors.of(context), never from literals.
//
// Accent mapping, from S6 and D8: the accent *fill* (the pastel color) is the
// same on both themes and is used for filled surfaces: the "+" button, primary
// buttons, progress bars. Accent *text, icons and outlines* use the fill on
// the dark theme and the darker "ink" on the light theme, where the pastel
// would be too faint. In Material terms:
//   colorScheme.primary          = accent ink on light, accent fill on dark
//   colorScheme.primaryContainer = accent fill, always
//
// One font is bundled: Figtree (Regular, Italic, Medium, SemiBold, Bold,
// ExtraBold) in assets/fonts/, declared in pubspec.yaml. Titles are the
// ExtraBold cut, tightened a little.

import 'package:flutter/material.dart';

import '../data/models/media_type.dart';

enum AccentGroup { vivid, pastel }

/// One selectable accent color. [fill] is used for filled surfaces on both
/// themes. [ink] is the darker variant used for text, icons and outlines on
/// the light theme.
class AccentOption {
  const AccentOption(this.group, this.name, this.fill, this.ink);

  final AccentGroup group;
  final String name;
  final Color fill;
  final Color ink;

  /// Stable id for device preferences, e.g. `vivid/Hot pink`. Names repeat
  /// across groups (Blue, Green), so the group is part of it.
  String get id => '${group.name}/$name';
}

class Accents {
  static const hotPink = AccentOption(
    AccentGroup.vivid,
    'Hot pink',
    Color(0xFFFF7AB6),
    Color(0xFFD6337F),
  );

  static const vivid = <AccentOption>[
    AccentOption(
      AccentGroup.vivid,
      'Violet',
      Color(0xFFA78BFA),
      Color(0xFF7C5CE0),
    ),
    hotPink,
    AccentOption(
      AccentGroup.vivid,
      'Amber',
      Color(0xFFF2B544),
      Color(0xFFA36706),
    ),
    AccentOption(
      AccentGroup.vivid,
      'Green',
      Color(0xFF5EE08A),
      Color(0xFF15803D),
    ),
    AccentOption(
      AccentGroup.vivid,
      'Blue',
      Color(0xFF5AA9FF),
      Color(0xFF1D6FE0),
    ),
  ];

  static const pastel = <AccentOption>[
    AccentOption(
      AccentGroup.pastel,
      'Beige',
      Color(0xFFF9E2AF),
      Color(0xFFA66706),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Rosewater',
      Color(0xFFF5E0DC),
      Color(0xFFAD604F),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Flamingo',
      Color(0xFFF2CDCD),
      Color(0xFFB85759),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Pink',
      Color(0xFFF5C2E7),
      Color(0xFFBA4A9E),
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
      Color(0xFF596ADD),
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
      Color(0xFF017DAF),
    ),
    AccentOption(
      AccentGroup.pastel,
      'Green',
      Color(0xFFA6E3A1),
      Color(0xFF238700),
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
/// platform's monospace face (the F6 preview).
class AppFonts {
  AppFonts._();
  static const body = 'Figtree';
  static const code = 'monospace';
}

/// The Libri mark (F1, F2): a peach left half with a play triangle and a
/// paper right half with three lines. Fixed colors, the same on both themes.
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

  /// A translucent dark well behind a segmented pair or a chip on a plan
  /// header (S1): darker than the page on dark, a neutral fill on light.
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

  /// Fill of an error banner (A12); the text on it stays the main color.
  final Color dangerFill;

  /// The "connected" dot (D6).
  final Color success;

  /// Placeholder blocks while the library loads (D7).
  final Color skeleton;

  /// Outline of an outline button (Cancel, Delete, Replace token): a step
  /// lighter than the field outline.
  final Color buttonOutline;

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
    // 5:1 on the surface, as the S9 hint color (#8A8F96).
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
  );

  // Values from the light mockups D8 and S6. The type colors follow the D8
  // note: as colorful as they can be while readable, 4.5:1 (AA) on white,
  // except Movies (3.8:1, kept on purpose so gold stays gold).
  static const light = LibraryColors(
    surfaceHigh: Color(0xFFE9EBEE),
    dialog: Color(0xFFFFFFFF),
    divider: Color(0xFFE3E5E9),
    muted: Color(0xFF5B616B),
    soft: Color(0xFF3C424A),
    // 4.6:1 on white.
    placeholder: Color(0xFF6F757E),
    dangerText: Color(0xFFC62828),
    neutralFill: Color(0xFFE9EBEE),
    selectedFill: Color(0xFFE9EBEE),
    navFill: Color(0xFFFFFFFF),
    navBorder: Color(0x00000000),
    tray: Color(0xFFE9EBEE),
    trayBorder: Color(0xFFD5D9DE),
    scrim: Color(0x99000000),
    movies: Color(0xFFA87C00),
    shows: Color(0xFF0074DC),
    books: Color(0xFF01872C),
    games: Color(0xFFD63A1F),
    music: Color(0xFF7C3AED),
    anime: Color(0xFFC8157E),
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
    skeleton: Color(0xFFE9EBEE),
    buttonOutline: Color(0xFFC9CED4),
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
  final accentFill = seasonal ?? accent.fill;
  final accentInk = seasonal ?? (isDark ? accent.fill : accent.ink);
  final onFill = isDark ? const Color(0xFF131416) : const Color(0xFF17181B);
  final onInk = isDark ? const Color(0xFF131416) : const Color(0xFFFFFFFF);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: accentInk,
    onPrimary: onInk,
    primaryContainer: accentFill,
    onPrimaryContainer: onFill,
    secondary: accentInk,
    onSecondary: onInk,
    error: ext.dangerText,
    onError: onInk,
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
    extensions: [ext],
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(color: ext.divider, thickness: 1, space: 1),
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
        backgroundColor: accentFill,
        foregroundColor: onFill,
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
      backgroundColor: accentFill,
      foregroundColor: onFill,
      shape: const CircleBorder(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accentFill,
      linearTrackColor: ext.selectedFill,
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
        (states) => states.contains(WidgetState.selected)
            ? accentFill
            : ext.neutralFill,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      // An (empty) thumb icon keeps the thumb 24 px when off too, as in
      // the mockups, instead of Material's shrunken 16 px dot.
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: accentFill,
      textColor: onFill,
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
        borderSide: BorderSide(color: accentInk),
      ),
    ),
  );
}
