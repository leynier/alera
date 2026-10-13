/// `2026-10-11 18:15` in local time, for lists that show when something
/// happened.
String formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

/// `just now`, `2 min ago`, `3 h ago`, or the full [formatTimestamp] once a
/// day has passed.
String formatRelativeTimestamp(DateTime value, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(value);
  if (age.inMinutes < 1) {
    return 'just now';
  }
  if (age.inHours < 1) {
    return '${age.inMinutes} min ago';
  }
  if (age.inDays < 1) {
    return '${age.inHours} h ago';
  }
  return formatTimestamp(value);
}
