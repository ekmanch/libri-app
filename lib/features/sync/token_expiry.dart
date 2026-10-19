import '../../widgets/labels.dart';
import 'sync_state.dart';

/// The rules behind the token expiry warning (Library › Token expires soon) and
/// the "Token expired" sync state. GitHub says when a token expires in a header
/// on every answer; the connection keeps the date
/// ([LibraryConnection.tokenExpires]).

/// The Library › Token expires soon dialog shows from this long before the
/// expiry.
const tokenWarningWindow = Duration(days: 7);

/// Where "Open GitHub" goes: the fine-grained tokens page, where a token
/// is regenerated with a new expiry date.
final gitHubTokensUrl = Uri.parse(
  'https://github.com/settings/personal-access-tokens',
);

/// Whole calendar days from [now]'s date to [when]'s, both in local time:
/// 0 for today, 1 for tomorrow, negative for a day gone by.
int daysUntil(DateTime when, DateTime now) {
  final day = when.toLocal();
  final today = now.toLocal();
  return DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
}

/// Whether the Library › Token expires soon dialog is due: the token expires
/// within [tokenWarningWindow] but has not yet (a date that passed while
/// requests still succeed is ignored, as is one with no date), and it was
/// not shown today.
bool tokenWarningDue({
  required DateTime? expires,
  required DateTime? warnedOn,
  required DateTime now,
}) {
  if (expires == null || !expires.isAfter(now)) return false;
  if (expires.difference(now) > tokenWarningWindow) return false;
  return warnedOn == null || daysUntil(warnedOn, now) != 0;
}

/// Whether the token has expired, as far as the connection knows: the
/// date GitHub gave has passed. With a 401 that makes "Token expired"
/// rather than "GitHub refused the token".
bool tokenHasExpired(LibraryConnection connection, DateTime now) =>
    switch (connection.tokenExpires) {
      null => false,
      final expires => !expires.isAfter(now),
    };

/// "Your GitHub token expires in 6 days", "… in 1 day", "… today".
String tokenExpiryTitle(DateTime expires, DateTime now) {
  final days = daysUntil(expires, now);
  final when = switch (days) {
    <= 0 => 'today',
    1 => 'in 1 day',
    _ => 'in $days days',
  };
  return 'Your GitHub token expires $when';
}

/// "October 24", with the year when it is not this one.
String tokenExpiryDate(DateTime expires, DateTime now) {
  final day = expires.toLocal();
  final name = monthNames[day.month - 1];
  return day.year == now.toLocal().year
      ? '$name ${day.day}'
      : '$name ${day.day}, ${day.year}';
}
