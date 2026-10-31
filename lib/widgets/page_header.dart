import 'package:flutter/material.dart';

import 'app_icons.dart';

/// Title row at the top of a screen: 34 px on top-level screens, 28 px with
/// a back arrow. [actions] sit at the trailing end, typically a settings
/// button. No tinted header bars.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.leading,
    this.actions = const [],
  });

  final String title;

  /// A muted line under the title ("5 in your library" on Library › Coming
  /// soon: in library).
  final String? subtitle;

  /// When set, a back arrow is shown and the title is one step smaller.
  final VoidCallback? onBack;

  /// Sits between the back arrow and the title, e.g. a type color dot.
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasBack = onBack != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: Row(
        children: [
          if (hasBack)
            Transform.translate(
              // A 48 dp target whose icon lines up with the 20 px margin.
              offset: const Offset(-14, 0),
              child: IconButton(
                onPressed: onBack,
                tooltip: 'Back',
                color: Theme.of(context).colorScheme.onSurface,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const StrokeIcon(AppIcons.back, size: 22),
              ),
            ),
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Library connection" at a large text size on a narrow
                // phone: shrink a little before cutting off.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title,
                    style: hasBack
                        ? textTheme.headlineMedium
                        : textTheme.headlineLarge,
                    maxLines: 1,
                  ),
                ),
                if (subtitle case final subtitle?) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall!.copyWith(fontSize: 14),
                    // Two lines at a large text size ("3 upcoming · 1 not
                    // in your library" at 1.3 on a 360 dp phone).
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// The 44 px gear button that opens Settings from top-level screens.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Settings',
      // The standard Material cog (Library › Home; Plans › Plans overview), not
      // one of the stroke glyphs.
      icon: const Icon(Icons.settings_outlined, size: 22),
    );
  }
}
