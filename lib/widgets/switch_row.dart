import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SwitchRowStyle {
  /// On a card with a hairline border: the plan form (Plans › Edit plan; New
  /// plan).
  card,

  /// A plain row with a hairline under it: Settings.
  line,
}

/// A labeled switch with a line of help under the label. The help text may
/// change with the value ("New plans place entries on a timeline.").
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.help,
    this.style = SwitchRowStyle.card,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String help;
  final SwitchRowStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final helpStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: style == SwitchRowStyle.card ? 13.5 : 13,
      fontStyle: FontStyle.normal,
      height: 1.4,
    );
    final toggle = Switch(value: value, onChanged: onChanged);
    return switch (style) {
      SwitchRowStyle.card => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                toggle,
              ],
            ),
            Text(help, style: helpStyle),
          ],
        ),
      ),
      SwitchRowStyle.line => Container(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(help, style: helpStyle),
                ],
              ),
            ),
            const SizedBox(width: 12),
            toggle,
          ],
        ),
      ),
    };
  }
}
