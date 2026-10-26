part of 'agent_chat_controller.dart';

/// Sending while approvals wait: the text answers the agent instead of
/// queueing behind a turn that cannot go on.
extension AgentChatApprovalSending on AgentChatController {
  /// Sends a composed prompt while the approvals in [plan] wait: as feedback
  /// that declines the shown one, or as a message that declines them all and
  /// redirects the agent. The composer keeps the draft until the outcome
  /// says it was sent; [draftChanged] tells whether it no longer holds
  /// [draft], which stops the message.
  Future<AgentChatApprovalSendOutcome> sendOverApprovals(
    AgentChatApprovalSend plan,
    AgentChatComposerDraft draft, {
    bool steer = false,
    required bool Function() draftChanged,
  }) async {
    if (!draft.canSubmit) return const AgentChatApprovalSendOutcome();
    final sync = _ready();
    if (sync.view!.nativeOperationPending) {
      throw const AgentChatRequestException(
        message: 'The last history change has not finished yet.',
        code: AgentChatErrorCodes.nativeOperationPending,
      );
    }
    return agentChatSendOverApprovals(
      plan,
      text: draft.text,
      hasAttachments: draft.attachments.isNotEmpty,
      port: AgentChatApprovalSendPort(
        draftChanged: draftChanged,
        current: () => _current(sync),
        pendingRequests: () =>
            sync.view?.timeline.requests ?? const <AgentChatRequest>[],
        respondingRequestIds: () =>
            sync.view?.respondingRequestIds ?? const <String>{},
        respond: respond,
        atomic: () => _offers(AgentChatWire.approvalRedirectCapability),
        sendDeclining: (ids) => _sendDeclining(sync, draft, ids, steer: steer),
        send: () async {
          await send(draft, steer: steer);
          return true;
        },
      ),
    );
  }

  /// One request that declines [declineRequestIds] and admits the message.
  /// The draft stays in the composer until it returns, so a refusal leaves
  /// nothing to retry from the timeline.
  Future<void> _sendDeclining(
    AgentChatSync sync,
    AgentChatComposerDraft draft,
    List<String> declineRequestIds, {
    required bool steer,
  }) async {
    final ids = _submissionIds();
    final view = sync.view!;
    final message = AgentChatOutgoingMessage(
      clientMessageId: ids.claim(draft.signature, _uuid.v4),
      text: draft.text,
      createdAt: DateTime.now().toUtc(),
      attachments: <AgentChatAttachment>[
        for (final attachment in draft.attachments) attachment.toAttachment(),
      ],
      status: AgentChatOutgoingStatus.accepted,
    );
    await sync.repository.send(
      AgentChatSendInput(
        chatId: chatId,
        workspaceId: workspaceId,
        clientMessageId: message.clientMessageId,
        text: message.text,
        attachments: message.attachments,
        delivery: steer && view.turnActive && view.session.capabilities.steer
            ? AgentChatDelivery.steer
            : AgentChatDelivery.auto,
        declineRequestIds: declineRequestIds,
      ),
    );
    ids.settled(draft.signature);
    if (!_current(sync) ||
        (sync.view?.thread.containsClientMessage(message.clientMessageId) ??
            true)) {
      return;
    }
    _putOutgoing(sync, message);
  }
}
