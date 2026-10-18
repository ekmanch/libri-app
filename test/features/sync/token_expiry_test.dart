import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/features/sync/token_expiry.dart';

void main() {
  final now = DateTime(2026, 10, 18, 10, 30);

  test('days until count calendar days, not 24-hour spans', () {
    expect(daysUntil(DateTime(2026, 10, 18, 23, 59), now), 0);
    expect(daysUntil(DateTime(2026, 10, 19, 0, 1), now), 1);
    expect(daysUntil(DateTime(2026, 10, 24, 16, 20), now), 6);
    expect(daysUntil(DateTime(2026, 10, 17, 23), now), -1);
  });

  test('the warning is due in the last week, not shown today', () {
    bool due(DateTime? expires, {DateTime? warnedOn}) =>
        tokenWarningDue(expires: expires, warnedOn: warnedOn, now: now);
    expect(due(null), isFalse);
    expect(due(now.add(const Duration(days: 8))), isFalse);
    expect(due(now.add(const Duration(days: 7))), isTrue);
    expect(due(now.add(const Duration(days: 1))), isTrue);
    expect(due(now.add(const Duration(hours: 2))), isTrue);
    // A date that has passed while requests still succeed is ignored.
    expect(due(now), isFalse);
    expect(due(now.subtract(const Duration(days: 1))), isFalse);
    // Once a day: shown this morning, not again tonight.
    final soon = now.add(const Duration(days: 3));
    expect(due(soon, warnedOn: DateTime(2026, 10, 18)), isFalse);
    expect(due(soon, warnedOn: DateTime(2026, 10, 17)), isTrue);
  });

  test('a token has expired once the date GitHub gave has passed', () {
    expect(
      tokenHasExpired(const LibraryConnection(connected: true), now),
      isFalse,
    );
    expect(
      tokenHasExpired(
        LibraryConnection(
          connected: true,
          tokenExpires: now.add(const Duration(days: 2)),
        ),
        now,
      ),
      isFalse,
    );
    expect(
      tokenHasExpired(
        LibraryConnection(
          connected: true,
          tokenExpires: now.subtract(const Duration(minutes: 1)),
        ),
        now,
      ),
      isTrue,
    );
  });

  test('the title and the date read like the artboard', () {
    expect(
      tokenExpiryTitle(DateTime(2026, 10, 24, 16, 20), now),
      'Your GitHub token expires in 6 days',
    );
    expect(
      tokenExpiryTitle(DateTime(2026, 10, 19, 8), now),
      'Your GitHub token expires in 1 day',
    );
    expect(
      tokenExpiryTitle(DateTime(2026, 10, 18, 18), now),
      'Your GitHub token expires today',
    );
    expect(tokenExpiryDate(DateTime(2026, 10, 24, 16, 20), now), 'October 24');
    expect(tokenExpiryDate(DateTime(2027, 1, 2), now), 'January 2, 2027');
    // The header's date is UTC; the day shown is the local one.
    expect(
      tokenExpiryDate(DateTime.utc(2026, 10, 24, 16, 20), now),
      tokenExpiryDate(DateTime.utc(2026, 10, 24, 16, 20).toLocal(), now),
    );
  });
}
