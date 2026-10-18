import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/chips.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/segmented_control.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/switch_row.dart';
import '../sync/sync_state.dart';
import 'about_screen.dart';
import 'connection_screen.dart';
import 'display_preferences.dart';

/// Opens Settings above everything, so the floating navigation is covered.
Future<void> openSettingsScreen(BuildContext context) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => const SettingsScreen()));
}

/// Settings (S6): a preview of the accent, theme, accent color in the
/// Vivid and Pastel groups, the defaults for new plans, the default game
/// platform, the library connection and the About row that opens D19.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _firstHeading = EdgeInsets.fromLTRB(0, 8, 0, 8);
  static const _heading = EdgeInsets.fromLTRB(0, 16, 0, 8);
  static const _lineHeading = EdgeInsets.fromLTRB(0, 16, 0, 2);
  static const _laterLineHeading = EdgeInsets.fromLTRB(0, 12, 0, 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final prefs = ref.watch(displayPreferencesProvider);
    final notifier = ref.read(displayPreferencesProvider.notifier);
    final groupStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: 'Settings', onBack: () => Navigator.pop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  const SectionHeading('Preview', padding: _firstHeading),
                  const _PreviewCard(),
                  const SectionHeading('Theme', padding: _heading),
                  SegmentedControl<ThemeMode>(
                    segments: const [
                      SegmentOption(ThemeMode.system, 'System'),
                      SegmentOption(ThemeMode.dark, 'Dark'),
                      SegmentOption(ThemeMode.light, 'Light'),
                    ],
                    selected: prefs.themeMode,
                    onChanged: notifier.setThemeMode,
                    equalWidths: true,
                  ),
                  const SectionHeading('Accent color', padding: _heading),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('Vivid', style: groupStyle),
                  ),
                  _SwatchGrid(
                    options: Accents.vivid,
                    selected: prefs.accent,
                    onPick: notifier.setAccent,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
                    child: Text('Pastel', style: groupStyle),
                  ),
                  _SwatchGrid(
                    options: Accents.pastel,
                    selected: prefs.accent,
                    onPick: notifier.setAccent,
                  ),
                  const SectionHeading('Plans', padding: _lineHeading),
                  SwitchRow(
                    label: 'Timeline',
                    value: prefs.timelineDefault,
                    onChanged: notifier.setTimelineDefault,
                    style: SwitchRowStyle.line,
                    help: prefs.timelineDefault
                        ? 'New plans place entries on a timeline. '
                              'You can change it per plan.'
                        : 'New plans are a plain checklist without dates. '
                              'You can change it per plan.',
                  ),
                  SwitchRow(
                    label: 'Seasonal touches',
                    value: prefs.seasonalThemeDefault,
                    onChanged: notifier.setSeasonalThemeDefault,
                    style: SwitchRowStyle.line,
                    help: prefs.seasonalThemeDefault
                        ? 'New Halloween and Christmas plans get themed '
                              'artwork and colors. You can change it per plan.'
                        : 'New plans all look the same. '
                              'You can change it per plan.',
                  ),
                  const SectionHeading('Games', padding: _laterLineHeading),
                  Container(
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: colors.divider)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default platform',
                          style: theme.textTheme.bodyLarge!.copyWith(
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Selected automatically when you add a game that '
                          'came out on it.',
                          style: theme.textTheme.bodySmall!.copyWith(
                            fontSize: 13,
                            fontStyle: FontStyle.normal,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final platform
                                in DisplayPreferences.platformChoices)
                              PillChip(
                                label: platform,
                                height: 40,
                                style: PillChipStyle.accent,
                                selected: prefs.defaultPlatform == platform,
                                onTap: () =>
                                    notifier.setDefaultPlatform(platform),
                              ),
                            PillChip(
                              label: 'None',
                              height: 40,
                              style: PillChipStyle.accent,
                              selected: prefs.defaultPlatform == null,
                              onTap: () => notifier.setDefaultPlatform(null),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SectionHeading('Data', padding: _laterLineHeading),
                  SettingRow(
                    label: 'Library source',
                    value:
                        ref.watch(
                          libraryConnectionProvider.select(
                            (c) => c.keptLocally,
                          ),
                        )
                        ? 'This phone only'
                        : 'GitHub, private repo',
                    onTap: () => openConnectionScreen(context),
                  ),
                  const SectionHeading('About', padding: _laterLineHeading),
                  SettingRow(
                    label: appName,
                    value: switch (ref.watch(appVersionProvider)) {
                      AsyncData(:final value) => 'Version $value',
                      AsyncError() => 'Version unknown',
                      _ => 'Version …',
                    },
                    onTap: () => openAboutScreen(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sample row, progress bar and button, so an accent can be judged
/// before leaving the screen.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    return Semantics(
      label: 'Preview of the accent color',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.divider),
          boxShadow: colors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: StrokeIcon(
                      AppIcons.check,
                      size: 14,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('The Mummy', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 1),
                      Text(
                        'All-time favorite chill movie',
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.33,
                      minHeight: 8,
                      backgroundColor: colors.divider,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'Add',
                    style: theme.textTheme.labelMedium!.copyWith(
                      fontSize: 13,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Five swatches per row: a colored disc over the accent's name, the
/// chosen one ringed in its own ink.
class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  final List<AccentOption> options;
  final AccentOption selected;
  final ValueChanged<AccentOption> onPick;

  static const columns = 5;
  static const gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rows = <List<AccentOption>>[];
    for (var i = 0; i < options.length; i += columns) {
      rows.add(options.sublist(i, (i + columns).clamp(0, options.length)));
    }
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: gap),
          Row(
            children: [
              for (final (i, option) in row.indexed) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: _Swatch(
                    option: option,
                    selected: option == selected,
                    ring: isDark ? option.fill : option.ink,
                    edge: isDark
                        ? Colors.transparent
                        : theme.colorScheme.outline,
                    onTap: () => onPick(option),
                  ),
                ),
              ],
              // Keep a short last row's swatches the same width.
              for (var i = row.length; i < columns; i++) ...[
                const SizedBox(width: gap),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.option,
    required this.selected,
    required this.ring,
    required this.edge,
    required this.onTap,
  });

  final AccentOption option;
  final bool selected;
  final Color ring;
  final Color edge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? ring : Colors.transparent, width: 2),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: option.name,
      excludeSemantics: true,
      child: Material(
        color: selected ? theme.colorScheme.surface : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: option.fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: edge),
                  ),
                ),
                const SizedBox(height: 6),
                // A long name ("Rosewater") shrinks to fit the column on a
                // narrow phone at a large text size; the disc stays legible.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      option.name,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.normal,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
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
