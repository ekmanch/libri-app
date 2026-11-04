import 'package:flutter/material.dart';

import '../../data/models/season_split.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/sheet_frame.dart';

/// The "Split into" field of the Seasons section (Add / edit entry › Edit
/// an anime: split into seasons): a field-shaped button with the small
/// label over the split's name, "6 seasons, one per arc" or "Set by hand",
/// which opens [showSplitSheet]. Only shown when the sources offer more
/// than one distinct split.
class SplitField extends StatelessWidget {
  const SplitField({super.key, required this.value, required this.onTap});

  /// "6 seasons, one per arc"; "Set by hand".
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: theme.colorScheme.outline),
    );
    return Semantics(
      button: true,
      label: 'Split into, $value',
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Split into',
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                          fontSize: 13,
                          color: colors.muted,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        value,
                        style: theme.textTheme.titleMedium!.copyWith(
                          fontSize: 15.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StrokeIcon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: colors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The split sheet (Add / edit entry › Split into: pick a split): each
/// distinct split once, described by its shape alone (never a source's
/// name), the one Libri would pick marked Automatic, then Set by hand. A
/// pick calls [onPick] at once with the split, or null for Set by hand,
/// and the sheet stays open until Done. [selected] is the split the
/// seasons are in now, null for seasons set by hand; [subtitle] reads
/// "Hunter x Hunter · 148 episodes".
Future<void> showSplitSheet(
  BuildContext context, {
  required String subtitle,
  required List<SeasonSplit> splits,
  required SeasonSplit? selected,
  required ValueChanged<SeasonSplit?> onPick,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => SplitSheet(
      subtitle: subtitle,
      splits: splits,
      selected: selected,
      onPick: onPick,
    ),
  );
}

class SplitSheet extends StatefulWidget {
  const SplitSheet({
    super.key,
    required this.subtitle,
    required this.splits,
    required this.selected,
    required this.onPick,
  });

  final String subtitle;
  final List<SeasonSplit> splits;
  final SeasonSplit? selected;
  final ValueChanged<SeasonSplit?> onPick;

  static const byHandLabel = 'Set by hand';
  static const byHandDetail =
      'Add, name and date seasons yourself. Checks won’t change them.';
  static const note =
      'What you’ve marked moves with the episodes: a split never loses '
      'a status. Kept until you change it here; new seasons are added the '
      'same way.';

  /// The splits as listed: fewest seasons first, the sources' order among
  /// equals.
  static List<SeasonSplit> ordered(List<SeasonSplit> splits) {
    final listed = [...splits];
    final order = {for (final (i, s) in splits.indexed) s: i};
    listed.sort((a, b) {
      final byCount = a.count.compareTo(b.count);
      return byCount != 0 ? byCount : order[a]!.compareTo(order[b]!);
    });
    return listed;
  }

  @override
  State<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<SplitSheet> {
  late SeasonSplit? _selected = widget.selected;
  late final bool _byHandAtFirst = widget.selected == null;
  bool _byHand = false;

  @override
  void initState() {
    super.initState();
    _byHand = _byHandAtFirst;
  }

  void _pick(SeasonSplit? split) {
    if (split == _selected && (split != null || _byHand)) return;
    setState(() {
      _selected = split;
      _byHand = split == null;
    });
    widget.onPick(split);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final titleStyle = theme.textTheme.headlineSmall!;
    final automatic = SeasonSplit.automatic(widget.splits);
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      height: 1.35,
      color: colors.muted,
    );
    Widget row({
      required String label,
      required String detail,
      required bool selected,
      required bool automatic,
      required VoidCallback onTap,
    }) {
      return Semantics(
        button: true,
        selected: selected,
        label: [label, if (automatic) 'automatic', detail].join(', '),
        excludeSemantics: true,
        child: RowInkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: label,
                              style: theme.textTheme.bodyMedium!.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (automatic)
                              TextSpan(
                                text: '  Automatic',
                                style: theme.textTheme.labelMedium!.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(detail, style: muted),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 12),
                  StrokeIcon(
                    AppIcons.checkBold,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SheetFrame(
      scrollable: true,
      // Done centered on the title and its subtitle, as drawn.
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Split into', style: titleStyle),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 14,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Done',
            compact: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final split in SplitSheet.ordered(widget.splits))
            row(
              label: split.label,
              detail: split.detail,
              selected: !_byHand && _selected?.id == split.id,
              automatic: split.id == automatic?.id,
              onTap: () => _pick(split),
            ),
          row(
            label: SplitSheet.byHandLabel,
            detail: SplitSheet.byHandDetail,
            selected: _byHand,
            automatic: false,
            onTap: () => _pick(null),
          ),
          const SizedBox(height: 8),
          Text(
            SplitSheet.note,
            style: theme.textTheme.bodySmall!.copyWith(
              fontStyle: FontStyle.normal,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
