import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'chips.dart';

/// One collapsible tag category: a 44 px header with the number picked and
/// a chevron, and the tags as chips when open. Used by the filter sheet
/// (A2) and the entry form's tag picker (D14). Without [onToggleOpen] the
/// header is a plain label and the group is always open ("New on this
/// entry" in D14).
///
/// A group the user opens scrolls its list just enough to show all of it,
/// never so far that its header leaves the top.
class TagGroup extends StatefulWidget {
  const TagGroup({
    super.key,
    required this.label,
    required this.tags,
    required this.selected,
    required this.open,
    required this.onToggleOpen,
    required this.onToggleTag,
    this.chipStyle = PillChipStyle.accent,
    this.checked = false,
    this.chipHeight = 44,
    this.chipPadding = 14,
  });

  final String label;
  final List<String> tags;
  final Iterable<String> selected;
  final bool open;
  final VoidCallback? onToggleOpen;
  final ValueChanged<String> onToggleTag;

  /// How the chips look: accent fills in the filter sheet, neutral fills
  /// with a check mark in the tag picker.
  final PillChipStyle chipStyle;
  final bool checked;
  final double chipHeight;
  final double chipPadding;

  static const revealDuration = Duration(milliseconds: 250);

  @override
  State<TagGroup> createState() => _TagGroupState();
}

class _TagGroupState extends State<TagGroup> {
  /// Set when the header is tapped while the group is shut. Only a group
  /// the user opens scrolls into view; one the sheet opens by itself (the
  /// first group after the types change) leaves the list where it is.
  bool _opening = false;

  void _toggle() {
    _opening = !widget.open;
    widget.onToggleOpen?.call();
  }

  @override
  void didUpdateWidget(TagGroup old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open && _opening) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
    _opening = false;
  }

  /// Scrolls the enclosing list so the opened group's chips are in view:
  /// its bottom to the bottom of the list, unless that would push its top
  /// out, then its top to the top.
  void _reveal() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (box == null || scrollable == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = scrollable.position;
    final topAtTop = viewport.getOffsetToReveal(box, 0).offset;
    final bottomAtBottom = viewport.getOffsetToReveal(box, 1).offset;
    final target = math
        .min(topAtTop, math.max(position.pixels, bottomAtBottom))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    position.animateTo(
      target,
      duration: TagGroup.revealDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final TagGroup(
      :label,
      :tags,
      :selected,
      :open,
      :onToggleOpen,
      :onToggleTag,
      :chipStyle,
      :checked,
      :chipHeight,
      :chipPadding,
    ) = widget;
    final picked = tags.where(selected.contains).length;
    if (tags.isEmpty) return const SizedBox.shrink();
    final folds = onToggleOpen != null;
    final header = SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
          if (picked > 0)
            Text(
              '$picked selected',
              style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
            ),
          if (folds) ...[
            const SizedBox(width: 8),
            RotatedBox(
              quarterTurns: open ? 2 : 0,
              child: StrokeIcon(
                AppIcons.chevronDown,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (folds)
            Semantics(
              button: true,
              expanded: open,
              // No press highlight: the group folding open or shut is the
              // feedback.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: header,
              ),
            )
          else
            Semantics(header: true, child: header),
          if (open)
            Padding(
              // Room for the chips' 48 dp touch area above the first row.
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    PillChip(
                      label: '#$tag',
                      selected: selected.contains(tag),
                      style: chipStyle,
                      checked: checked,
                      height: chipHeight,
                      horizontalPadding: chipPadding,
                      onTap: () => onToggleTag(tag),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A long group as one row (A2, D14, S9): the label, then "64 authors · 1
/// selected" and a chevron, muted. Opens the full-screen list (A28).
class TagGroupRow extends StatelessWidget {
  const TagGroupRow({
    super.key,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  /// Room the label keeps however long the count is ("Game genres").
  static const _minLabelWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      label: '$label, $detail',
      excludeSemantics: true,
      // No press highlight: the full list opening is the feedback.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          // The count and the chevron sit flush right like a collapsible
          // group's chevron and get the room first; the label takes the
          // rest, at least [_minLabelWidth], and either text gives way
          // with an ellipsis.
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth - 12 - _minLabelWidth)
                        .clamp(0.0, double.infinity),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall!.copyWith(
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StrokeIcon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
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
