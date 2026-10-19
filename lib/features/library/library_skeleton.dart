import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../shell/app_shell.dart';

/// The library home while the library loads for the first time (First run ›
/// First load): grey blocks where the search box, chips, headings and rows will
/// be, and a line saying what is happening.
class LibrarySkeleton extends StatelessWidget {
  const LibrarySkeleton({super.key});

  // Widths of the two lines of each placeholder row, as a share of the
  // row, following the mockup.
  static const _rows = [
    (0.55, 0.22),
    (0.70, 0.30),
    (0.62, 0.18),
    (0.40, 0.26),
    (0.48, 0.34),
    (0.66, 0.20),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    Widget block(double width, double height, {double? radius}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.skeleton,
        borderRadius: BorderRadius.circular(radius ?? height / 2),
      ),
    );
    return Semantics(
      label: 'Loading your library from GitHub',
      excludeSemantics: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          10,
          20,
          AppShell.contentBottomPadding,
        ),
        children: [
          block(double.infinity, 52, radius: 14),
          const SizedBox(height: 12),
          // Like the real chip row, this runs past the edge of a narrow
          // phone, so it is a (frozen) horizontal list rather than a Row.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final (i, w) in const [
                  52.0,
                  96.0,
                  90.0,
                  88.0,
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  block(w, 44),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(
              'Loading your library from GitHub',
              style: theme.textTheme.bodyMedium!.copyWith(
                fontSize: 14,
                color: colors.muted,
              ),
            ),
          ),
          for (final (i, row) in _rows.indexed) ...[
            if (i.isEven)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: block(72, 12),
                ),
              ),
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.skeleton)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: row.$1,
                    child: block(double.infinity, 16),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: row.$2,
                    child: block(double.infinity, 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
