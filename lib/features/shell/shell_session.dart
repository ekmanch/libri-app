import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the fresh starts of the app shell. The shell is keyed on it, so
/// bumping the count throws the shell away and builds a new one: the
/// Library tab, nothing pushed above its home, the home at the top. The
/// end of the first run (F8) does this, so a new connection always opens
/// on the library home whatever was on screen before (a reconnect from D6
/// starts above Settings, on either tab).
class ShellSessionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void restart() => state++;
}

final shellSessionProvider = NotifierProvider<ShellSessionNotifier, int>(
  ShellSessionNotifier.new,
);
