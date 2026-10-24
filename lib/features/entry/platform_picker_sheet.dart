import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/lookup/lookup_source.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../data/models/platform_names.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/lookup_notice.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/search_field.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/touch_target.dart';
import '../settings/display_preferences.dart';

/// What the platform picker resolved with: the platform, or null for "Any
/// platform". The sheet itself resolves with null when dismissed.
typedef PlatformPick = ({GamePlatform? platform});

/// Add / edit entry › Platform picker, over Game search on a platform.
Future<PlatformPick?> showPlatformPicker(
  BuildContext context, {
  GamePlatform? selected,
}) => showAppSheet<PlatformPick>(
  context,
  builder: (_) => PlatformPickerSheet(selected: selected),
);

/// The platform [name] stands for among [platforms]: the one shown by that
/// name, else one that goes by it ("SNES"), case aside. Null when none
/// does.
GamePlatform? platformNamed(List<GamePlatform> platforms, String name) {
  final wanted = normalizePlatform(name).toLowerCase();
  final raw = name.trim().toLowerCase();
  for (final p in platforms) {
    if (p.name.toLowerCase() == wanted) return p;
  }
  for (final p in platforms) {
    if (p.aka.any((a) => a.toLowerCase() == raw)) return p;
  }
  return null;
}

/// The picker's "Your platforms": the default platform from Settings first,
/// then the platforms of the library's games, the most used first (A to Z
/// among equals), each once and only those [platforms] lists.
List<GamePlatform> yourPlatforms(
  List<GamePlatform> platforms, {
  String? defaultPlatform,
  Iterable<Entry> entries = const [],
}) {
  final counts = <String, int>{};
  for (final e in entries) {
    if (e.type != MediaType.games) continue;
    for (final name in splitPlatforms(e.platform)) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final used = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0
          ? byCount
          : a.toLowerCase().compareTo(b.toLowerCase());
    });
  final seen = <int>{};
  return [
    for (final name in [?defaultPlatform, ...used])
      if (platformNamed(platforms, name) case final p?)
        if (seen.add(p.id)) p,
  ];
}

/// Whether [platform] is called [query] by any of its names, case aside
/// ("snes" finds Super Nintendo).
bool platformMatches(GamePlatform platform, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty ||
      [platform.name, ...platform.aka].any((n) => n.toLowerCase().contains(q));
}

/// A search field over three groups: "Any platform", Your platforms and
/// All platforms A to Z; while a search is typed, one group of the
/// platforms called that. Each row shows the platform's name with its
/// other names under it, and a check on the one picked.
class PlatformPickerSheet extends ConsumerStatefulWidget {
  const PlatformPickerSheet({super.key, this.selected});

  final GamePlatform? selected;

  @override
  ConsumerState<PlatformPickerSheet> createState() =>
      _PlatformPickerSheetState();
}

class _PlatformPickerSheetState extends ConsumerState<PlatformPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _pick(GamePlatform? platform) =>
      Navigator.pop<PlatformPick>(context, (platform: platform));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final query = _query.text.trim();
    final loaded = ref.watch(gamePlatformsProvider);
    final selectedId = widget.selected?.id;

    Widget row(GamePlatform? p) => _PlatformRow(
      name: p?.name ?? 'Any platform',
      aka: p?.aka ?? const [],
      selected: p?.id == selectedId,
      onTap: () => _pick(p),
    );

    final List<Widget> body;
    switch (loaded) {
      case AsyncData(:final value):
        if (query.isNotEmpty) {
          final hits = value.where((p) => platformMatches(p, query)).toList();
          body = hits.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'No platform called that.',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.muted,
                      ),
                    ),
                  ),
                ]
              : [_heading('Matches'), for (final p in hits) row(p)];
        } else {
          final yours = yourPlatforms(
            value,
            defaultPlatform: ref.watch(
              displayPreferencesProvider.select((p) => p.defaultPlatform),
            ),
            entries: ref.watch(libraryProvider).value?.entries ?? const [],
          );
          body = [
            _heading('Any'),
            row(null),
            if (yours.isNotEmpty) ...[
              _heading('Your platforms'),
              for (final p in yours) row(p),
            ],
            _heading('All platforms'),
            for (final p in value) row(p),
          ];
        }
      case AsyncError():
        body = [
          LookupNotice(
            'Could not load the platforms. Check your connection and try '
            'again.',
            onRetry: () => ref.invalidate(gamePlatformsProvider),
          ),
        ];
      default:
        body = [const LookupNotice('Loading platforms…', spinner: true)];
    }

    return SheetFrame(
      scrollable: true,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Platform', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SearchField(
            controller: _query,
            hintText: 'Search, e.g. SNES or Genesis',
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }

  Widget _heading(String label) =>
      SectionHeading(label, padding: const EdgeInsets.fromLTRB(0, 14, 0, 4));
}

/// One platform: its name, its other names under it, and a check while
/// it is the one picked.
class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.name,
    required this.aka,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final List<String> aka;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    if (aka.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        aka.join(' · '),
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontSize: 13,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 12),
                StrokeIcon(
                  AppIcons.check,
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
}

/// "Platform · Any ▾" under the type chips on Add / edit entry › New entry:
/// pick a match while Games is picked (Game search on a platform): opens
/// the platform picker, filled while a platform is picked, with a cross
/// beside it that goes back to any platform.
class PlatformChip extends StatelessWidget {
  const PlatformChip({
    super.key,
    required this.platform,
    required this.onTap,
    required this.onClear,
  });

  final GamePlatform? platform;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final picked = platform != null;
    final value = platform?.name ?? 'Any';
    final label = theme.textTheme.labelMedium!.copyWith(
      color: scheme.onSurface,
    );
    return Row(
      children: [
        Flexible(
          child: TouchTarget(
            child: Semantics(
              button: true,
              label: 'Platform: $value',
              excludeSemantics: true,
              child: Material(
                color: picked ? colors.selectedFill : Colors.transparent,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: picked ? Colors.transparent : scheme.outline,
                  ),
                ),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const StadiumBorder(),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Platform',
                          style: label.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colors.muted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            value,
                            style: label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        StrokeIcon(
                          AppIcons.chevronDown,
                          size: 16,
                          color: scheme.onSurface,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (picked) ...[
          const SizedBox(width: 6),
          IconButton(
            onPressed: onClear,
            tooltip: 'Any platform',
            color: colors.muted,
            icon: const StrokeIcon(AppIcons.closeBold, size: 16),
          ),
        ],
      ],
    );
  }
}
