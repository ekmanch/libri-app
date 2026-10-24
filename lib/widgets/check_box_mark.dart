import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

/// The square check in lists of things to tick (Library › Add to plan;
/// Library › Series page: choose what to show): the accent fill with a check
/// when [checked], an empty outline when not.
class CheckBoxMark extends StatelessWidget {
  const CheckBoxMark({super.key, required this.checked, this.size = 24});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = LibraryColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.29),
        border: Border.all(
          color: checked ? scheme.primaryContainer : colors.placeholder,
          width: 2,
        ),
      ),
      child: checked
          ? StrokeIcon(
              AppIcons.check,
              size: size * 0.6,
              color: scheme.onPrimaryContainer,
            )
          : null,
    );
  }
}
