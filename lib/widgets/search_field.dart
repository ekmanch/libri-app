import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'touch_target.dart';

/// The one search box (Library › Search: Music › Artists; Add / edit entry ›
/// New entry: pick a match, and the tag searches in Library › Filter sheet;
/// Add / edit entry › Tag picker; Plans › Edit plan): a 52 px rounded field
/// with a magnifier, the text inside it and a clear button once there is
/// text. The text field inside draws no border of its own, so there is never
/// a second rectangle inside the first.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    this.controller,
    required this.hintText,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.search,
    this.clearTooltip = 'Clear',
    this.accentWhileFilled = false,
  });

  /// Keeps the accent outline for as long as the field holds text, focused
  /// or not: the library home's box, whose text narrows the list under it
  /// (Library › Search: Music › Artists).
  final bool accentWhileFilled;

  /// Optional; the field keeps its own when none is given.
  final TextEditingController? controller;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final String clearTooltip;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  TextEditingController? _own;
  final _focus = FocusNode();

  TextEditingController get controller =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _own?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final onChanged = widget.onChanged;
    // A tap anywhere in the 52 dp box focuses the field; the field itself
    // is one line, centered by layout. (An expanding multi-line field
    // centered through textAlignVertical sat its text at the top on
    // Android once the keyboard's suggestion strip was up.)
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // The field inside is what a screen reader meets; this only widens
      // where a finger may land.
      excludeFromSemantics: true,
      onTap: () => _focus.requestFocus(),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) => Container(
          height: 52,
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            // One outline: the accent while typing, the field outline at
            // rest.
            border: Border.all(
              color:
                  _focus.hasFocus ||
                      (widget.accentWhileFilled && controller.text.isNotEmpty)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          child: child,
        ),
        child: Row(
          children: [
            StrokeIcon(AppIcons.search, color: colors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Center(
                // The one-line field is 24 dp tall: its touch area and its
                // screen reader rect are the 48 dp the box has room for.
                child: TouchTarget(
                  child: TextField(
                    maxLines: 1,
                    controller: controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    onChanged: onChanged,
                    onSubmitted: widget.onSubmitted,
                    textInputAction: widget.textInputAction,
                    textCapitalization: widget.textCapitalization,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox(width: 10)
                  : IconButton(
                      onPressed: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                      tooltip: widget.clearTooltip,
                      icon: const StrokeIcon(AppIcons.close, size: 18),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
