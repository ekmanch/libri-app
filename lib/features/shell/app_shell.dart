import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entry/dropped_season_dialog.dart';
import '../entry/entry_details_sheet.dart';
import '../entry/new_entry_screen.dart';
import '../plans/plan_form_screen.dart';
import '../library/home_return_provider.dart';
import '../library/home_type_provider.dart';
import '../library/library_home_screen.dart';
import '../library/recent_changes.dart';
import '../settings/display_preferences.dart';
import '../../theme/app_theme.dart';
import '../../data/models/plan.dart';
import '../plans/plan_screen.dart';
import '../plans/plan_progress.dart';
import '../plans/plans_screen.dart';
import '../first_run/first_run_flow.dart';
import '../sync/sync_scheduler.dart';
import '../sync/sync_state.dart';
import '../sync/token_expiry.dart';
import '../sync/token_expiry_dialog.dart';
import '../../data/images/artwork_providers.dart';
import '../../data/library_providers.dart';
import '../../data/operations/operations.dart';
import '../../data/lookup/lookup_providers.dart';
import 'fab_action.dart';
import 'floating_nav_bar.dart';

/// The app frame: one navigator per tab, the floating pill navigation and
/// the round "+" button laid over the content.
///
/// Screens inside a tab keep the pill visible (Library › Movies, text view), so
/// lists add [contentBottomPadding] at the end to scroll clear of it.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.libraryHome,
    this.plansHome,
    this.onAddEntry,
    this.onAddPlan,
  });

  /// Override the tab roots, mainly for tests.
  final Widget? libraryHome;
  final Widget? plansHome;

  /// Called with the Library tab's navigator context when "+" is pressed. By
  /// default "+" starts the new-entry flow (Add / edit entry › New entry: pick
  /// a match).
  final void Function(BuildContext context)? onAddEntry;
  final void Function(BuildContext context)? onAddPlan;

  /// Navigation height (60: 48 dp items in a 6 dp padded pill) plus its
  /// 20 px margin and 20 px of air.
  static const contentBottomPadding = 100.0;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  ShellTab _tab = ShellTab.library;
  final _keys = {
    ShellTab.library: GlobalKey<NavigatorState>(),
    ShellTab.plans: GlobalKey<NavigatorState>(),
  };

  late final SyncScheduler _scheduler;
  AppLifecycleListener? _lifecycle;

  /// Whether the Library › Token expires soon dialog is being shown, so a
  /// resume meanwhile adds no second.
  bool _warning = false;

  /// Whether the move to seasons is being applied, so it is queued once.
  bool _movingShows = false;

  NavigatorState? get _current => _keys[_tab]!.currentState;

  @override
  void initState() {
    super.initState();
    _scheduler = SyncScheduler(sync: () => ref.read(librarySyncProvider))
      ..start();
    // Covers and photos of entries that are gone get cleaned up once per
    // session, a little after the library loads.
    ref.listenManual(artworkPrunerProvider, (_, _) {});
    // When entries change is recorded from the first change on, for the
    // home's In progress order (Library › Home).
    ref.listenManual(recentChangesProvider, (_, _) {});
    // A plan whose first date has come turns its Started switch on, so the
    // switch always shows the real state (Plans › Edit plan). Plans never stop
    // on their own.
    ref.listenManual(libraryProvider, (_, next) {
      final library = next.value;
      if (library == null) return;
      final repository = ref.read(libraryRepositoryProvider);
      for (final start in dueStarts(library)) {
        repository.apply(start);
      }
      // Shows from before seasons move their date and status into seasons,
      // once, as one change synced like any other.
      if (!_movingShows && library.entries.any(needsSeasonMove)) {
        _movingShows = true;
        repository
            .apply(const MoveShowsToSeasons())
            .whenComplete(() => _movingShows = false);
      }
    }, fireImmediately: true);
    // The token expiry warning (Library › Token expires soon) on the first open
    // of the day, in the last week of the token: when the app starts or comes
    // back to the foreground, and when GitHub first says when the token
    // expires.
    ref.listenManual(
      libraryConnectionProvider.select((c) => c.tokenExpires),
      (_, _) => unawaited(_warnAboutToken()),
      fireImmediately: true,
    );
    // New seasons of the shows being watched, once a day: when the
    // library first loads and when the app comes back to the foreground.
    ref.listenManual(libraryProvider.select((l) => l.hasValue), (_, loaded) {
      if (loaded) unawaited(_checkSeasons());
    }, fireImmediately: true);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(_warnAboutToken());
        unawaited(_checkSeasons());
      },
    );
  }

  /// Applies what the daily season check found, once a day, and asks
  /// about dropped seasons the user gave a status.
  Future<void> _checkSeasons() async {
    final library = ref.read(libraryProvider).value;
    final check = ref.read(seasonCheckProvider);
    if (library == null || check == null) return;
    final result = await check.run(library, DateTime.now());
    if (!mounted) return;
    final repository = ref.read(libraryRepositoryProvider);
    for (final operation in result.operations) {
      await repository.apply(operation);
    }
    // Seasons TMDB dropped that the user gave a status: ask, one at a time
    // (Show & seasons › Announced season dropped). One left unanswered is asked
    // again after the next check.
    for (final dropped in result.dropped) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final show = ref.read(libraryProvider).value?.entryById(dropped.entryId);
      if (show == null ||
          !(show.seasons?.any((s) => s.season == dropped.season) ?? false)) {
        continue;
      }
      final choice = await showDroppedSeasonDialog(
        context,
        show: show,
        season: dropped.season,
        status: dropped.status,
      );
      switch (choice) {
        case DroppedSeasonChoice.keep:
          await repository.apply(KeepSeason(show.id, dropped.season));
        case DroppedSeasonChoice.remove:
          await repository.apply(RemoveSeason(show.id, dropped.season));
        case null:
          break;
      }
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _scheduler.dispose();
    super.dispose();
  }

  /// Shows Library › Token expires soon when it is due ([tokenWarningDue]) and
  /// records the day, so it comes once a day. Replace token opens the token
  /// step with the repo kept; Later leaves it until the next day.
  Future<void> _warnAboutToken() async {
    if (_warning) return;
    _warning = true;
    try {
      // Not during a build (the first check runs from initState) and not
      // before the first frame: the dialog needs the navigator.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final connection = ref.read(libraryConnectionProvider);
      final now = DateTime.now();
      if (!connection.connected ||
          !tokenWarningDue(
            expires: connection.tokenExpires,
            warnedOn: connection.tokenWarnedOn,
            now: now,
          )) {
        return;
      }
      unawaited(
        ref.read(libraryConnectionProvider.notifier).markTokenWarned(now),
      );
      final choice = await showTokenExpiryDialog(
        context,
        repository: connection.repository,
        expires: connection.tokenExpires!,
        now: now,
      );
      if (choice == TokenExpiryChoice.replace && mounted) {
        await openReplaceTokenScreen(context);
      }
    } finally {
      _warning = false;
    }
  }

  /// The current tab's item returns to its overview one step at a time: a
  /// screen above it is popped (Plans to Plans › Plans overview, Library to the
  /// home); on the Library home, the next tap scrolls to the top and the one
  /// after returns to All (Library › Home, DESIGN.md section 3).
  void _select(ShellTab tab) {
    if (tab == _tab) {
      final navigator = _current;
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      } else if (tab == ShellTab.library) {
        ref.read(homeReturnProvider.notifier).goHome();
      }
      return;
    }
    setState(() => _tab = tab);
    _scheduler.onTabSwitch();
  }

  /// Android back: pop inside the tab, then return to Library, then leave.
  void _onPop(bool didPop, Object? result) {
    if (didPop) return;
    final navigator = _current;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    } else if (_tab != ShellTab.library) {
      setState(() => _tab = ShellTab.library);
    } else {
      SystemNavigator.pop();
    }
  }

  /// The active plan card on the home (Library › Home) opens the plan in the
  /// Plans tab, so the pill says where you are and back lands on the overview.
  void _openPlan(Plan plan) {
    setState(() => _tab = ShellTab.plans);
    final plans = _keys[ShellTab.plans]!.currentState!;
    plans.popUntil((route) => route.isFirst);
    openPlanScreen(plans.context, plan.id, tab: ShellTab.plans);
  }

  void _add() {
    final context = _current?.context ?? this.context;
    switch (_tab) {
      case ShellTab.library:
        if (widget.onAddEntry case final onAdd?) {
          onAdd(context);
        } else {
          openNewEntryScreen(context, type: ref.read(homeTypeProvider));
        }
      case ShellTab.plans:
        if (widget.onAddPlan case final onAdd?) {
          onAdd(context);
        } else {
          openNewPlanForm(context);
        }
    }
  }

  Widget _tabNavigator(ShellTab tab, Widget home) {
    return Navigator(
      key: _keys[tab],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => home, settings: settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: _tab.index,
              children: [
                _tabNavigator(
                  ShellTab.library,
                  widget.libraryHome ??
                      LibraryHomeScreen(
                        onOpenEntry: (entry) =>
                            showEntryDetailsSheet(context, entry.id),
                        onOpenPlan: _openPlan,
                        onAddEntry: ({type, title}) => openNewEntryScreen(
                          context,
                          type: type,
                          title: title,
                        ),
                      ),
                ),
                _tabNavigator(
                  ShellTab.plans,
                  widget.plansHome ?? const PlansScreen(),
                ),
              ],
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20 + MediaQuery.paddingOf(context).bottom,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FloatingNavBar(selected: _tab, onSelect: _select),
                  Builder(
                    builder: (context) {
                      // A screen inside the tab may claim the button (Plans ›
                      // Plan checklist; All Halloween: add, edit, remove).
                      final fab = ref.watch(fabActionProvider);
                      final claimed = fab != null && fab.tab == _tab;
                      final button = AddButton(
                        label: claimed
                            ? fab.label
                            : _tab == ShellTab.library
                            ? newEntryLabel(ref.watch(homeTypeProvider))
                            : 'New plan',
                        onPressed: claimed ? fab.onPressed : _add,
                      );
                      final seasonal = claimed ? fab.accent : null;
                      if (seasonal == null) return button;
                      // Inside a themed plan the button wears its accent.
                      final theme = Theme.of(context);
                      return Theme(
                        data: buildTheme(
                          brightness: theme.brightness,
                          accent: ref.watch(displayPreferencesProvider).accent,
                          seasonal: seasonal,
                        ),
                        child: button,
                      );
                    },
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
