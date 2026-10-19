import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tapping Library in the pill while already on the Library tab's home
/// (Library › Home): the home scrolls back to the top, so the title, the search
/// box and the chips are in view again; at the top it returns to All, with the
/// filter and the type cleared and the status segment reset. The state counts
/// the taps; the home screen listens and decides which of the two it is, since
/// only it knows the scroll position.
class HomeReturnNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void goHome() => state++;
}

final homeReturnProvider = NotifierProvider<HomeReturnNotifier, int>(
  HomeReturnNotifier.new,
);
