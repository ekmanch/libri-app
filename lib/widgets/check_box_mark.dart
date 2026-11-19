import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

/// The tick box in lists of things to tick: square (Library › Add to plan;
/// Library › Series page: choose what to show) or, with [round], a disc (a
/// plan's items, Library › Filter: all Authors). Ticked, it is the accent
/// with a check; empty, an outline. On light the ticked box is the accent at
/// half strength with a dark check, the empty one white with a hairline, and
/// both are raised by a small shadow ([AccentColors]).
class CheckBoxMark extends StatelessWidget {
  const CheckBoxMark({
    super.key,
    required this.checked,
    this.size = 24,
    this.round = false,
  });

  final bool checked;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final accent = AccentColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? accent.tick : accent.boxFill,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(size * 0.29),
        border: checked
            ? Border.all(color: accent.tick, width: accent.boxBorder.width)
            : Border.fromBorderSide(accent.boxBorder),
        boxShadow: accent.tickShadow,
      ),
      child: checked
          ? StrokeIcon(
              AppIcons.check,
              size: round ? size * 14 / 24 : size * 0.6,
              color: accent.onTick,
            )
          : null,
    );
  }
}
