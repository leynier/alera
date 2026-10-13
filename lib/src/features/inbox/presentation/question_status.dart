import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/pull_requests/domain/comment_relative_time.dart';

/// Labels and tones for questions, shared by the list, the thread and the
/// Ask Agent dialog.
extension QuestionStatusLabel on InboxQuestionStatus {
  String get label => switch (this) {
    .pending => 'Pending',
    .delivered => 'Delivered',
    .answered => 'Answered',
    .expired => 'Expired',
    .cancelled => 'Cancelled',
  };

  AleraBadgeTone get tone => switch (this) {
    .pending || .cancelled => AleraBadgeTone.neutral,
    .delivered => AleraBadgeTone.info,
    .answered => AleraBadgeTone.success,
    .expired => AleraBadgeTone.attention,
  };
}

/// What asking an agent with `now` would do, shown beside each target.
String questionTargetDeliveryLabel(InboxDeliveryMode mode) => switch (mode) {
  .pastedNow => 'Delivers now',
  .queuedAtTurnEnd => 'Delivers when its turn ends',
  .check => 'Reads on its next check',
  .unavailable => 'Cannot receive questions now',
};

/// How an asked question reaches the agent, for the thread header.
String? questionDeliveryLabel(InboxDeliveryMode? mode) => switch (mode) {
  .pastedNow => 'Delivered now',
  .queuedAtTurnEnd => 'Delivers when its turn ends',
  .check => 'Read on its next check',
  .unavailable || null => null,
};

/// The delivery a thread header describes. `inboxV2` hosts report it; older
/// hosts only say how a still-open question would reach the agent now.
InboxDeliveryMode? questionThreadDeliveryMode(InboxThreadDetail detail) {
  final question = detail.latestQuestion;
  if (detail.thread.deliveryMode case final mode?) return mode;
  if (question?.deliveryMode case final mode?) return mode;
  if (question != null && question.deliveredNow) {
    return InboxDeliveryMode.pastedNow;
  }
  return detail.thread.status.open ? detail.recipient.deliveryMode : null;
}

/// Explains a delivery mode that will not paste the question by itself.
String? questionDeliveryHint(InboxDeliveryMode mode) => switch (mode) {
  .pastedNow || .queuedAtTurnEnd => null,
  .check => 'This agent coordinates a run and reads questions when it checks its messages.',
  .unavailable => 'This agent does not report its turns, so the question waits until it does or expires.',
};

const String questionDeliverNowHelper =
    "The question is pasted into the agent's terminal right away.";

String questionDeliverTurnEndHelper(Duration expiry) =>
    'The agent receives the question when it finishes its turn. If that does not happen within ${questionExpiryProse(expiry)}, the question expires.';

/// Why `now` cannot be chosen for a target, or null when it can.
String? questionDeliverNowUnavailableReason(InboxDeliveryMode mode) =>
    switch (mode) {
      .pastedNow || .check => null,
      .queuedAtTurnEnd => 'This agent cannot take input while it works, so it receives the question when its turn ends.',
      .unavailable => 'This agent does not report its turns, so the question waits until it does or expires.',
    };

/// Shown instead of the delivery choice by hosts without `inboxV2`.
const String questionLegacyDeliveryCaption =
    'Agents receive a question when they finish their turn and answer with alera orchestration reply. Undelivered questions expire after 5 hours by default; history is kept for 7 days.';

const List<Duration> questionExpiryChoices = <Duration>[
  Duration(hours: 1),
  Duration(hours: 5),
  Duration(days: 1),
  Duration(days: 7),
];

/// The runtime's own default, so an unchanged choice sends nothing.
const Duration questionDefaultExpiry = Duration(hours: 5);

String questionExpiryLabel(Duration value) => value.inDays > 0
    ? '${value.inDays} Day${value.inDays == 1 ? '' : 's'}'
    : '${value.inHours} Hour${value.inHours == 1 ? '' : 's'}';

String questionExpiryProse(Duration value) =>
    questionExpiryLabel(value).toLowerCase();

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
