import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';

const Duration agentChatTypingIdle = Duration(milliseconds: 1500);

String agentChatDecisionLabel(AgentChatApprovalDecision decision) =>
    switch (decision) {
      .accept => 'Allow Once',
      .acceptForSession => 'Allow For Session',
      .acceptAlways => 'Always Allow',
      .decline => 'Decline',
      .cancel => 'Cancel Turn',
    };

const String agentChatDeclineWithFeedbackLabel = 'Decline With Feedback';

/// Why an approval arrived although the session has full access.
String agentChatFullAccessOverrideMessage(
  AgentChatFullAccessOverride override,
) => switch (override) {
  .askRule =>
    'Asked despite full access: an ask rule in your settings matches this.',
  .providerCheck =>
    "Asked despite full access: the agent's own safety check flagged this.",
};

/// Whether [request] can be declined with feedback for the agent.
bool agentChatOffersDeclineFeedback(AgentChatRequest request) =>
    request.supportsFeedback &&
    request.offeredDecisions.contains(AgentChatApprovalDecision.decline);

String agentChatRequestTitle(AgentChatRequest request) {
  final title = request.title?.trim();
  return title == null || title.isEmpty
      ? agentChatRequestKindTitle(request.kind)
      : title;
}

String agentChatRequestKindTitle(AgentChatRequestKind kind) => switch (kind) {
  .commandExecutionApproval || .execCommandApproval => 'Run Command?',
  .fileReadApproval => 'Read File?',
  .fileChangeApproval || .applyPatchApproval => 'Apply File Changes?',
  .permissionApproval => 'Permission Request',
  .mcpElicitationApproval => 'Input Requested',
  .toolUserInput => 'Question',
  _ => kind.isApproval ? 'Approval Required' : 'The Agent Is Waiting',
};

/// Approval decision order is owned by the runtime; only requests are sorted.
List<AgentChatRequest> agentChatRequestDockOrder(
  Iterable<AgentChatRequest> requests,
) {
  final indexed = requests.indexed.toList();
  int priority(AgentChatRequest request) => request.isApproval
      ? 0
      : request.isElicitation
      ? 1
      : 2;
  indexed.sort((left, right) {
    final kind = priority(left.$2).compareTo(priority(right.$2));
    if (kind != 0) return kind;
    final age = left.$2.createdAt.compareTo(right.$2.createdAt);
    return age != 0 ? age : left.$1.compareTo(right.$1);
  });
  return List.unmodifiableOf(indexed.map((entry) => entry.$2));
}

/// A dock can take focus after typing has paused, a send, or a blur.
bool agentChatRequestMayTakeFocus({
  required DateTime now,
  DateTime? lastKeystroke,
  bool sentOrBlurred = false,
}) =>
    sentOrBlurred ||
    lastKeystroke == null ||
    now.difference(lastKeystroke) >= agentChatTypingIdle;
