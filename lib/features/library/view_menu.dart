import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../settings/entry_view.dart';

StrokeIconData viewIcon(EntryView view) => switch (view) {
  EntryView.text => AppIcons.textView,
  EntryView.listWithPhotos => AppIcons.listView,
  EntryView.grid => AppIcons.gridView,
};

/// The 44 px button showing the current view; opens the view menu (Library ›
/// View menu open) anchored under it.
class ViewMenuButton extends StatelessWidget {
  const ViewMenuButton({
    super.key,
    required this.current,
    required this.onChanged,
    this.photos = false,
  });

  final EntryView current;
  final ValueChanged<EntryView> onChanged;

  /// Artists and songs say "with photos"; everything else "with covers".
  final bool photos;

  Future<void> _open(BuildContext context) async {
    final theme = Theme.of(context);
    final button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx + button.size.width - 240,
      origin.dy + button.size.height + 4,
      overlay.size.width - origin.dx - button.size.width,
      0,
    );
    // The artboard dims the screen behind the menu. showMenu has no barrier
    // color, so a route that only draws the scrim goes under the menu.
    final colors = LibraryColors.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final scrim = PageRouteBuilder<void>(
      opaque: false,
      barrierColor: colors.scrim.withValues(alpha: 0.62),
      transitionDuration: AppMotion.menu.duration!,
      reverseTransitionDuration: AppMotion.menu.reverseDuration!,
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    navigator.push(scrim);
    final picked = await showMenu<EntryView>(
      context: context,
      useRootNavigator: true,
      position: position,
      popUpAnimationStyle: AppMotion.menu,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 240),
      items: [
        PopupMenuItem<EntryView>(
          enabled: false,
          height: 32,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Text('VIEW', style: theme.textTheme.labelSmall),
        ),
        for (final view in EntryView.values)
          PopupMenuItem<EntryView>(
            value: view,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                // The chosen view is highlighted as well as checked.
                color: view == current ? colors.selectedFill : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  StrokeIcon(
                    viewIcon(view),
                    size: 20,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      view.labelFor(photos: photos),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (view == current)
                    StrokeIcon(
                      AppIcons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                      semanticLabel: 'Selected',
                    ),
                ],
              ),
            ),
          ),
      ],
    );
    // Fade the scrim out with the menu.
    if (scrim.isCurrent) {
      navigator.pop();
    } else if (scrim.isActive) {
      navigator.removeRoute(scrim);
    }
    if (picked != null && picked != current) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _open(context),
      tooltip: 'Change view',
      color: Theme.of(context).colorScheme.onSurface,
      icon: StrokeIcon(viewIcon(current), size: 20),
    );
  }
}
