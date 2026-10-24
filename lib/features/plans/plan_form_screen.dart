import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/library.dart';
import '../../data/models/plan.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/chips.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/radio_mark.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/segmented_control.dart';
import '../../widgets/search_field.dart';
import '../../widgets/sheet_frame.dart';
import '../../widgets/switch_row.dart';
import '../settings/display_preferences.dart';
import 'plan_builders.dart';
import 'plan_dialogs.dart';
import 'plan_progress.dart';
import 'plan_season.dart';
import '../../widgets/tag_group.dart';
import '../library/tag_list_screen.dart';
import '../library/tag_sort.dart';

/// What the plan form came back with.
enum PlanFormOutcome { saved, deleted }

/// Opens Plans › New plan to make a plan. With [copyFrom] the form starts as a
/// copy of that plan for the following year (Plans › Plan menu, "Copy to a new
/// year"; the year chip's "New year…"). Resolves with the saved plan's id, or
/// null.
Future<String?> openNewPlanForm(BuildContext context, {Plan? copyFrom}) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      builder: (_) => PlanFormScreen.create(copyFrom: copyFrom),
    ),
  );
}

/// Opens Plans › Edit plan to edit [plan]. Resolves with what happened, or null
/// when the user went back.
Future<PlanFormOutcome?> openEditPlanForm(BuildContext context, Plan plan) {
  return Navigator.of(context, rootNavigator: true).push<PlanFormOutcome>(
    MaterialPageRoute(builder: (_) => PlanFormScreen.edit(plan)),
  );
}

enum _Start { empty, copy }

/// Plans › New plan and Edit plan: name, optional year, linked tags,
/// the seasonal theme switch when the tags imply a season, "Start with"
/// for a new plan, the timeline switch, and Delete plan when editing.
class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen.edit(Plan this.plan, {super.key}) : copyFrom = null;

  const PlanFormScreen.create({super.key, this.copyFrom}) : plan = null;

  final Plan? plan;
  final Plan? copyFrom;

  bool get isEditing => plan != null;

  /// Longer names would not fit a header even at the smallest size.
  static const maxNameLength = 60;

  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _year;
  late List<String> _tags;
  late bool _timeline;
  late bool _seasonal;
  late bool _started;
  late _Start _start;
  Plan? _source;
  bool _defaultsApplied = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    final copy = widget.copyFrom;
    _name = TextEditingController(text: plan?.name ?? copy?.name ?? '');
    _year = TextEditingController(
      text:
          plan?.year?.toString() ??
          (copy == null ? '' : '${nextYearFor(copy)}'),
    );
    _tags = [...?(plan ?? copy)?.tags];
    _timeline = (plan ?? copy)?.timeline ?? false;
    _seasonal = (plan ?? copy)?.seasonalTheme ?? true;
    _started = plan?.started ?? false;
    _start = copy == null ? _Start.empty : _Start.copy;
    _source = copy;
    _defaultsApplied = plan != null || copy != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    super.dispose();
  }

  String? get _yearError {
    final text = _year.text.trim();
    if (text.isEmpty) return null;
    final year = int.tryParse(text);
    return year != null && year >= 1900 && year <= 2999
        ? null
        : 'A year like 2027';
  }

  int? get _yearValue => int.tryParse(_year.text.trim());

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      _yearError == null &&
      (_start == _Start.empty || _source != null);

  Future<void> _pickTags(Library library) async {
    final picked = await showAppSheet<List<String>>(
      context,
      builder: (context) => _LinkedTagsSheet(library: library, selected: _tags),
    );
    if (picked != null && mounted) setState(() => _tags = picked);
  }

  Future<void> _pickSource(Library library) async {
    final picked = await showAppSheet<Plan>(
      context,
      builder: (context) => _CopyFromSheet(
        plans: library.plans,
        selected: _source,
        exclude: widget.plan?.id,
      ),
    );
    if (picked != null && mounted) setState(() => _useSource(picked));
  }

  /// Takes the source's tags and switches, and a name and year when none
  /// were typed yet.
  void _useSource(Plan source) {
    _source = source;
    if (_name.text.trim().isEmpty) _name.text = source.name;
    if (_year.text.trim().isEmpty) _year.text = '${nextYearFor(source)}';
    _tags = [...source.tags];
    _timeline = source.timeline;
    _seasonal = source.seasonalTheme;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final repository = ref.read(libraryRepositoryProvider);
    final library = await repository.load();
    final name = _name.text.trim();
    final year = _yearValue;
    final existing = widget.plan;
    if (existing != null) {
      await repository.apply(
        UpdatePlan(
          existing.copyWith(
            name: name,
            year: year,
            tags: _tags,
            timeline: _timeline,
            seasonalTheme: _seasonal,
            started: _started,
          ),
        ),
      );
      if (mounted) Navigator.pop(context, PlanFormOutcome.saved);
      return;
    }
    final id = newPlanId(name, year, library.plans.map((p) => p.id));
    final base = _start == _Start.copy && _source != null
        ? copyPlan(_source!, id: id, name: name, year: year)
        : Plan(id: id, name: name, year: year);
    final plan = base.copyWith(
      tags: _tags,
      timeline: _timeline,
      seasonalTheme: _seasonal,
    );
    final result = await repository.apply(AddPlan(plan));
    if (mounted) Navigator.pop(context, result.plans.last.id);
  }

  Future<void> _delete() async {
    final plan = widget.plan!;
    final ok = await confirmDeletePlan(context, plan);
    if (!ok || !mounted) return;
    await ref.read(libraryRepositoryProvider).apply(DeletePlan(plan.id));
    if (mounted) Navigator.pop(context, PlanFormOutcome.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final prefs = ref.watch(displayPreferencesProvider);
    final library = ref.watch(libraryProvider).value;
    if (!_defaultsApplied) {
      // A fresh plan starts with the switches as set in Settings.
      _defaultsApplied = true;
      _timeline = prefs.timelineDefault;
      _seasonal = prefs.seasonalThemeDefault;
    }
    final editing = widget.isEditing;
    final season = seasonForTags(_tags);
    final helpStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 13.5,
      fontStyle: FontStyle.normal,
      height: 1.4,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: editing ? 'Edit plan' : 'New plan',
              onBack: () => Navigator.pop(context),
              actions: [
                AppButton(
                  label: editing ? 'Save' : 'Create',
                  compact: true,
                  onPressed: _canSave ? _save : null,
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('Name'),
                            AppTextField(
                              controller: _name,
                              hintText: 'Summer vacation',
                              maxLength: PlanFormScreen.maxNameLength,
                              autofocus: !editing && _name.text.isEmpty,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 104,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('Year (optional)'),
                            TextField(
                              controller: _year,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) => setState(() {}),
                              style: theme.textTheme.bodyLarge!.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: '2027',
                                errorText: _yearError,
                                fillColor: theme.colorScheme.surface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (editing) ...[
                    const SizedBox(height: 14),
                    // Plan states, from the Plans › Edit plan note: on is
                    // Active, off is Not started; the first date turns it on by
                    // itself.
                    SwitchRow(
                      label: 'Started',
                      value: _started,
                      onChanged: (on) => setState(() => _started = on),
                      help: _started
                          ? 'Active. Stays active after its end date until '
                                'every entry is done or removed.'
                          : 'Not started. Turns on by itself when the '
                                "plan's first date comes.",
                    ),
                  ],
                  const SizedBox(height: 14),
                  const FieldLabel('Linked hashtags (optional)'),
                  FieldButton(
                    placeholder: _tags.isEmpty,
                    padding: _tags.isEmpty
                        ? const EdgeInsets.fromLTRB(14, 8, 12, 8)
                        : const EdgeInsets.fromLTRB(8, 8, 12, 8),
                    semanticsLabel: _tags.isEmpty
                        ? 'Linked hashtags, none'
                        : 'Linked hashtags, ${_tags.map((t) => '#$t').join(', ')}',
                    onTap: library == null ? () {} : () => _pickTags(library),
                    child: _tags.isEmpty
                        ? const Text('Choose from your tags')
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final tag in _tags) TagChip(tag)],
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Adds a second tab with everything in the library that '
                    'has any of these tags. Leave empty for a free-form plan.',
                    style: helpStyle,
                  ),
                  if (season != null) ...[
                    const SizedBox(height: 18),
                    SwitchRow(
                      label: 'Seasonal theme',
                      value: _seasonal,
                      onChanged: (on) => setState(() => _seasonal = on),
                      help: _seasonal
                          ? season.help
                          : 'This plan looks like any other plan.',
                    ),
                  ],
                  if (!editing) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Start with'),
                    SegmentedControl<_Start>(
                      segments: const [
                        SegmentOption(_Start.empty, 'Empty'),
                        SegmentOption(_Start.copy, 'Copy a plan'),
                      ],
                      selected: _start,
                      style: SegmentedStyle.accent,
                      equalWidths: true,
                      onChanged: (start) => setState(() {
                        _start = start;
                        // Offer the most recent plan to copy from.
                        if (start == _Start.copy &&
                            _source == null &&
                            library != null) {
                          final latest = _latestPlan(library);
                          if (latest != null) _useSource(latest);
                        }
                      }),
                    ),
                    if (_start == _Start.copy) ...[
                      const SizedBox(height: 8),
                      FieldButton(
                        placeholder: _source == null,
                        semanticsLabel: _source == null
                            ? 'Copy from, choose a plan'
                            : 'Copy from ${planTitle(_source!)}',
                        onTap: library == null
                            ? () {}
                            : () => _pickSource(library),
                        child: _source == null
                            ? const Text('Choose a plan to copy')
                            : Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Copy from ',
                                      style: TextStyle(color: colors.muted),
                                    ),
                                    TextSpan(text: planTitle(_source!)),
                                  ],
                                ),
                              ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _start == _Start.empty
                          ? 'You add entries yourself afterwards.'
                          : 'Entries you had not finished in that plan are '
                                'copied in.',
                      style: helpStyle,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SwitchRow(
                    label: 'Timeline',
                    value: _timeline,
                    onChanged: (on) => setState(() => _timeline = on),
                    help: [
                      _timeline
                          ? 'Entries sit on a timeline, each with a day or a '
                                'period.'
                          : 'A plain checklist without dates.',
                      if (!editing && _timeline == prefs.timelineDefault)
                        'Starts ${_timeline ? 'on' : 'off'}, as set in '
                            'Settings.',
                    ].join(' '),
                  ),
                ],
              ),
            ),
            if (editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: AppButton(
                  label: 'Delete plan',
                  kind: AppButtonKind.destructive,
                  onPressed: _delete,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The plan with the latest year, the last in the file on a tie.
  Plan? _latestPlan(Library library) {
    Plan? best;
    for (final plan in library.plans) {
      if (plan.id == widget.plan?.id) continue;
      if (best == null || (plan.year ?? 0) >= (best.year ?? 0)) best = plan;
    }
    return best;
  }
}

/// Multi-select of existing tags for a plan (Plans › Edit plan; New plan). No
/// tag is created here; that only happens in the entry form.
class _LinkedTagsSheet extends StatefulWidget {
  const _LinkedTagsSheet({required this.library, required this.selected});

  final Library library;
  final List<String> selected;

  @override
  State<_LinkedTagsSheet> createState() => _LinkedTagsSheetState();
}

class _LinkedTagsSheetState extends State<_LinkedTagsSheet> {
  late final List<String> _selected = [...widget.selected];
  String _query = '';

  void _toggle(String tag) => setState(() {
    if (!_selected.remove(tag)) _selected.add(tag);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    return SheetFrame(
      scrollable: true,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Linked hashtags',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              AppButton(
                label: 'Done',
                compact: true,
                onPressed: () => Navigator.pop(context, _selected),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchField(
            hintText: 'Search tags',
            onChanged: (value) => setState(() => _query = value),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Every category, A to Z; a long group is a row that opens Library ›
          // Filter: all Authors, like the filter sheet's.
          for (final MapEntry(key: category, value: names)
              in widget.library.tags.entries)
            if (names.any((n) => q.isEmpty || n.contains(q)))
              if (q.isEmpty && names.length > longTagGroup) ...[
                const SizedBox(height: 8),
                TagGroupRow(
                  label: category.label,
                  detail: tagGroupCountLabel(
                    category,
                    names.length,
                    names.where(_selected.contains).length,
                  ),
                  onTap: () => showTagListScreen(
                    context,
                    category: category,
                    tags: names,
                    selected: _selected.toSet(),
                    library: widget.library,
                    onToggle: _toggle,
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                  child: Text(
                    category.label.toUpperCase(),
                    style: theme.textTheme.labelSmall!.copyWith(fontSize: 12.5),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in sortedTags(
                      names.where((n) => q.isEmpty || n.contains(q)),
                    ))
                      PillChip(
                        label: '#$tag',
                        selected: _selected.contains(tag),
                        style: PillChipStyle.accent,
                        onTap: () => _toggle(tag),
                      ),
                  ],
                ),
              ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The plan to copy from (Plans › New plan).
class _CopyFromSheet extends StatelessWidget {
  const _CopyFromSheet({
    required this.plans,
    required this.selected,
    this.exclude,
  });

  final List<Plan> plans;
  final Plan? selected;
  final String? exclude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final choices = plans.where((p) => p.id != exclude).toList();
    return SheetFrame(
      title: 'Copy from',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (choices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No other plans to copy from.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.muted,
                ),
              ),
            ),
          for (final plan in choices)
            Semantics(
              button: true,
              selected: plan.id == selected?.id,
              child: RowInkWell(
                onTap: () => Navigator.pop(context, plan),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.divider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              planTitle(plan),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              switch (planState(plan)) {
                                PlanState.active => 'Active',
                                PlanState.notStarted => 'Not started',
                                PlanState.finished => 'Finished',
                              },
                              style: theme.textTheme.bodySmall!.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      RadioMark(selected: plan.id == selected?.id),
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
