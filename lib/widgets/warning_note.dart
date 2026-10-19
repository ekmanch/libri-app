import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

/// A warning inside a dialog (Settings › Disconnect: keep or delete): a red
/// triangle and the text on a faint red field.
class WarningNote extends StatelessWidget {
  const WarningNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.dangerText.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: StrokeIcon(
              AppIcons.warning,
              size: 18,
              color: colors.dangerText,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 14,
                color: colors.soft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
