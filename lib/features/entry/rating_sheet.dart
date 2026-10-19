import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/labels.dart';
import '../../widgets/sheet_frame.dart';

/// What the rating picker was closed with. [rating] null means cleared.
/// A dismissed sheet resolves to no choice at all.
@immutable
class RatingChoice {
  const RatingChoice(this.rating);

  final int? rating;
}

/// The rating picker (Library › Rating picker): ten buttons, never a slider.
/// [title] names the entry under the heading.
Future<RatingChoice?> showRatingSheet(
  BuildContext context, {
  required String title,
  required int? current,
}) {
  return showAppSheet<RatingChoice>(
    context,
    builder: (context) => RatingSheet(title: title, current: current),
  );
}

class RatingSheet extends StatefulWidget {
  const RatingSheet({super.key, required this.title, required this.current});

  final String title;
  final int? current;

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  late int? _rating = widget.current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    return SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Rating', style: theme.textTheme.titleLarge),
              ),
              AppButton(
                label: 'Done',
                compact: true,
                onPressed: () => Navigator.pop(context, RatingChoice(_rating)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.title,
            style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          for (final row in const [1, 6]) ...[
            if (row > 1) const SizedBox(height: 10),
            Row(
              children: [
                for (var n = row; n < row + 5; n++) ...[
                  if (n > row) const SizedBox(width: 10),
                  Expanded(
                    child: _RatingButton(
                      value: n,
                      selected: n == _rating,
                      onTap: () => setState(() => _rating = n),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '1 is the lowest',
                    style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Text(
                    '10 is the highest',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ratingLabel(_rating),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _rating == null
                      ? null
                      : () => setState(() => _rating = null),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    padding: EdgeInsets.zero,
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  child: const Text('Clear rating'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: selected ? scheme.primaryContainer : scheme.outline,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '$value out of 10',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(
                '$value',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
