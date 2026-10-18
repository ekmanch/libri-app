import 'package:flutter/material.dart';

/// The inside of a bottom sheet: grabber, optional title row, content.
/// Side padding is 20 px like the screens. The sheet itself comes from
/// [showAppSheet], which applies the theme's shape and scrim.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    this.title,
    this.action,
    this.header,
    required this.child,
    this.footer,
    this.scrollable = false,
  });

  final String? title;

  /// Trailing widget on the title row, e.g. a "Reset" text button.
  final Widget? action;

  /// A custom header instead of [title] and [action], pinned above the
  /// content like they are: the tag picker's title row and search field.
  final Widget? header;
  final Widget child;

  /// Pinned under the content, e.g. the "Show N entries" button.
  final Widget? footer;

  /// True when the content may be taller than the screen.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grabber = Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    final header = this.header != null
        ? Padding(padding: const EdgeInsets.only(top: 8), child: this.header)
        : title == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title!, style: theme.textTheme.headlineSmall),
                ),
                ?action,
              ],
            ),
          );
    // The keyboard (a sheet with a text field: the plan note, the tag
    // picker's search, the typed year in A26) pushes the sheet up and
    // shrinks a scrollable body, so the field stays in view.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    const sides = EdgeInsets.symmetric(horizontal: 20);
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 10, 0, 20 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          grabber,
          if (header != null) Padding(padding: sides, child: header),
          const SizedBox(height: 12),
          // The scroll view spans the sheet's full width with the side
          // margin inside it, so it clips at the sheet's edges, not at the
          // margin: a chip's outline or a row that bleeds (the decade row
          // in A2) is not cut off.
          if (scrollable)
            Flexible(
              child: SingleChildScrollView(padding: sides, child: child),
            )
          else
            Padding(padding: sides, child: child),
          if (footer != null) ...[
            const SizedBox(height: 12),
            Padding(padding: sides, child: footer),
          ],
        ],
      ),
    );
  }
}

/// Opens a modal bottom sheet styled by the theme, on the root navigator so
/// it covers the floating navigation. With [inheritTheme] the sheet keeps
/// the opener's theme, e.g. the seasonal accent inside a plan (S7, D2).
///
/// A sheet never takes the whole screen: at most [maxHeightFactor] of it,
/// so the screen it came from stays in view above it (A22, D14).
///
/// A text field behind the sheet gives up its focus first. Otherwise the
/// field takes it back when the sheet closes and the keyboard pops up
/// again, after every rating, tag or date picked on the entry form.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool inheritTheme = false,
  double maxHeightFactor = 0.88,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    builder: (context) {
      final child = SafeArea(top: false, child: builder(context));
      return inheritTheme ? Theme(data: theme, child: child) : child;
    },
  );
}
