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
    this.lines = const [],
  });

  final Widget cover;
  final String title;
  final double width;
  final bool picked;
  final VoidCallback onTap;
  final List<String> lines;

  /// The cover's width inside the ring.
  static double imageWidth(double width) => width - 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      selected: picked,
      label: [title, ...lines].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    width: 2,
                    color: picked
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                child: cover,
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
