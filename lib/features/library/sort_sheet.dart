import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/radio_mark.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/sheet_frame.dart';
import 'library_sort.dart';

/// The sort menu (Library › Sort menu). Picks apply at once; Done closes the
/// sheet.
Future<void> showSortSheet(
  BuildContext context, {
  required LibrarySort current,
  required ValueChanged<LibrarySort> onChanged,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => _SortSheet(current: current, onChanged: onChanged),
  );
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({required this.current, required this.onChanged});

  final LibrarySort current;
  final ValueChanged<LibrarySort> onChanged;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late LibrarySort _current = widget.current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return SheetFrame(
      title: 'Sort by',
      action: AppButton(
        label: 'Done',
        compact: true,
        onPressed: () => Navigator.pop(context),
      ),
      child: Column(
        children: [
          for (final sort in LibrarySort.values)
            Semantics(
              button: true,
              selected: sort == _current,
              child: RowInkWell(
                onTap: () {
                  setState(() => _current = sort);
                  widget.onChanged(sort);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.divider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sort.label,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      RadioMark(selected: sort == _current),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "Newest added ⌄" button that opens the sort sheet.
class SortButton extends StatelessWidget {
  const SortButton({super.key, required this.current, required this.onChanged});

  final LibrarySort current;
  final ValueChanged<LibrarySort> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: () =>
          showSortSheet(context, current: current, onChanged: onChanged),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: theme.textTheme.labelMedium,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              current.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          StrokeIcon(
            AppIcons.chevronDown,
            size: 16,
            color: theme.colorScheme.onSurface,
          ),
        ],
      ),
    );
  }
}
