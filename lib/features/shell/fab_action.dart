import 'package:flutter/painting.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'floating_nav_bar.dart';

/// What the round "+" button does while a screen inside a tab wants it for
/// something else than a new entry or plan: "Add from All Halloween" on a plan
/// (Plans › Plan checklist), "New Halloween entry" on its pool (Plans › All
/// Halloween: add, edit, remove).
@immutable
class FabAction {
  const FabAction({
    required this.owner,
    required this.tab,
    required this.label,
    required this.onPressed,
    this.accent,
  });

  /// The screen that set it, so a screen clears only its own action.
  final Object owner;
  final ShellTab tab;
  final String label;
  final VoidCallback onPressed;

  /// A seasonal accent for the button while a themed plan is open (Plans ›
  /// Halloween touches, Christmas touches); null keeps the user's accent.
  final Color? accent;
}

class FabActionNotifier extends Notifier<FabAction?> {
  @override
  FabAction? build() => null;

  void set(FabAction action) {
    if (ref.mounted) state = action;
  }

  /// Clears the action if [owner] set it. Safe to call while the app is
  /// being torn down, which is when the owning screen's dispose runs last.
  void clear(Object owner) {
    if (ref.mounted && state?.owner == owner) state = null;
  }
}

final fabActionProvider = NotifierProvider<FabActionNotifier, FabAction?>(
  FabActionNotifier.new,
);
