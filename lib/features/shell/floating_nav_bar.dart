import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';

enum ShellTab { library, plans }

/// The floating pill with the two destinations, Library and Plans.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ShellTab selected;
  final ValueChanged<ShellTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.navFill,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: colors.navBorder),
        boxShadow: colors.navShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavItem(
            label: 'Library',
            icon: AppIcons.library,
            selected: selected == ShellTab.library,
            onTap: () => onSelect(ShellTab.library),
          ),
          const SizedBox(width: 4),
          _NavItem(
            label: 'Plans',
            icon: AppIcons.plans,
            selected: selected == ShellTab.plans,
            onTap: () => onSelect(ShellTab.plans),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final StrokeIconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        // Neutral gray on dark, the accent's tint on light.
        color: selected
            ? AccentColors.of(context).selection
            : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round accent "+" button to the right of the navigation pill: the
/// accent on dark, its tint under a dark plus on light, with the same shadow.
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.label, required this.onPressed});

  /// Semantic label: "New entry" or "New plan".
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = LibraryColors.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: colors.navShadow,
      ),
      child: Material(
        color: scheme.primaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Tooltip(
            message: label,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: StrokeIcon(
                  AppIcons.plus,
                  size: 24,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
