import 'package:alera_agent_chat/src/agent_chat_error_message.dart';
import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';
import 'package:alera_agent_chat/src/agent_chat_request_labels.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// What the composer's send does while approvals wait. The text answers the
/// agent instead of queueing behind a turn that cannot go on: it declines the
/// shown approval with the text as feedback when that approval takes
/// feedback, and otherwise declines every pending approval and goes out as a
/// message that redirects the agent.
class const AgentChatApprovalSend({
  required final List<AgentChatRequest> approvals,
  final AgentChatRequest? feedbackTarget,
}) {
  List<String> get approvalIds => <String>[
    for (final approval in approvals) approval.id,
  ];

  String get hint => feedbackTarget == null
      ? agentChatApprovalRedirectHint
      : agentChatApprovalFeedbackHint;

  String get sendLabel => feedbackTarget == null
      ? agentChatApprovalRedirectSendLabel
      : agentChatApprovalFeedbackSendLabel;
}

/// Null while no approval waits; the composer then sends as usual. The shown
/// approval is the first one the request dock opens on.
AgentChatApprovalSend? agentChatApprovalSend(
  Iterable<AgentChatRequest> requests,
) {
  final approvals = <AgentChatRequest>[
    for (final request in agentChatRequestDockOrder(requests))
      if (request.isApproval) request,
  ];
  if (approvals.isEmpty) return null;
  final shown = approvals.first;
  return AgentChatApprovalSend(
    approvals: List<AgentChatRequest>.unmodifiableOf(approvals),
    feedbackTarget: agentChatOffersDeclineFeedback(shown) ? shown : null,
  );
}

/// How a send over approvals ended. [sent] lets the composer clear when its
/// draft did not change meanwhile; [notice] says why nothing went out; [error]
/// belongs inline next to the composer.
class const AgentChatApprovalSendOutcome({
  final bool sent = false,
  final String? notice,
  final String? error,
});

/// What the app supplies to [agentChatSendOverApprovals].
class const AgentChatApprovalSendPort({
  /// Whether the draft is no longer the one the person sent.
  required final bool Function() draftChanged,

  /// Whether the same chat is still open on a live controller.
  required final bool Function() current,
  required final List<AgentChatRequest> Function() pendingRequests,
  required final Set<String> Function() respondingRequestIds,

  /// Answers one request; false when it was not answered.
  required final Future<bool> Function(
    AgentChatRequest request,
    AgentChatResponse response,
  )
  respond,

  /// Whether the runtime declines and admits in one step.
  required final Future<bool> Function() atomic,

  /// The message with [AgentChatSendInput.declineRequestIds]; throws when the
  /// runtime refuses it.
  required final Future<void> Function(List<String> declineRequestIds)
  sendDeclining,

  /// The message as a plain send, once the approvals are declined; false
  /// when it was not taken.
  required final Future<bool> Function() send,
});

/// The decision that declines [request] for a redirect, if it offers one.
AgentChatApprovalDecision? agentChatRedirectDecision(AgentChatRequest request) {
  final offered = request.offeredDecisions;
  if (offered.contains(AgentChatApprovalDecision.decline)) {
    return AgentChatApprovalDecision.decline;
  }
  return offered.contains(AgentChatApprovalDecision.cancel)
      ? AgentChatApprovalDecision.cancel
      : null;
}

/// Sends [text] over the approvals in [plan]. A draft that changed, an
/// approval that arrived or is already being answered, or a chat that closed
/// stops the message, so it never overrides an approval its sender did not
/// see. Runtimes without [AgentChatWire.approvalRedirectCapability] get the
/// same guards around a decline followed by a plain send.
Future<AgentChatApprovalSendOutcome> agentChatSendOverApprovals(
  AgentChatApprovalSend plan, {
  required String text,
  required bool hasAttachments,
  required AgentChatApprovalSendPort port,
}) async {
  final responding = port.respondingRequestIds();
  if (plan.feedbackTarget case final AgentChatRequest target) {
    if (hasAttachments) {
      return const AgentChatApprovalSendOutcome(
        error: agentChatApprovalFeedbackAttachmentsError,
      );
    }
    if (responding.contains(target.id) ||
        port.draftChanged() ||
        !port.current()) {
      return const AgentChatApprovalSendOutcome();
    }
    final sent = await port.respond(
      target,
      AgentChatApprovalResponse(
        AgentChatApprovalDecision.decline,
        feedback: text.trim(),
      ),
    );
    return AgentChatApprovalSendOutcome(sent: sent);
  }
  String? notice({
    bool draftChanged = false,
    bool declined = false,
    bool approvalResponding = false,
    bool approvalArrived = false,
  }) => agentChatApprovalRedirectNotice(
    draftChanged: draftChanged,
    declined: declined,
    approvalResponding: approvalResponding,
    approvalArrived: approvalArrived,
  );
  if (plan.approvals.any((approval) => responding.contains(approval.id))) {
    return AgentChatApprovalSendOutcome(
      notice: notice(approvalResponding: true),
    );
  }
  if (port.draftChanged()) {
    return AgentChatApprovalSendOutcome(notice: notice(draftChanged: true));
  }
  if (await port.atomic()) {
    if (!port.current()) return const AgentChatApprovalSendOutcome();
    try {
      await port.sendDeclining(plan.approvalIds);
      return const AgentChatApprovalSendOutcome(sent: true);
    } on AgentChatRequestException catch (error) {
      if (error.code != AgentChatErrorCodes.approvalsChanged) rethrow;
      return AgentChatApprovalSendOutcome(notice: error.message);
    }
  }
  final before = <String>{
    ...plan.approvalIds,
    for (final request in port.pendingRequests())
      if (request.isApproval) request.id,
  };
  var declined = true;
  for (final approval in plan.approvals) {
    final decision = agentChatRedirectDecision(approval);
    if (decision == null ||
        !await port.respond(approval, AgentChatApprovalResponse(decision))) {
      declined = false;
      break;
    }
  }
  if (!port.current()) return const AgentChatApprovalSendOutcome();
  final draftChanged = port.draftChanged();
  final approvalArrived = port.pendingRequests().any(
    (request) => request.isApproval && !before.contains(request.id),
  );
  if (!declined || draftChanged || approvalArrived) {
    return AgentChatApprovalSendOutcome(
      notice: notice(
        draftChanged: draftChanged,
        declined: declined,
        approvalArrived: approvalArrived,
      ),
    );
  }
  return AgentChatApprovalSendOutcome(sent: await port.send());
}
