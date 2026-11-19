import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One cover to pick from (Library › Series page (from a series row): Series
/// cover; Add / edit entry › Pick a cover): the [cover], ringed in the accent
/// when [picked], the [title] under it and up to a few muted [lines] ("1975
/// · Hardcover", "Your pick"). [cover] is built at [imageWidth] of [width].
class CoverChoice extends StatelessWidget {
  const CoverChoice({
    super.key,
    required this.cover,
    required this.title,
    required this.width,
    required this.picked,
    required this.onTap,
    this.onLongPress,
    this.badge,
    this.badgeAccent = false,
    this.round = false,
    this.lines = const [],
  });

  final Widget cover;
  final String title;
  final double width;
  final bool picked;
  final VoidCallback onTap;

  /// A long press, e.g. the Delete file sheet of one of your own covers.
  final VoidCallback? onLongPress;

  /// A small pill in the cover's top left corner: "Yours" on one of your
  /// own covers (dark), "New" on an online cover that turned up later
  /// (the accent, with [badgeAccent]).
  final String? badge;
  final bool badgeAccent;

  /// A round tile (Music › Pick a photo): the ring follows the disc.
  final bool round;
  final List<String> lines;

  /// The cover's width inside the ring.
  static double imageWidth(double width) => width - 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final accent = AccentColors.of(context);
    return Semantics(
      button: true,
      selected: picked,
      label: [title, ?badge, ...lines].join(', '),
      onLongPressHint: onLongPress == null ? null : 'More',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: round ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: round ? null : BorderRadius.circular(10),
                  border: Border.all(
                    width: 2,
                    color: picked
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                child: badge == null
                    ? cover
                    : Stack(
                        children: [
                          cover,
                          Positioned(
                            left: round ? 0 : 4,
                            top: round ? 0 : 4,
                            child: Container(
                              height: 20,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: badgeAccent
                                    ? accent.tick
                                    : colors.coverBadge,
                              ),
                              child: Text(
                                badge!,
                                textScaler: TextScaler.noScaling,
                                style: theme.textTheme.labelSmall!.copyWith(
                                  fontSize: 11,
                                  height: 1,
                                  letterSpacing: 0,
                                  fontWeight: FontWeight.w700,
                                  color: badgeAccent
                                      ? accent.onTick
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium!.copyWith(fontSize: 13),
              ),
              for (final line in lines) ...[
                const SizedBox(height: 2),
                Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    fontSize: 12,
                    color: colors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A grid of [CoverChoice]s, three to a row, as both cover sheets lay them
/// out. [itemBuilder] makes the choice at index i for the given width.
class CoverChoiceGrid extends StatelessWidget {
  const CoverChoiceGrid({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.runSpacing = 12,
  });

  final int count;

  /// The gap between rows; the columns keep 12.
  final double runSpacing;
  final Widget Function(int index, double width) itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 12.0;
      final width = (constraints.maxWidth - 2 * gap) / 3;
      return Wrap(
        spacing: gap,
        runSpacing: runSpacing,
        children: [for (var i = 0; i < count; i++) itemBuilder(i, width)],
      );
    },
  );
}
