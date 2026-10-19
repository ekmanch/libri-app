import 'package:flutter/material.dart';

import '../../data/models/plan.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fitted_title.dart';
import '../plans/plan_progress.dart';

/// The card on the library home for the plan in progress (Library › Home).
class ActivePlanCard extends StatelessWidget {
  const ActivePlanCard({super.key, required this.plan, this.onTap});

  final Plan plan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final done = doneCount(plan);
    final total = plan.items.length;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: colors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACTIVE PLAN',
                            style: theme.textTheme.labelSmall!.copyWith(
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Shrinks a step before cutting off, like the plan
                          // header, so the year stays in view.
                          FittedTitle(
                            planTitle(plan),
                            style: theme.textTheme.titleLarge!,
                            sizes: const [20, 18, 16],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$done of $total done',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 8,
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
