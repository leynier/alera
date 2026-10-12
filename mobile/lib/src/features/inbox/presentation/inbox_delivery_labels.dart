import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';

/// What asking an agent with `now` would do, shown beside each target.
String inboxTargetDeliveryLabel(InboxDeliveryMode mode) => switch (mode) {
  InboxDeliveryMode.pastedNow => 'Delivers now',
  InboxDeliveryMode.queuedAtTurnEnd => 'Delivers when its turn ends',
  InboxDeliveryMode.check => 'Reads on its next check',
  InboxDeliveryMode.unavailable => 'Cannot receive questions now',
};

/// How an asked question reaches the agent, for the thread header.
String? inboxThreadDeliveryLabel(InboxDeliveryMode? mode) => switch (mode) {
  InboxDeliveryMode.pastedNow => 'Delivered now',
  InboxDeliveryMode.queuedAtTurnEnd => 'Delivers when its turn ends',
  InboxDeliveryMode.check => 'Read on its next check',
  InboxDeliveryMode.unavailable || null => null,
};

/// The delivery a thread header describes. `inboxV2` hosts report it; older
/// hosts only say how a still-open question would reach the agent now.
InboxDeliveryMode? inboxThreadDeliveryMode(InboxThreadDetail detail) {
  final question = detail.latestQuestion;
  if (detail.thread.deliveryMode case final mode?) return mode;
  if (question?.deliveryMode case final mode?) return mode;
  if (question != null && question.deliveredNow) {
    return InboxDeliveryMode.pastedNow;
  }
  final open =
      detail.thread.status == InboxQuestionStatus.pending ||
      detail.thread.status == InboxQuestionStatus.delivered;
  return open ? detail.recipient?.deliveryMode : null;
}

/// Explains a delivery mode that will not paste the question by itself.
String? inboxDeliveryHint(InboxDeliveryMode mode) => switch (mode) {
  InboxDeliveryMode.pastedNow || InboxDeliveryMode.queuedAtTurnEnd => null,
  InboxDeliveryMode.check => 'This agent coordinates a run and reads questions when it checks its messages.',
  InboxDeliveryMode.unavailable => 'This agent does not report its turns, so the question waits until it does or expires.',
};

const String inboxDeliverNowHelper =
    "The question is pasted into the agent's terminal right away.";

String inboxDeliverTurnEndHelper(Duration expiry) =>
    'The agent receives the question when it finishes its turn. If that does not happen within ${inboxExpiryProse(expiry)}, the question expires.';

/// Why `now` cannot be chosen for a target, or null when it can.
String? inboxDeliverNowUnavailableReason(InboxDeliveryMode mode) =>
    switch (mode) {
      InboxDeliveryMode.pastedNow || InboxDeliveryMode.check => null,
      InboxDeliveryMode.queuedAtTurnEnd => 'This agent cannot take input while it works, so it receives the question when its turn ends.',
      InboxDeliveryMode.unavailable => 'This agent does not report its turns, so the question waits until it does or expires.',
    };

/// The delivery actually sent: `now` falls back to `turnEnd` for an agent
/// that cannot take a question mid-turn.
InboxDelivery effectiveInboxDelivery(
  InboxDelivery chosen,
  InboxDeliveryMode? targetMode,
) => chosen == InboxDelivery.now && !(targetMode?.acceptsNow ?? true)
    ? InboxDelivery.turnEnd
    : chosen;

/// Shown instead of the delivery choice by hosts without `inboxV2`.
const String inboxLegacyDeliveryNote =
    'The agent receives the question when it finishes its turn. If that does not happen within 5 hours, the question expires.';

const List<Duration> inboxExpiryChoices = <Duration>[
  Duration(hours: 1),
  Duration(hours: 5),
  Duration(days: 1),
  Duration(days: 7),
];

/// The runtime's own default, so an unchanged choice sends nothing.
const Duration inboxDefaultExpiry = Duration(hours: 5);

/// The `expiresInMs` to send for a choice: null keeps the runtime default.
Duration? inboxExpiryToSend(Duration choice) =>
    choice == inboxDefaultExpiry ? null : choice;

String inboxExpiryChoiceLabel(Duration value) => value.inDays > 0
    ? '${value.inDays} Day${value.inDays == 1 ? '' : 's'}'
    : '${value.inHours} Hour${value.inHours == 1 ? '' : 's'}';

String inboxExpiryProse(Duration value) =>
    inboxExpiryChoiceLabel(value).toLowerCase();
