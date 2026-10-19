import '../../widgets/labels.dart';

/// "just now", "3 minutes ago", "yesterday", "Mar 14, 2026": how long ago [at]
/// was, as Settings › Library connection, First run › Pick a branch and Pick an
/// existing file say it.
String relativeTime(DateTime at, {required DateTime now}) {
  final difference = now.difference(at);
  if (difference.isNegative || difference.inSeconds < 60) return 'just now';
  final minutes = difference.inMinutes;
  if (minutes < 60) {
    return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
  }
  final hours = difference.inHours;
  if (hours < 24) return hours == 1 ? '1 hour ago' : '$hours hours ago';
  final days = difference.inDays;
  if (days == 1) return 'yesterday';
  if (days < 30) return '$days days ago';
  final local = at.toLocal();
  return '${monthAbbreviations[local.month - 1]} ${local.day}, ${local.year}';
}
