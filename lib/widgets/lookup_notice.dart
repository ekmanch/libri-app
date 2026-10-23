import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A line in place of lookup results (Add / edit entry › New entry: pick a
/// match; Pick a cover): "Looking up…" with a spinner, nothing found, or a
/// failure with "Try again" when [onRetry] is given.
class LookupNotice extends StatelessWidget {
  const LookupNotice(
    this.text, {
    super.key,
    this.spinner = false,
    this.onRetry,
  });

  final String text;
  final bool spinner;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          if (spinner) ...[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                textStyle: theme.textTheme.labelMedium,
                minimumSize: const Size(48, 48),
              ),
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}
