import 'package:flutter/foundation.dart';
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
/// instead of being cut off. With a [position] the accent line follows a
/// swipe between the tabs' pages.
class UnderlineTabs<T> extends StatelessWidget {
  const UnderlineTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.position,
  });

  final List<UnderlineTab<T>> tabs;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Where the accent line is, counted in tabs from the first: 1.5 is
  /// halfway between the second and the third. Pages swiped under the tabs
  /// give their scroll position here and the line moves with the finger,
  /// without this widget building again. Null: under [selected].
  final ValueListenable<double>? position;

  static const height = 48.0;

  /// The accent line, for tests.
  static const lineKey = ValueKey('underline-tabs-line');

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final index = tabs.indexWhere((tab) => tab.value == selected);
    Widget line(double at) => Align(
      // The line is one tab wide: -1 puts it under the first, 1 the last.
      alignment: AlignmentDirectional(
        tabs.length < 2 ? 0 : 2 * at / (tabs.length - 1) - 1,
        0,
      ),
      child: FractionallySizedBox(
        widthFactor: 1 / tabs.length,
        heightFactor: 1,
        child: ColoredBox(key: lineKey, color: accent),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // The hairline is painted behind the accent line, which covers
          // it.
          DecoratedBox(
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
          if (index >= 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2,
              child: IgnorePointer(
                child: switch (position) {
                  final position? => ValueListenableBuilder(
                    valueListenable: position,
                    builder: (context, at, _) => line(at),
                  ),
                  null => line(index.toDouble()),
                },
              ),
            ),
        ],
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
    );
  }
}
