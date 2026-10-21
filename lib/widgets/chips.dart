import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'touch_target.dart';

/// How a selected [PillChip] is shown.
enum PillChipStyle {
  /// Neutral fill, muted when unselected: the type chips on the library home.
  neutral,

  /// Accent fill: choices in the filter sheet and the tag picker.
  accent,
}

/// A 44 px selectable pill with an optional color dot.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.style = PillChipStyle.neutral,
    this.dotColor,
    this.horizontalPadding = 14,
    this.checked = false,
    this.height = 44,
    this.badge,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A long press, where the chip has one: a tag in the picker opens its
  /// categories (Add / edit entry › Tag picker).
  final VoidCallback? onLongPress;
  final PillChipStyle style;
  final Color? dotColor;

  /// Shows a check before the label while selected (the tag picker,
  /// Add / edit entry › Tag picker, and the platform chips in
  /// Add / edit entry).
  final bool checked;

  /// 44 px by default; the tag picker's chips are 40.
  final double height;

  /// A small word after the label, e.g. "new" on a tag not saved yet.
  final String? badge;

  /// Smaller in tight grids, like the six "Released" chips in the filter
  /// sheet. With a bounded width the chip fills it and centers its label.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final accent = style == PillChipStyle.accent;
    final background = selected
        ? (accent ? scheme.primaryContainer : colors.selectedFill)
        : Colors.transparent;
    final foreground = selected
        ? (accent ? scheme.onPrimaryContainer : scheme.onSurface)
        : (accent ? scheme.onSurface : scheme.onSurfaceVariant);
    final border = selected
        ? (accent ? scheme.primaryContainer : Colors.transparent)
        : scheme.outline;
    return TouchTarget(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: background,
          shape: StadiumBorder(side: BorderSide(color: border)),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            customBorder: const StadiumBorder(),
            child: Container(
              height: height,
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (checked && selected) ...[
                    StrokeIcon(AppIcons.check, size: 14, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  if (dotColor != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium!.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    ChipBadge(badge!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tiny "new" word on a tag chip whose tag is not in the library yet.
class ChipBadge extends StatelessWidget {
  const ChipBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.selectedFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.muted,
        ),
      ),
    );
  }
}

/// A small read-only tag, shown as "#name". [isNew] adds the "new" badge.
class TagChip extends StatelessWidget {
  const TagChip(
    this.name, {
    super.key,
    this.isNew = false,
    this.detail,
    this.mutedDetail = false,
  });

  final String name;
  final bool isNew;

  /// The role after the name for a tag in more than one category:
  /// "#clint-eastwood · Actor" ("Director, Actor" in details).
  final String? detail;

  /// Whether the role is in the muted color, as in details (Library ›
  /// Entry details: tag in two categories); the form's Tags box keeps it
  /// in the text color.
  final bool mutedDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: LibraryColors.of(context).surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A long name (#the-brothers-grimm) is cut rather than pushed
          // past the chip's edge.
          Flexible(
            child: Text.rich(
              TextSpan(
                text: '#$name',
                children: [
                  if (detail != null)
                    TextSpan(
                      text: ' · $detail',
                      style: mutedDetail
                          ? TextStyle(color: LibraryColors.of(context).muted)
                          : null,
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isNew) ...[const SizedBox(width: 6), const ChipBadge('new')],
        ],
      ),
    );
  }
}

/// A chip with a dashed outline and a plus: something that is not there yet,
/// like a suggested tag or "Other…" among the platforms (Add / edit entry).
class DashedChip extends StatelessWidget {
  const DashedChip({
    super.key,
    required this.label,
    required this.onTap,
    this.badge,
    this.height = 40,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback onTap;
  final String? badge;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TouchTarget(
      child: Semantics(
        button: true,
        label: semanticsLabel,
        excludeSemantics: semanticsLabel != null,
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: CustomPaint(
              painter: DashedStadiumPainter(theme.colorScheme.outline),
              child: Container(
                height: height,
                padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StrokeIcon(
                      AppIcons.plus,
                      size: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 6),
                    // A long suggestion ("#post-apocalyptic" with its "new"
                    // badge) is cut off rather than overflowing a 360 dp row.
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium!.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      ChipBadge(badge!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1 px dashed stadium outline, for something not set yet: a suggested
/// chip, a season without a status.
class DashedStadiumPainter extends CustomPainter {
  const DashedStadiumPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(0.5),
          Radius.circular(size.height / 2),
        ),
      );
    const dash = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(DashedStadiumPainter old) => old.color != color;
}

/// A 44 px chip for an active filter, with a cross that removes it.
class RemovableChip extends StatelessWidget {
  const RemovableChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Remove $label',
      excludeSemantics: true,
      child: Material(
        color: LibraryColors.of(context).selectedFill,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onRemove,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: 6),
                StrokeIcon(
                  AppIcons.closeBold,
                  size: 14,
                  color: theme.colorScheme.onSurface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
