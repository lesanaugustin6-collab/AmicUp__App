import 'package:intl/intl.dart';

String formatChatTimestamp(DateTime utcDateTime) {
  final localTime = utcDateTime.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final startOfThisWeek = today.subtract(Duration(days: today.weekday - 1));

  final localDay = DateTime(localTime.year, localTime.month, localTime.day);

  if (localDay == today) {
    return DateFormat.jm().format(localTime);
  }

  if (localDay == yesterday) {
    return 'Yesterday, ${DateFormat.jm().format(localTime)}';
  }

  if (localTime.isAfter(startOfThisWeek) || localDay.isAfter(startOfThisWeek)) {
    return '${DateFormat.E().format(localTime)} ${DateFormat.jm().format(localTime)}';
  }

  return '${DateFormat.MMMd().format(localTime)}, ${DateFormat.jm().format(localTime)}';
}

bool shouldShowTimestampHeader(DateTime currentMsgUtc, DateTime? previousMsgUtc) {
  if (previousMsgUtc == null) {
    return true;
  }

  final differenceInMinutes = currentMsgUtc.difference(previousMsgUtc).inMinutes.abs();
  return differenceInMinutes >= 10;
}
