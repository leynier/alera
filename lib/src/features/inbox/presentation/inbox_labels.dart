import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/pull_requests/domain/comment_relative_time.dart';

AleraBadgeTone inboxStatusTone(InboxQuestionStatus status) => switch (status) {
  .pending => AleraBadgeTone.neutral,
  .received || .delivered => AleraBadgeTone.info,
  .answered => AleraBadgeTone.success,
  .expired => AleraBadgeTone.attention,
  .cancelled => AleraBadgeTone.done,
};

/// Explains a delivery mode that will not paste the question by itself.
String? inboxDeliveryHint(InboxDeliveryMode mode) => switch (mode) {
  .paste => null,
  .check => 'This agent coordinates a run and reads questions when it checks its messages.',
  .unavailable => 'This agent does not report its turns, so the question waits until it does or expires.',
};

String inboxTimeLabel(DateTime? value, DateTime now) {
  if (value == null) return '';
  final local = value.toLocal();
  return commentRelativeTimeLabel(local, now) ??
      '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// How long a pending question can still wait for the agent.
String? inboxExpiryLabel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return null;
  final left = expiresAt.difference(now);
  if (left <= Duration.zero) return 'Expires now';
  if (left < const Duration(hours: 1)) return 'Expires in ${left.inMinutes}m';
  if (left < const Duration(days: 1)) return 'Expires in ${left.inHours}h';
  return 'Expires in ${left.inDays}d';
}

String inboxAgentLabel(String? agent) => switch (agent) {
  null || '' => 'Agent',
  'codex' => 'Codex',
  'claude' => 'Claude',
  'copilot' => 'GitHub Copilot',
  'cursor' => 'Cursor',
  'agy' => 'Antigravity',
  'opencode' || 'opencode2' => 'OpenCode',
  'amp' => 'Amp',
  'grok' => 'Grok Build',
  'pi' => 'Pi',
  final other => other,
};

String _two(int value) => value.toString().padLeft(2, '0');
