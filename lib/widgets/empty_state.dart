import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_buttons.dart';
import 'app_icons.dart';

/// Centered icon, title, one line of help and an optional action (Library ›
/// Empty states).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final StrokeIconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: colors.cardShadow,
            ),
            child: Center(
              child: StrokeIcon(icon, size: 24, color: colors.muted),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.muted),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            AppButton(label: actionLabel!, onPressed: onAction, compact: true),
          ],
        ],
      ),
    );
  }
}
