import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class UnderlineTab<T> {
  const UnderlineTab(this.value, this.label, {this.count});

  final T value;
  final String label;

  /// Shown after the label, a step dimmer ("Library 29").
  final int? count;
}

/// A row of tabs across the full width, each an equal share (Library ›
/// Coming soon: Library tab): the label and its count centered, the selected
/// one in the text color with a 2 px accent line under it, the others muted,
/// and a hairline under the whole row that the accent line sits on. 48 dp
/// tall. A label too wide for its share at a large text size shrinks to fit
/// instead of being cut off.
class UnderlineTabs<T> extends StatelessWidget {
  const UnderlineTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<UnderlineTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    return Material(
      type: MaterialType.transparency,
      // The hairline is painted behind the tabs, so the selected tab's line
      // covers it.
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            for (final tab in tabs)
              Expanded(
                child: _Tab(
                  tab,
                  selected: tab.value == selected,
                  onTap: () => onChanged(tab.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab<T> extends StatelessWidget {
  const _Tab(this.tab, {required this.selected, required this.onTap});

  final UnderlineTab<T> tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final style = theme.textTheme.labelMedium!.copyWith(fontSize: 15);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
          ),
          child: SizedBox(
            height: UnderlineTabs.height,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tab.label,
                        maxLines: 1,
                        style: style.copyWith(
                          color: selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (tab.count case final count?) ...[
                        const SizedBox(width: 6),
                        Text(
                          '$count',
                          maxLines: 1,
                          style: style.copyWith(
                            color: selected ? colors.muted : colors.placeholder,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
