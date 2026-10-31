import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/follow_kind.dart';
import '../../data/operations/settings_operations.dart';
import '../../data/upcoming/check_control.dart';
import '../../data/upcoming/upcoming_scheduler.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/switch_row.dart';
import '../upcoming/upcoming_checks.dart';
import 'display_preferences.dart';
import 'follow_list_screen.dart';

/// Opens Settings › Upcoming releases above Settings.
Future<void> openUpcomingReleasesScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(builder: (_) => const UpcomingReleasesScreen()),
  );
}

/// Settings › Upcoming releases (DESIGN.md section 4 and 10c): the master
/// switch, then Only on Wi-Fi, Last checked with Check now (Stop while a
/// check runs), the seven kinds followed with their counts, each opening its
/// list, and the note on the schedule.
class UpcomingReleasesScreen extends ConsumerWidget {
  const UpcomingReleasesScreen({super.key});

  static const onHelp =
      'Once a day, the first time you open Libri. New seasons, parts, books '
      'and albums show up under Coming soon › Everything.';
  static const offHelp =
      'Nothing is followed and nothing is fetched. Coming soon only shows '
      'what you add yourself.';
  static const wifiHelp = 'Skips the check on mobile data.';
  static const followHelp =
      'Taken from your library: creators, tags and series. Add a book and its '
      'author is followed. Tap a kind to leave some out.';
  static const scheduleNote =
      'What you want and what is dated is checked every day; the rest once a '
      'week, a part of it each day. Creators who have died or disbanded are '
      'skipped, but their series are still checked. New seasons of shows you '
      'dropped are not.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings =
        ref.watch(appSettingsProvider).value ?? AppSettings.defaults;
    final prefs = ref.watch(displayPreferencesProvider);
    final follows = ref.watch(followsProvider);
    final progress =
        ref.watch(upcomingProgressProvider).value ?? CheckProgress.idle;
    final schedule =
        ref.watch(upcomingScheduleProvider).value ?? UpcomingSchedule.none;
    final checks = ref.read(upcomingChecksProvider);
    void set(SettingsOperation operation) =>
        unawaited(ref.read(libraryRepositoryProvider).applySettings(operation));
    final helpStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 13,
      height: 1.4,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Upcoming releases',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  SwitchRow(
                    label: 'Check for new releases',
                    value: settings.upcomingEnabled,
                    onChanged: (on) => set(SetUpcomingEnabled(on)),
                    style: SwitchRowStyle.line,
                    help: settings.upcomingEnabled ? onHelp : offHelp,
                  ),
                  if (settings.upcomingEnabled) ...[
                    SwitchRow(
                      label: 'Only on Wi-Fi',
                      value: prefs.upcomingWifiOnly,
                      onChanged: ref
                          .read(displayPreferencesProvider.notifier)
                          .setUpcomingWifiOnly,
                      style: SwitchRowStyle.line,
                      help: wifiHelp,
                    ),
                    _LastCheckedRow(
                      progress: progress,
                      schedule: schedule,
                      onCheckNow: () => unawaited(checks.run(everything: true)),
                      onStop: checks.stop,
                    ),
                    const SectionHeading(
                      'Follow',
                      padding: EdgeInsets.fromLTRB(0, 18, 0, 2),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
                      child: Text(followHelp, style: helpStyle),
                    ),
                    for (final kind in FollowKind.values)
                      SettingRow(
                        key: ValueKey('kind-${kind.key}'),
                        label: kind.label,
                        detail: kind.what,
                        value: follows.countLabel(kind),
                        // In the text color, as the canvas draws the counts;
                        // muted would read as "nothing followed".
                        emphasizedValue: true,
                        onTap: () => openFollowListScreen(context, kind),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                      child: Text(scheduleNote, style: helpStyle),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Last checked · Today 07:12 · 3 new" with Check now; "Checking 184 of
/// 423…" with Stop while a run is on.
class _LastCheckedRow extends StatelessWidget {
  const _LastCheckedRow({
    required this.progress,
    required this.schedule,
    required this.onCheckNow,
    required this.onStop,
  });

  final CheckProgress progress;
  final UpcomingSchedule schedule;
  final VoidCallback onCheckNow;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final value = progress.running
        ? 'Checking ${progress.done} of ${progress.total}…'
        : lastCheckedLabel(schedule, now: DateTime.now());
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last checked',
                  style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
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
            label: progress.running ? 'Stop' : 'Check now',
            kind: AppButtonKind.outline,
            compact: true,
            onPressed: progress.running ? onStop : onCheckNow,
          ),
        ],
      ),
    );
  }
}

/// "Today 07:12 · 3 new", "Yesterday 22:40", "Oct 12 · 1 new", or "Never".
String lastCheckedLabel(UpcomingSchedule schedule, {required DateTime now}) {
  final checked = schedule.lastChecked?.toLocal();
  if (checked == null) return 'Never';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(checked.year, checked.month, checked.day);
  final time =
      '${checked.hour.toString().padLeft(2, '0')}:'
      '${checked.minute.toString().padLeft(2, '0')}';
  final when = day == today
      ? 'Today $time'
      : day == today.subtract(const Duration(days: 1))
      ? 'Yesterday $time'
      : day.year == today.year
      ? '${monthAbbreviations[day.month - 1]} ${day.day}'
      : '${monthAbbreviations[day.month - 1]} ${day.day}, ${day.year}';
  final found = schedule.newCount;
  return found == 0 ? when : '$when · $found new';
}
