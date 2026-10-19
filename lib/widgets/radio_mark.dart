import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The round selection mark in sort and option lists (Library › Sort menu).
class RadioMark extends StatelessWidget {
  const RadioMark({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = LibraryColors.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : colors.placeholder,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}
