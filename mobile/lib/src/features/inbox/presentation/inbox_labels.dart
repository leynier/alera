import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';

AleraBadgeTone inboxStatusTone(InboxQuestionStatus status) => switch (status) {
  InboxQuestionStatus.answered => AleraBadgeTone.success,
  InboxQuestionStatus.delivered ||
  InboxQuestionStatus.received => AleraBadgeTone.info,
  InboxQuestionStatus.expired => AleraBadgeTone.attention,
  InboxQuestionStatus.pending ||
  InboxQuestionStatus.cancelled ||
  InboxQuestionStatus.unknown => AleraBadgeTone.neutral,
};

/// What the asker can expect, in words.
String inboxStatusHint(InboxQuestionStatus status) => switch (status) {
  InboxQuestionStatus.pending => 'Waiting for the agent to finish its turn before the question is delivered.',
  InboxQuestionStatus.delivered =>
    'Delivered to the agent. The answer appears here when it replies.',
  InboxQuestionStatus.received => 'The coordinator read the question. The answer appears here when it replies.',
  InboxQuestionStatus.answered => 'The agent answered.',
  InboxQuestionStatus.expired =>
    'The question expired before it reached the agent.',
  InboxQuestionStatus.cancelled => 'The question was cancelled.',
  InboxQuestionStatus.unknown => 'The runtime reported an unknown state.',
};

String inboxDeliveryHint(InboxDeliveryMode mode) => switch (mode) {
  InboxDeliveryMode.paste =>
    'Questions reach this agent when it finishes its turn.',
  InboxDeliveryMode.check =>
    'This terminal coordinates a run and reads questions on its next check.',
  InboxDeliveryMode.unavailable => 'This agent is not running or does not report its status, so questions wait.',
};

/// Compact age such as `5m ago`, or a date once it is a week old.
String inboxAgeLabel(DateTime? value, DateTime now) {
  if (value == null) return '';
  final age = now.difference(value);
  if (age < const Duration(minutes: 1)) return 'just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m ago';
  if (age < const Duration(days: 1)) return '${age.inHours}h ago';
  if (age < const Duration(days: 7)) return '${age.inDays}d ago';
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// Time left before a pending question expires, such as `4h 20m`.
String? inboxExpiryLabel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return null;
  final left = expiresAt.difference(now);
  if (left <= Duration.zero) return 'Expires now';
  if (left.inHours >= 1) {
    return 'Expires in ${left.inHours}h ${left.inMinutes.remainder(60)}m';
  }
  return 'Expires in ${left.inMinutes.clamp(1, 59)}m';
}

String _two(int value) => value.toString().padLeft(2, '0');
