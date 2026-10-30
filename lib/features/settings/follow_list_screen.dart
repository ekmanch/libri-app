import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/follow_kind.dart';
import '../../data/operations/settings_operations.dart';
import '../../data/upcoming/follows.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/check_box_mark.dart';
import '../../widgets/page_header.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/search_field.dart';
import '../../widgets/section_heading.dart';

/// Opens one kind's follow list (Settings › Follow: authors; Follow: actors)
/// above Settings › Upcoming releases.
Future<void> openFollowListScreen(BuildContext context, FollowKind kind) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => FollowListScreen(kind: kind)));
}

/// The follows the library gives, with the settings and the creator
/// records applied, for the screens (Settings › Upcoming releases and the
/// follow lists) and the follow mark in Library › Entry details.
final followsProvider = Provider.autoDispose<Follows>((ref) {
  final library = ref.watch(libraryProvider).value;
  final settings = ref.watch(appSettingsProvider).value ?? AppSettings.defaults;
  final statuses = ref.watch(creatorStatusesProvider).value ?? const {};
  if (library == null) return const Follows({});
  return deriveFollows(library, settings, statuses: statuses);
});

/// Settings › Follow: authors (and the same list for every kind): the kind
/// as the title with "10 of 25 followed" under it, Follow all or Unfollow
/// all, a search, then the follows under "Followed for new books" and the
/// creators who are no longer active under "No longer active", unticked
/// unless the owner ticked them. A tap toggles the follow at once
/// (`SetFollow`, saved to `settings.json`).
class FollowListScreen extends ConsumerStatefulWidget {
  const FollowListScreen({super.key, required this.kind});

  final FollowKind kind;

  static const inactiveHelp = 'Skipped on their own. Tick one to check anyway.';

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  String _query = '';

  FollowKind get kind => widget.kind;

  void _set(SettingsOperation operation) =>
      unawaited(ref.read(libraryRepositoryProvider).applySettings(operation));

  void _toggle(Follow follow) => _set(
    SetFollow(
      kind,
      follow.id,
      name: follow.name,
      on: !follow.followed,
      defaultOn: follow.defaultOn,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final follows = ref.watch(followsProvider);
    final all = follows.of(kind);
    final q = _query.trim().toLowerCase();
    bool matches(Follow f) => q.isEmpty || f.name.toLowerCase().contains(q);
    final active = [
      for (final f in all)
        if (f.isActive && matches(f)) f,
    ];
    final gone = [
      for (final f in all)
        if (!f.isActive && matches(f)) f,
    ];
    final mostFollowed = follows.mostFollowed(kind);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: kind.label,
              subtitle: follows.followedLabel(kind),
              onBack: () => Navigator.pop(context),
              actions: [
                if (all.any((f) => f.isActive))
                  AppButton(
                    label: mostFollowed ? 'Unfollow all' : 'Follow all',
                    kind: AppButtonKind.outline,
                    compact: true,
                    onPressed: () => _set(
                      SetFollows(
                        kind,
                        follows.activeDefaults(kind),
                        on: !mostFollowed,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SearchField(
                hintText: kind.searchHint,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: all.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        _emptyText,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontSize: 15,
                          color: colors.muted,
                        ),
                      ),
                    )
                  : active.isEmpty && gone.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text(
                        'No ${kind.label.toLowerCase()} match '
                        '"${_query.trim()}".',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontSize: 15,
                          color: colors.muted,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        if (active.isNotEmpty) ...[
                          SectionHeading(
                            'Followed for new ${kind.noun}',
                            padding: const EdgeInsets.fromLTRB(0, 14, 0, 2),
                          ),
                          for (final f in active)
                            FollowRow(
                              follow: f,
                              key: ValueKey('follow-${f.id}'),
                              onTap: () => _toggle(f),
                            ),
                        ],
                        if (gone.isNotEmpty) ...[
                          const SectionHeading(
                            'No longer active',
                            padding: EdgeInsets.fromLTRB(0, 18, 0, 2),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                            child: Text(
                              FollowListScreen.inactiveHelp,
                              style: theme.textTheme.bodySmall!.copyWith(
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                          for (final f in gone)
                            FollowRow(
                              follow: f,
                              key: ValueKey('follow-${f.id}'),
                              onTap: () => _toggle(f),
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

  String get _emptyText => switch (kind) {
    FollowKind.shows =>
      'No shows or anime with seasons from a lookup yet. They are followed '
          'as you add them.',
    FollowKind.series =>
      'No series with a part done or in progress yet. A series is followed '
          'once you have read, watched or played part of it.',
    FollowKind.artists =>
      'No artists yet. Add an album or a song and its artist is followed.',
    _ =>
      'No ${kind.label.toLowerCase()} tagged yet. Tag an entry with one and '
          'they are followed.',
  };
}

/// One follow: the name over what the library has of theirs ("3 books"), or
/// for the No longer active group "Died 2021 · Series still checked", and a
/// square check on the right; muted when no longer active.
class FollowRow extends StatelessWidget {
  const FollowRow({super.key, required this.follow, required this.onTap});

  final Follow follow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final muted = !follow.isActive;
    return Semantics(
      button: true,
      checked: follow.followed,
      label: follow.name,
      value: follow.secondLine,
      excludeSemantics: true,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              CheckBoxMark(checked: follow.followed),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      follow.name,
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: muted ? colors.muted : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      follow.secondLine,
                      style: theme.textTheme.bodySmall!.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
