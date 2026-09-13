/// Compact age of a comment relative to [now], or null once it is a week old,
/// where a calendar date reads better than a count.
///
/// A timestamp in the future (clock skew between the forge and this machine)
/// reads as `just now` rather than a negative age.
String? commentRelativeTimeLabel(DateTime value, DateTime now) {
  final age = now.difference(value);
  if (age < const Duration(minutes: 1)) {
    return 'just now';
  }
  if (age < const Duration(hours: 1)) {
    return '${age.inMinutes}m ago';
  }
  if (age < const Duration(days: 1)) {
    return '${age.inHours}h ago';
  }
  if (age < const Duration(days: 7)) {
    return '${age.inDays}d ago';
  }
  return null;
}
