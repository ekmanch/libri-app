import 'package:flutter/material.dart';

import '../../widgets/app_buttons.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/sheet_frame.dart';

/// Edits the note on a plan item (the "Plan note" of Plans › Entry details
/// (timeline on) and Entry details (timeline off)). Resolves with the new text,
/// or null when dismissed.
Future<String?> showPlanNoteSheet(
  BuildContext context, {
  required String title,
  required String current,
}) {
  return showAppSheet<String>(
    context,
    inheritTheme: true,
    builder: (context) => _PlanNoteSheet(title: title, current: current),
  );
}

class _PlanNoteSheet extends StatefulWidget {
  const _PlanNoteSheet({required this.title, required this.current});

  final String title;
  final String current;

  @override
  State<_PlanNoteSheet> createState() => _PlanNoteSheetState();
}

class _PlanNoteSheetState extends State<_PlanNoteSheet> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetFrame(
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan note', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  widget.title,
                  style: theme.textTheme.bodySmall!.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Done',
            compact: true,
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
          ),
        ],
      ),
      child: AppTextField(
        controller: _controller,
        hintText: 'Why it is in this plan, or anything to remember',
        maxLines: 4,
        autofocus: true,
      ),
    );
  }
}
