import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/entry_kind.dart';
import '../../data/models/plan.dart';
import '../../data/models/plan_item.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/fitted_title.dart';
import '../../widgets/touch_target.dart';
import '../../widgets/segmented_control.dart';
import '../entry/delete_entry_dialog.dart';
import '../entry/entry_form_screen.dart';
import '../entry/new_entry_screen.dart';
import '../settings/display_preferences.dart';
import '../shell/app_shell.dart';
import '../shell/fab_action.dart';
import '../shell/floating_nav_bar.dart';
import 'plan_builders.dart';
import 'plan_dialogs.dart';
import 'plan_done.dart';
import 'plan_entry_sheet.dart';
import 'plan_form_screen.dart';
import 'plan_progress.dart';
import 'plan_season.dart';
import 'plan_timeline.dart';
import 'seasonal_art.dart';
import 'seasonal_art_data.dart';

/// Opens a plan inside the current tab, so the floating navigation stays.
Future<void> openPlanScreen(
  BuildContext context,
  String planId, {
  required ShellTab tab,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlanScreen(planId: planId, tab: tab),
    ),
  );
}

enum PlanTab { thisPlan, pool }

/// One plan: the checklist grouped by type (Plans › Plan checklist) or the
/// timeline (Plans › Plan with timing on), and with linked tags a second tab
/// with everything that has them (Plans › All Halloween: add, edit, remove).
/// The header has the year chip, the plan menu (Plans › Plan menu), progress
/// and the tabs. With the seasonal theme on, the strip, icon, marker and accent
/// of Plans › Halloween touches or Christmas touches apply, only inside
/// this screen.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, required this.planId, required this.tab});

  final String planId;

  /// The shell tab this screen lives in, for the "+" button.
  final ShellTab tab;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  late String _planId = widget.planId;
  PlanTab _tab = PlanTab.thisPlan;
  String? _expandedPoolEntry;
  late final FabActionNotifier _fab;
  final _menuKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fab = ref.read(fabActionProvider.notifier);
  }

  @override
  void dispose() {
    final fab = _fab;
    WidgetsBinding.instance.addPostFrameCallback((_) => fab.clear(this));
    super.dispose();
  }

  /// Tells the shell what "+" does here: open the pool from the checklist,
  /// make a new entry with the plan's tags from the pool.
  void _publishFab(Plan plan) {
    final FabAction? action;
    final accent = seasonOf(plan)?.accent;
    if (plan.tags.isEmpty) {
      action = null;
    } else if (_tab == PlanTab.thisPlan) {
      action = FabAction(
        owner: this,
        tab: widget.tab,
        label: 'Add from All ${plan.name}',
        accent: accent,
        onPressed: () => setState(() => _tab = PlanTab.pool),
      );
    } else {
      action = FabAction(
        owner: this,
        tab: widget.tab,
        label: 'New ${plan.name} entry',
        accent: accent,
        onPressed: () => openNewEntryScreen(context, tags: plan.tags),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(fabActionProvider);
      if (action == null) {
        _fab.clear(this);
      } else if (current?.owner != this ||
          current?.label != action.label ||
          current?.accent != action.accent) {
        _fab.set(action);
      }
    });
  }

  Future<void> _toggleDone(Plan plan, PlanItem item, Entry entry) =>
      togglePlanItemDoneWithUndo(
        context,
        ref,
        plan: plan,
        item: item,
        entry: entry,
      );

  Future<void> _openMenu(Plan plan) async {
    final action = await showPlanMenu(
      context,
      _menuKey.currentContext!,
      plan: plan,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case PlanMenuAction.edit:
        final outcome = await openEditPlanForm(context, plan);
        if (outcome == PlanFormOutcome.deleted && mounted) {
          Navigator.pop(context);
        }
      case PlanMenuAction.copy:
        await _copyToNewYear(plan);
      case PlanMenuAction.delete:
        final ok = await confirmDeletePlan(context, plan);
        if (!ok || !mounted) return;
        await ref.read(libraryRepositoryProvider).apply(DeletePlan(plan.id));
        if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _copyToNewYear(Plan plan) async {
    final id = await openNewPlanForm(context, copyFrom: plan);
    if (id != null && mounted) setState(() => _planId = id);
  }

  Future<void> _pickYear(
    Plan plan,
    Library library,
    BuildContext anchor,
  ) async {
    // The anchor sits inside the plan's theme, so a seasonal accent applies.
    final theme = Theme.of(anchor);
    final colors = LibraryColors.of(anchor);
    final button = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final years = planYears(library, plan);
    final picked = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + button.size.height + 4,
        overlay.size.width - origin.dx - 170,
        0,
      ),
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 170),
      popUpAnimationStyle: AppMotion.menu,
      items: [
        for (final other in years)
          PopupMenuItem<String>(
            value: other.id,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: other.id == plan.id ? colors.neutralFill : null,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                other.year?.toString() ?? 'No year',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        PopupMenuDivider(height: 1, color: colors.navBorder),
        PopupMenuItem<String>(
          value: '',
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'New year…',
            style: theme.textTheme.labelLarge!.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked.isEmpty) {
      await _copyToNewYear(plan);
    } else if (picked != plan.id) {
      setState(() => _planId = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryProvider);
    final library = libraryAsync.value;
    final plan = library?.planById(_planId);
    if (library == null || plan == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeaderBack(onBack: () => Navigator.pop(context)),
              if (library != null)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('This plan is gone.'),
                ),
            ],
          ),
        ),
      );
    }
    _publishFab(plan);
    final prefs = ref.watch(displayPreferencesProvider);
    final season = seasonOf(plan);
    final base = Theme.of(context);
    final theme = season == null
        ? base
        : buildTheme(
            brightness: base.brightness,
            accent: prefs.accent,
            seasonal: season.accent,
          );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (season != null)
                  Stack(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) => SeasonalArtView(
                          season.strip,
                          width: constraints.maxWidth,
                          height:
                              88 * constraints.maxWidth / season.strip.width,
                        ),
                      ),
                      if (season == PlanSeason.halloween)
                        const Positioned(
                          top: 0,
                          right: 0,
                          child: SeasonalArtView(
                            halloweenWeb,
                            width: 120,
                            height: 120,
                            opacity: 0.4,
                          ),
                        ),
                    ],
                  ),
                _Header(
                  plan: plan,
                  library: library,
                  season: season,
                  tab: _tab,
                  menuKey: _menuKey,
                  hasStrip: season != null,
                  onPickYear: (anchor) => _pickYear(plan, library, anchor),
                  onMenu: () => _openMenu(plan),
                  onTab: (tab) => setState(() => _tab = tab),
                ),
                Expanded(
                  child: switch (_tab) {
                    PlanTab.pool => _Pool(
                      plan: plan,
                      library: library,
                      expanded: _expandedPoolEntry,
                      onExpand: (id) => setState(
                        () => _expandedPoolEntry = _expandedPoolEntry == id
                            ? null
                            : id,
                      ),
                    ),
                    PlanTab.thisPlan when plan.timeline => _Timeline(
                      plan: plan,
                      library: library,
                      onToggle: (item, entry) => _toggleDone(plan, item, entry),
                    ),
                    PlanTab.thisPlan => _Checklist(
                      plan: plan,
                      library: library,
                      onToggle: (item, entry) => _toggleDone(plan, item, entry),
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Just a back arrow, for the empty fallback screen.
class PageHeaderBack extends StatelessWidget {
  const PageHeaderBack({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 20, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          onPressed: onBack,
          tooltip: 'Back',
          color: Theme.of(context).colorScheme.onSurface,
          icon: const StrokeIcon(AppIcons.back, size: 24),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.plan,
    required this.library,
    required this.season,
    required this.tab,
    required this.menuKey,
    required this.hasStrip,
    required this.onPickYear,
    required this.onMenu,
    required this.onTab,
  });

  final Plan plan;
  final Library library;
  final PlanSeason? season;
  final PlanTab tab;
  final GlobalKey menuKey;
  final bool hasStrip;
  final void Function(BuildContext anchor) onPickYear;
  final VoidCallback onMenu;
  final ValueChanged<PlanTab> onTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final total = plan.items.length;
    final done = doneCount(plan);
    final fraction = total == 0 ? 0.0 : done / total;
    final years = planYears(library, plan);
    final showYearChip = plan.year != null || years.length > 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, hasStrip ? 0 : 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // No back arrow, as on the artboards: the system back and
              // the navigation pill lead out of a plan.
              if (season != null) ...[
                // The title's line box has room for descenders below the
                // letters; lift the icon so it sits on the caps.
                Transform.translate(
                  offset: const Offset(0, -3),
                  child: SeasonalArtView(
                    season!.icon,
                    width: season == PlanSeason.christmas ? 36 : 34,
                    height: season == PlanSeason.christmas ? 36 : 34,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FittedTitle(
                  plan.name,
                  style: theme.textTheme.headlineMedium!,
                  sizes: const [32, 28, 24],
                ),
              ),
              Transform.translate(
                offset: const Offset(10, 0),
                child: IconButton(
                  key: menuKey,
                  onPressed: onMenu,
                  tooltip: 'Plan options',
                  icon: const StrokeIcon(AppIcons.more, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (showYearChip) ...[
                Builder(
                  builder: (anchor) => TouchTarget(
                    child: Semantics(
                      button: true,
                      label: 'Choose year',
                      excludeSemantics: true,
                      child: Material(
                        color: colors.tray,
                        shape: StadiumBorder(
                          side: BorderSide(color: colors.trayBorder),
                        ),
                        child: InkWell(
                          onTap: () => onPickYear(anchor),
                          customBorder: const StadiumBorder(),
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  plan.year?.toString() ?? 'No year',
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(width: 4),
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
                const SizedBox(width: 12),
              ],
              // The bar shows on every tab, so the header looks the same on
              // the checklist, the timeline and the "All <plan>" tab.
              ...[
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                      height: 8,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 8,
                            ),
                          ),
                          if (season != null)
                            Positioned(
                              left: constraints.maxWidth * fraction - 10,
                              top: -6,
                              child: SeasonalArtView(
                                season!.marker,
                                width: 20,
                                height: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(progressLabel(plan), style: theme.textTheme.labelMedium),
              ],
            ],
          ),
          if (plan.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            SegmentedControl<PlanTab>(
              segments: [
                for (final t in PlanTab.values)
                  SegmentOption(
                    t,
                    t == PlanTab.thisPlan ? 'This plan' : 'All ${plan.name}',
                  ),
              ],
              selected: tab,
              trackColor: colors.tray,
              equalWidths: true,
              onChanged: onTab,
            ),
          ],
        ],
      ),
    );
  }
}

/// The round check on a plan row (Plans › Plan checklist; Plan with timing on).
class PlanCheck extends StatelessWidget {
  const PlanCheck({
    super.key,
    required this.done,
    required this.title,
    required this.onTap,
  });

  final bool done;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = LibraryColors.of(context);
    return Semantics(
      container: true,
      button: true,
      checked: done,
      label: '${done ? 'Mark not done' : 'Mark done'}: $title',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? scheme.primaryContainer : Colors.transparent,
                border: Border.all(
                  color: done ? scheme.primaryContainer : colors.placeholder,
                  width: 2,
                ),
              ),
              child: done
                  ? StrokeIcon(
                      AppIcons.check,
                      size: 14,
                      color: scheme.onPrimaryContainer,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Items with their entries, in plan order, skipping entries that are gone.
List<(PlanItem, Entry)> _resolved(Plan plan, Library library) => [
  for (final item in plan.items)
    if (library.entryById(item.entry) case final entry?) (item, entry),
];

class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.plan,
    required this.library,
    required this.onToggle,
  });

  final Plan plan;
  final Library library;
  final void Function(PlanItem item, Entry entry) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final rows = _resolved(plan, library);
    if (rows.isEmpty) {
      return EmptyState(
        icon: AppIcons.plans,
        title: 'Nothing in this plan yet',
        body: plan.tags.isEmpty
            ? 'Add entries from their details in the library.'
            : 'Pick from All ${plan.name} with the + button.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        AppShell.contentBottomPadding,
      ),
      children: [
        for (final type in MediaType.values)
          if (rows.any((r) => r.$2.type == type)) ...[
            SectionHeading(
              type.label,
              color: colors.forType(type),
              padding: const EdgeInsets.fromLTRB(0, 9, 0, 2),
            ),
            for (final (item, entry) in rows)
              if (entry.type == type)
                _CheckRow(
                  item: item,
                  entry: entry,
                  onToggle: () => onToggle(item, entry),
                  onOpen: () => showPlanEntrySheet(
                    context,
                    planId: plan.id,
                    entryId: entry.id,
                  ),
                  theme: theme,
                ),
          ],
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.item,
    required this.entry,
    required this.onToggle,
    required this.onOpen,
    required this.theme,
  });

  final PlanItem item;
  final Entry entry;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          PlanCheck(done: item.done, title: entry.title, onTap: onToggle),
          const SizedBox(width: 8),
          Expanded(
            child: RowInkWell(
              onTap: onOpen,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: item.done ? colors.muted : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        planRowSubtitle(entry),
                        if (item.repeat) repeatLabel(entry.type),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.plan,
    required this.library,
    required this.onToggle,
  });

  final Plan plan;
  final Library library;
  final void Function(PlanItem item, Entry entry) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final groups = timelineGroups(
      plan,
      typeRank: (item) =>
          library.entryById(item.entry)?.type.index ?? MediaType.values.length,
    );
    if (plan.items.isEmpty) {
      return EmptyState(
        icon: AppIcons.plans,
        title: 'Nothing in this plan yet',
        body: plan.tags.isEmpty
            ? 'Add entries from their details in the library.'
            : 'Pick from All ${plan.name} with the + button.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        4,
        20,
        AppShell.contentBottomPadding,
      ),
      children: [
        for (final group in groups)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  // "Whenever" fits at normal size; at large text sizes the
                  // column grows only a little, so the cards keep room for
                  // their titles, and a label may wrap instead.
                  width:
                      76 *
                      MediaQuery.textScalerOf(context)
                          .scale(1)
                          .clamp(1.0, 1.15),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          style: theme.textTheme.labelMedium!.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: switch (group.state) {
                              TimelineState.current => scheme.primary,
                              TimelineState.undated => colors.muted,
                              _ => scheme.onSurface,
                            },
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.dates,
                          style: theme.textTheme.bodySmall!.copyWith(
                            fontSize: 12,
                            fontStyle: FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // The gap to the next group is inside the row, so the rail
                // runs through it as one line (Plans › Plan with timing on).
                _Rail(group: group),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (j, item) in group.items.indexed)
                          if (library.entryById(item.entry) case final entry?)
                            Padding(
                              padding: EdgeInsets.only(top: j == 0 ? 0 : 8),
                              child: _TimelineCard(
                                item: item,
                                entry: entry,
                                onToggle: () => onToggle(item, entry),
                                onOpen: () => showPlanEntrySheet(
                                  context,
                                  planId: plan.id,
                                  entryId: entry.id,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The 2 px line on the left of a timeline group: filled for the past,
/// filled up to today for the current group (with a dot for today), empty
/// for what is to come, none for undated items.
class _Rail extends StatelessWidget {
  const _Rail({required this.group});

  final TimelineGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = LibraryColors.of(context);
    final fraction = group.todayFraction;
    final painter = CustomPaint(
      key: fraction == null ? null : const Key('timeline-today'),
      painter: _RailPainter(
        line: switch (group.state) {
          TimelineState.past => scheme.primaryContainer,
          TimelineState.undated => Colors.transparent,
          _ => colors.neutralFill,
        },
        fill: scheme.primaryContainer,
        fraction: fraction,
      ),
    );
    return SizedBox(
      width: 2,
      child: fraction == null
          ? painter
          : Semantics(label: 'Today', child: painter),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.line,
    required this.fill,
    required this.fraction,
  });

  final Color line;
  final Color fill;
  final double? fraction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, 2, size.height), Paint()..color = line);
    final f = fraction;
    if (f == null) return;
    final y = size.height * f;
    canvas.drawRect(Rect.fromLTWH(0, 0, 2, y), Paint()..color = fill);
    // The today dot overhangs the 2 px column on both sides.
    canvas.drawCircle(Offset(1, y), 5, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.line != line || old.fill != fill || old.fraction != fraction;
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.item,
    required this.entry,
    required this.onToggle,
    required this.onOpen,
  });

  final PlanItem item;
  final Entry entry;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
        boxShadow: colors.cardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(2, 6, 12, 6),
      child: Row(
        children: [
          PlanCheck(done: item.done, title: entry.title, onTap: onToggle),
          const SizedBox(width: 2),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (context) {
                    final title = Text(
                      entry.title,
                      style: theme.textTheme.titleMedium!.copyWith(
                        fontSize: 15.5,
                        height: 1.25,
                        color: item.done ? colors.muted : null,
                      ),
                      // Two lines before cutting off, as on Plans › Plan with
                      // timing on.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );
                    final kind = Text(
                      entryKindLabel(entry).toUpperCase(),
                      style: theme.textTheme.labelSmall!.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.forType(entry.type),
                      ),
                    );
                    final subtitle = Text(
                      planRowSubtitle(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                    // A narrow card (large text on a small phone) gives the
                    // title the full width and puts the type label above
                    // it, so words are never split.
                    // The card sits in an IntrinsicHeight row, so its width
                    // comes from the screen: margins, the label column, the
                    // rail and the check ring.
                    final scaler = MediaQuery.textScalerOf(context);
                    final labelColumn = 76 * scaler.scale(1).clamp(1.0, 1.15);
                    final textWidth =
                        MediaQuery.sizeOf(context).width -
                        40 -
                        labelColumn -
                        26 -
                        14 -
                        50;
                    final narrow = textWidth < scaler.scale(170);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: narrow
                          ? [kind, title, const SizedBox(height: 2), subtitle]
                          : [
                              Row(
                                children: [
                                  Expanded(child: title),
                                  const SizedBox(width: 8),
                                  kind,
                                ],
                              ),
                              const SizedBox(height: 2),
                              subtitle,
                            ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything in the library with any of the plan's tags (Plans › All
/// Halloween: add, edit, remove): add to or remove from this plan, and a row of
/// actions behind "⋮".
class _Pool extends ConsumerWidget {
  const _Pool({
    required this.plan,
    required this.library,
    required this.expanded,
    required this.onExpand,
  });

  final Plan plan;
  final Library library;
  final String? expanded;
  final ValueChanged<String> onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    final repository = ref.read(libraryRepositoryProvider);
    final entries = library.entries
        .where((e) => e.tags.any(plan.tags.contains))
        .toList();
    final tagsLabel = plan.tags.length == 1
        ? 'Remove #${plan.tags.single}'
        : 'Remove tags';
    final inLabel = plan.year == null ? 'In plan' : 'In ${plan.year}';

    if (entries.isEmpty) {
      return EmptyState(
        icon: AppIcons.filters,
        title: 'Nothing tagged ${plan.tags.map((t) => '#$t').join(', ')} yet',
        body: 'New entries with the tag show up here.',
      );
    }

    Future<void> toggle(Entry entry, bool inPlan) async {
      await repository.apply(
        inPlan
            ? RemovePlanItem(plan.id, entry.id)
            : SetPlanItem(
                plan.id,
                PlanItem(
                  entry: entry.id,
                  repeat: entry.status == EntryStatus.done,
                ),
              ),
      );
    }

    Future<void> removeTags(Entry entry) async {
      await repository.apply(
        UpdateEntry(
          entry.copyWith(
            tags: entry.tags.where((t) => !plan.tags.contains(t)).toList(),
          ),
        ),
      );
    }

    Future<void> delete(Entry entry) async {
      final plans = library.plans
          .where((p) => p.itemFor(entry.id) != null)
          .toList();
      final ok = await confirmDeleteEntry(context, entry: entry, plans: plans);
      if (ok) await repository.apply(DeleteEntry(entry.id));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        0,
        20,
        AppShell.contentBottomPadding,
      ),
      children: [
        for (final type in MediaType.values)
          if (entries.any((e) => e.type == type)) ...[
            SectionHeading(
              type.label,
              color: colors.forType(type),
              padding: const EdgeInsets.fromLTRB(0, 9, 0, 2),
            ),
            for (final entry in entries)
              if (entry.type == type)
                Builder(
                  builder: (context) {
                    final inPlan = plan.itemFor(entry.id) != null;
                    final open = expanded == entry.id;
                    final meta = [
                      planRowSubtitle(entry),
                      if (entry.seasonalOnly) 'only in ${plan.name}',
                    ].where((s) => s.isNotEmpty).join(' · ');
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: colors.divider),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.title,
                                        style: theme.textTheme.titleMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (meta.isNotEmpty)
                                        Text(
                                          meta,
                                          style: theme.textTheme.bodySmall!
                                              .copyWith(
                                                fontSize: 13,
                                                fontStyle: FontStyle.normal,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Semantics(
                                container: true,
                                button: true,
                                label:
                                    '${inPlan ? 'Remove from plan' : 'Add to plan'}: ${entry.title}',
                                excludeSemantics: true,
                                child: Material(
                                  color: inPlan
                                      ? Colors.transparent
                                      : scheme.primaryContainer,
                                  shape: StadiumBorder(
                                    side: BorderSide(
                                      color: inPlan
                                          ? scheme.outline
                                          : scheme.primaryContainer,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => toggle(entry, inPlan),
                                    customBorder: const StadiumBorder(),
                                    child: Container(
                                      height: 36,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        inPlan ? inLabel : 'Add',
                                        style: theme.textTheme.labelMedium!
                                            .copyWith(
                                              fontSize: 13,
                                              color: inPlan
                                                  ? scheme.onSurface
                                                  : scheme.onPrimaryContainer,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => onExpand(entry.id),
                                tooltip: 'More actions: ${entry.title}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 48,
                                  height: 48,
                                ),
                                style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const StrokeIcon(AppIcons.more, size: 20),
                              ),
                            ],
                          ),
                          if (open)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _ActionChip(
                                    label: 'Edit entry',
                                    onTap: () =>
                                        openEditEntryForm(context, entry),
                                  ),
                                  _ActionChip(
                                    label: tagsLabel,
                                    onTap: () => removeTags(entry),
                                  ),
                                  _ActionChip(
                                    label: 'Delete',
                                    danger: true,
                                    onTap: () => delete(entry),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          ],
      ],
    );
  }
}

/// One of the three actions under a pool row (Plans › All Halloween: add, edit,
/// remove): 44 px, neutral fill.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      kind: danger ? AppButtonKind.softDestructive : AppButtonKind.soft,
      compact: true,
      horizontalPadding: 14,
      onPressed: onTap,
    );
  }
}

/// A plan row's subtitle: as in the library, except that a song names its
/// artist ("Wham! · 1984"), since plans mix every type and artist.
String planRowSubtitle(Entry entry) =>
    entry.type == MediaType.music && entry.kind == EntryKind.song
    ? songSubtitle(entry)
    : entrySubtitle(entry);
