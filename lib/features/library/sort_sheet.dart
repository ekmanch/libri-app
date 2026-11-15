import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/radio_mark.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/sheet_frame.dart';
import 'library_sort.dart';

/// The sort menu (Library › Sort menu; Music: sort menu, artists) with the
/// list's [options]. Picks apply at once; Done closes the sheet.
Future<void> showSortSheet<T extends SortOption>(
  BuildContext context, {
  required T current,
  required List<T> options,
  required ValueChanged<T> onChanged,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) =>
        _SortSheet<T>(current: current, options: options, onChanged: onChanged),
  );
}

class _SortSheet<T extends SortOption> extends StatefulWidget {
  const _SortSheet({
    required this.current,
    required this.options,
    required this.onChanged,
  });

  final T current;
  final List<T> options;
  final ValueChanged<T> onChanged;

  @override
  State<_SortSheet<T>> createState() => _SortSheetState<T>();
}

class _SortSheetState<T extends SortOption> extends State<_SortSheet<T>> {
  late T _current = widget.current;

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
          for (final sort in widget.options)
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

/// The "Newest added ⌄" button that opens the sort sheet with [options].
class SortButton<T extends SortOption> extends StatelessWidget {
  const SortButton({
    super.key,
    required this.current,
    required this.options,
    required this.onChanged,
  });

  final T current;
  final List<T> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: () => showSortSheet<T>(
        context,
        current: current,
        options: options,
        onChanged: onChanged,
      ),
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
