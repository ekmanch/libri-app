import 'package:flutter/material.dart';

import 'app_icons.dart';

/// The row that offers to create the tag a search names (Add / edit entry ›
/// Tag picker; Library › Tag picker: all Authors, create a tag): a plus and
/// "Create “#gothic”", or "Create “#fredrik-backman” in Authors" on a
/// category's own page ([category] is its label). [tag] is the name as it
/// will be stored, already normalized.
class CreateTagRow extends StatelessWidget {
  const CreateTagRow({
    super.key,
    required this.tag,
    required this.onTap,
    this.category,
  });

  final String tag;
  final String? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = category == null ? '' : ' in $category';
    return Semantics(
      button: true,
      label: 'Create #$tag$where',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            // The vertical padding only shows once a long name wraps.
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                StrokeIcon(
                  AppIcons.plus,
                  size: 16,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Create “#$tag”$where',
                    style: theme.textTheme.labelLarge,
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
