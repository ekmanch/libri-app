import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/bordered_row.dart';
import '../../widgets/chips.dart';
import '../../widgets/labels.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';
import '../entry/entry_form_screen.dart';
import '../entry/entry_header.dart';
import '../entry/rating_sheet.dart';
import '../settings/display_preferences.dart';
import '../settings/entry_view.dart';
import 'plan_dates.dart';
import 'plan_dialogs.dart';
import 'plan_done.dart';
import 'plan_note_sheet.dart';
import 'when_sheet.dart';

/// Opens an entry's details inside a plan (Plans › Entry details (timeline on)
/// and Entry details (timeline off)). Keeps the opener's theme, so a seasonal
/// accent carries over.
Future<void> showPlanEntrySheet(
  BuildContext context, {
  required String planId,
  required String entryId,
}) {
  return showAppSheet<void>(
    context,
    inheritTheme: true,
    builder: (context) => PlanEntrySheet(planId: planId, entryId: entryId),
  );
}

/// Entry details in a plan: a Mark as done button instead of the status
/// segments, the rating, "When" when the plan has a timeline, the plan note,
/// About, tags, Edit and Remove (Plans › Remove from plan, or everywhere).
class PlanEntrySheet extends ConsumerWidget {
  const PlanEntrySheet({
    super.key,
    required this.planId,
    required this.entryId,
  });

  final String planId;
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final libraryAsync = ref.watch(libraryProvider);
    if (!libraryAsync.hasValue) return const SizedBox(height: 120);
    final library = libraryAsync.value!;
    final plan = library.planById(planId);
    final entry = library.entryById(entryId);
    final item = plan?.itemFor(entryId);
    if (plan == null || entry == null || item == null) {
      // Gone. Only a sheet still on top closes itself: one already on its
      // way out must not pop the screen under it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox(height: 120);
    }
    final repository = ref.read(libraryRepositoryProvider);
    final showCover =
        ref.watch(displayPreferencesProvider).viewForEntry(entry) !=
        EntryView.text;

    Future<void> toggleDone() => togglePlanItemDoneWithUndo(
      context,
      ref,
      plan: plan,
      item: item,
      entry: entry,
    );

    Future<void> pickRating() async {
      final choice = await showRatingSheet(
        context,
        title: entry.title,
        current: entry.rating,
      );
      if (choice != null && choice.rating != entry.rating) {
        await repository.apply(SetRating(entry.id, choice.rating));
      }
    }

    Future<void> pickWhen() async {
      final choice = await showWhenSheet(context, current: item.when);
      if (choice != null && choice.when != item.when) {
        await repository.apply(
          SetPlanItem(plan.id, item.copyWith(when: choice.when)),
        );
      }
    }

    Future<void> editNote() async {
      final note = await showPlanNoteSheet(
        context,
        title: entry.title,
        current: item.note,
      );
      if (note != null && note != item.note) {
        await repository.apply(SetPlanItem(plan.id, item.copyWith(note: note)));
      }
    }

    Future<void> remove() async {
      final others = library.plans
          .where((p) => p.id != plan.id && p.itemFor(entry.id) != null)
          .toList();
      final choice = await showRemoveFromPlanDialog(
        context,
        entry: entry,
        plan: plan,
        otherPlans: others,
      );
      if (choice == null || !context.mounted) return;
      // Close first: the repository publishes the change before its apply
      // completes, and the sheet would close itself on seeing the item
      // gone, so a pop after the await would pop the screen underneath.
      Navigator.of(context).pop();
      await repository.apply(
        choice == RemoveChoice.fromPlan
            ? RemovePlanItem(plan.id, entry.id)
            : DeleteEntry(entry.id),
      );
    }

    return SheetFrame(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EntryHeader(entry: entry, showCover: showCover),
          const SizedBox(height: 14),
          AppButton(
            label: item.done ? 'Done. Tap to undo' : 'Mark as done',
            kind: item.done ? AppButtonKind.outline : AppButtonKind.primary,
            icon: const StrokeIcon(AppIcons.check),
            onPressed: toggleDone,
          ),
          const SizedBox(height: 13),
          BorderedRow(
            onTap: pickRating,
            semanticsLabel: 'Rating, ${ratingLabel(entry.rating)}',
            leading: const RowLabel('Rating'),
            trailing: RowValue(ratingLabel(entry.rating)),
          ),
          if (plan.timeline)
            BorderedRow(
              onTap: pickWhen,
              topBorder: false,
              semanticsLabel:
                  'When, ${item.when == null ? 'no date' : formatWhen(item.when!)}',
              leading: const RowLabel('When'),
              trailing: RowValue(
                item.when == null ? 'No date' : formatWhen(item.when!),
              ),
            ),
          const SizedBox(height: 13),
          Semantics(
            button: true,
            label: 'Plan note',
            child: InkWell(
              onTap: editNote,
              // At least 48 dp tall to tap, however short the note.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeading('Plan note', padding: EdgeInsets.zero),
                    const SizedBox(height: 6),
                    Text(
                      item.note.isEmpty ? 'Add a note' : item.note,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: item.note.isEmpty ? colors.placeholder : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: 13),
            const SectionHeading('About', padding: EdgeInsets.zero),
            const SizedBox(height: 6),
            Text(
              entry.description,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 14.5,
                color: colors.soft,
              ),
            ),
          ],
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final tag in entry.tags) TagChip(tag)],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Edit',
                  kind: AppButtonKind.soft,
                  onPressed: () => openEditEntryForm(context, entry),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Remove',
                  kind: AppButtonKind.soft,
                  onPressed: remove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
