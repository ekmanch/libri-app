import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/sync/sync_status.dart';
import 'package:library_app/features/sync/sync_scheduler.dart';

import '../../helpers/fake_library_sync.dart';

void main() {
  late FakeLibrarySync sync;
  var now = DateTime(2026, 10, 13, 20);

  setUp(() {
    sync = FakeLibrarySync();
    now = DateTime(2026, 10, 13, 20);
  });

  SyncScheduler scheduler() => SyncScheduler(sync: () => sync, now: () => now);

  /// The engine walks through inactive on the way to and from hidden; the
  /// test binding does not, so the test does.
  void hide(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }

  void resume(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('checks when the app comes back to the foreground', (
    tester,
  ) async {
    final s = scheduler()..start();
    expect(sync.checks, 0);
    hide(tester);
    resume(tester);
    await tester.pump();
    expect(sync.checks, 1);
    s.dispose();
  });

  testWidgets('checks every 30 seconds in the foreground only', (tester) async {
    final s = scheduler()..start();
    await tester.pump(const Duration(seconds: 30));
    expect(sync.checks, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(sync.checks, 2);
    hide(tester);
    await tester.pump(const Duration(minutes: 20));
    expect(sync.checks, 2, reason: 'nothing while hidden');
    resume(tester);
    await tester.pump();
    expect(sync.checks, 3);
    s.dispose();
  });

  testWidgets('coming back skips the check made moments ago', (tester) async {
    final s = scheduler()..start();
    sync.status = SyncStatus(lastChecked: now);
    hide(tester);
    resume(tester);
    await tester.pump();
    expect(sync.checks, 0, reason: 'checked just now');
    // The timer runs again from the resume.
    await tester.pump(const Duration(seconds: 30));
    expect(sync.checks, 1);
    hide(tester);
    now = now.add(const Duration(seconds: 15));
    resume(tester);
    await tester.pump();
    expect(sync.checks, 2, reason: 'past the guard');
    s.dispose();
  });

  testWidgets('a tab switch checks only when the last check is old', (
    tester,
  ) async {
    final s = scheduler();
    expect(s.isStale, isTrue, reason: 'never checked');
    s.onTabSwitch();
    expect(sync.checks, 1);
    sync.status = SyncStatus(lastChecked: now);
    s.onTabSwitch();
    expect(sync.checks, 1);
    now = now.add(const Duration(seconds: 20));
    s.onTabSwitch();
    expect(sync.checks, 1);
    now = now.add(const Duration(seconds: 10));
    s.onTabSwitch();
    expect(sync.checks, 2);
    s.dispose();
  });

  testWidgets('dispose stops the timer and the lifecycle listener', (
    tester,
  ) async {
    scheduler()
      ..start()
      ..dispose();
    await tester.pump(const Duration(minutes: 10));
    hide(tester);
    resume(tester);
    await tester.pump();
    expect(sync.checks, 0);
  });

  testWidgets('without a sync nothing happens', (tester) async {
    final s = SyncScheduler(sync: () => null, now: () => now)..start();
    await tester.pump(const Duration(seconds: 30));
    s.onTabSwitch();
    expect(s.isStale, isTrue);
    s.dispose();
  });
}
