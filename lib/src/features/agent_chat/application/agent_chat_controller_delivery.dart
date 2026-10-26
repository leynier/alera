part of 'agent_chat_controller.dart';

mixin _AgentChatDelivery on _$AgentChatController {
  Future<void> _deliveryTail = Future<void>.value();
  AgentChatRepository get _repository;
  String Function() get _nextId;
  DateTime Function() get _now;
  AgentChatRef get _chat;
  AgentChatLifecycleRepository get _lifecycle;
  void _setOutgoing(List<AgentChatOutgoingMessage> outgoing);
  Future<bool> respond(AgentChatRequest request, AgentChatResponse response);

  /// Keeps this session's stand-in for the runtime's remembered selection,
  /// for runtimes without chat preferences.
  void _rememberSelection() {
    final thread = state.thread;
    if (thread == null || thread.providerInstanceId.isEmpty) return;
    final session = thread.session;
    ref
        .read(agentChatLaunchPreferenceProvider.notifier)
        .remember(
          AgentChatSelection(
            providerInstanceId: thread.providerInstanceId,
            model: session.model,
            runtimeMode: session.runtimeMode,
            interactionMode: session.interactionMode,
          ),
        );
  }

  String get _draftHostId {
    if (!ref.exists(workbenchControllerProvider)) return 'local';
    for (final workspaces
        in ref.read(workbenchControllerProvider).workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == workspaceId) return workspace.hostId;
      }
    }
    return 'local';
  }

  void _setPreparing(String id, bool preparing) => state = state.copyWith(
    preparingAttachmentIds: <String>{
      for (final current in state.preparingAttachmentIds)
        if (current != id) current,
      if (preparing) id,
    },
  );

  void _settleDraftSubmission(String id, {String? hostId}) => ref
      .read(agentChatComposerDraftsProvider)
      .settleSubmission(
        chatId,
        id,
        hostId: hostId ?? _draftHostId,
        workspaceId: workspaceId,
      );

  Future<void> _restorePendingOutgoing(AgentChatThread thread) async {
    final drafts = ref.read(agentChatComposerDraftsProvider);
    final hostId = _draftHostId;
    await drafts.ensureHydrated(
      chatId,
      hostId: hostId,
      workspaceId: workspaceId,
    );
    if (!ref.mounted) return;
    final outgoing = <AgentChatOutgoingMessage>[...state.outgoing];
    for (final submission in drafts.pending(
      chatId,
      hostId: hostId,
      workspaceId: workspaceId,
    )) {
      if (thread.containsClientMessage(submission.clientMessageId)) {
        drafts.settleSubmission(
          chatId,
          submission.clientMessageId,
          hostId: hostId,
          workspaceId: workspaceId,
        );
      } else if (!outgoing.any(
        (message) => message.clientMessageId == submission.clientMessageId,
      )) {
        outgoing.add(
          AgentChatOutgoingMessage(
            clientMessageId: submission.clientMessageId,
            text: submission.draft.text.trim(),
            createdAt: submission.createdAt,
            attachments: submission.input(chatId, workspaceId).attachments,
            status: .failed,
            error: 'Delivery was not confirmed. Retry to check it.',
          ),
        );
      }
    }
    _setOutgoing(outgoing);
    unawaited(drafts.flush());
  }

  /// Sends a message, or queues it behind a running turn. Returns whether
  /// the composer may clear: the message is now owned by the timeline, which
  /// shows its delivery and lets the user retry it.
  bool send(
    String text, {
    List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
    AgentChatDelivery delivery = AgentChatDelivery.auto,
  }) {
    final trimmed = text.trim();
    if (!state.canSend ||
        state.nativeOperationPending ||
        (trimmed.isEmpty && attachments.isEmpty)) {
      return false;
    }
    final drafts = ref.read(agentChatComposerDraftsProvider);
    final hostId = _draftHostId;
    final draft = AgentChatComposerDraft.fromMessage(trimmed, attachments);
    final message = AgentChatOutgoingMessage(
      clientMessageId: drafts.claimSubmissionId(
        chatId,
        draft,
        _nextId,
        hostId: hostId,
        workspaceId: workspaceId,
      ),
      text: trimmed,
      createdAt: _now().toUtc(),
      attachments: List<AgentChatAttachment>.unmodifiable(attachments),
    );
    final pending = state.pendingModel;
    // A provider default cannot travel on a message; it waits for idle.
    final model = pending?.model;
    if (model != null) state = state.copyWith(pendingModel: null);
    final firstSend = state.neverSent;
    _setOutgoing(<AgentChatOutgoingMessage>[
      for (final current in state.outgoing)
        if (current.clientMessageId != message.clientMessageId) current,
      message,
    ]);
    unawaited(
      _deliver(
        message,
        delivery == AgentChatDelivery.steer && !state.canSteer
            ? AgentChatDelivery.auto
            : delivery,
        model: model,
        firstSend: firstSend,
      ),
    );
    return true;
  }

  /// Sends composer text while the approvals in [plan] wait: as feedback
  /// that declines the shown one, or as a message that declines them all and
  /// redirects the agent. The composer keeps its draft until the outcome
  /// says it was sent; [draftChanged] tells whether it no longer holds what
  /// was sent, which stops the message.
  Future<AgentChatApprovalSendOutcome> sendOverApprovals(
    AgentChatApprovalSend plan,
    String text, {
    List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
    AgentChatDelivery delivery = AgentChatDelivery.auto,
    required bool Function() draftChanged,
  }) async {
    final trimmed = text.trim();
    if (!state.canSend ||
        state.nativeOperationPending ||
        (trimmed.isEmpty && attachments.isEmpty)) {
      return const AgentChatApprovalSendOutcome();
    }
    final keepAlive = ref.keepAlive();
    final lifecycle = _lifecycle;
    try {
      final outcome = await agentChatSendOverApprovals(
        plan,
        text: trimmed,
        hasAttachments: attachments.isNotEmpty,
        port: AgentChatApprovalSendPort(
          draftChanged: draftChanged,
          current: () => ref.mounted,
          pendingRequests: () =>
              state.projection?.requests ?? const <AgentChatRequest>[],
          respondingRequestIds: () => state.respondingRequestIds,
          respond: respond,
          atomic: () async {
            try {
              return await lifecycle.supports(
                AgentChatWire.approvalRedirectCapability,
              );
            } on Object {
              return false;
            }
          },
          sendDeclining: (ids) =>
              _sendDeclining(trimmed, attachments, delivery, ids),
          send: () async =>
              send(trimmed, attachments: attachments, delivery: delivery),
        ),
      );
      if (outcome.error case final String error when ref.mounted) {
        state = state.copyWith(actionError: error);
      }
      return outcome;
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(actionError: agentChatErrorMessage(error));
      }
      return const AgentChatApprovalSendOutcome();
    } finally {
      keepAlive.close();
    }
  }

  /// One request that declines [declineRequestIds] and admits the message.
  /// The draft stays in the composer until it returns, so a refusal leaves
  /// nothing to retry from the timeline.
  Future<void> _sendDeclining(
    String text,
    List<AgentChatAttachment> attachments,
    AgentChatDelivery delivery,
    List<String> declineRequestIds,
  ) async {
    final drafts = ref.read(agentChatComposerDraftsProvider);
    final hostId = _draftHostId;
    final repository = _repository;
    final clientMessageId = drafts.claimSubmissionId(
      chatId,
      AgentChatComposerDraft.fromMessage(text, attachments),
      _nextId,
      hostId: hostId,
      workspaceId: workspaceId,
    );
    final prepared =
        attachments.any(
          (attachment) =>
              attachment.localSourcePath != null &&
              attachment.attachmentId == null,
        )
        ? await ref.read(agentChatPrepareAttachmentsProvider)(
            _chat,
            attachments,
            clientMessageId,
          )
        : attachments;
    final createdAt = _now().toUtc();
    await repository.send(
      AgentChatSendInput(
        chatId: chatId,
        workspaceId: workspaceId,
        clientMessageId: clientMessageId,
        text: text,
        attachments: prepared,
        delivery: delivery == AgentChatDelivery.steer && !state.canSteer
            ? AgentChatDelivery.auto
            : delivery,
        declineRequestIds: declineRequestIds,
      ),
    );
    drafts.settleSubmission(
      chatId,
      clientMessageId,
      hostId: hostId,
      workspaceId: workspaceId,
    );
    if (!ref.mounted ||
        (state.thread?.containsClientMessage(clientMessageId) ?? false)) {
      return;
    }
    _setOutgoing(<AgentChatOutgoingMessage>[
      for (final current in state.outgoing)
        if (current.clientMessageId != clientMessageId) current,
      AgentChatOutgoingMessage(
        clientMessageId: clientMessageId,
        text: text,
        createdAt: createdAt,
        attachments: List<AgentChatAttachment>.unmodifiable(prepared),
        status: AgentChatOutgoingStatus.accepted,
      ),
    ]);
  }

  Future<void> retrySend(String clientMessageId) async {
    final message = state.outgoing
        .where((message) => message.clientMessageId == clientMessageId)
        .firstOrNull;
    if (message == null ||
        message.status != AgentChatOutgoingStatus.failed ||
        !state.canSend ||
        state.nativeOperationPending) {
      return;
    }
    _replaceOutgoing(message.withStatus(AgentChatOutgoingStatus.sending));
    final retained = ref
        .read(agentChatComposerDraftsProvider)
        .pending(chatId, hostId: _draftHostId, workspaceId: workspaceId)
        .where((submission) => submission.clientMessageId == clientMessageId)
        .firstOrNull;
    await _deliver(
      message,
      retained?.delivery ?? AgentChatDelivery.auto,
      model: retained?.model,
      reasoningEffort: retained?.reasoningEffort,
      interactionMode: retained?.interactionMode,
    );
  }

  Future<void> _deliver(
    AgentChatOutgoingMessage message,
    AgentChatDelivery delivery, {
    String? model,
    String? reasoningEffort,
    AgentChatInteractionMode? interactionMode,
    bool firstSend = false,
  }) async {
    // A send outlives the tab being hidden; its result must still land.
    final owner = ref;
    final keepAlive = owner.keepAlive();
    final repository = _repository;
    final drafts = owner.read(agentChatComposerDraftsProvider);
    final hostId = _draftHostId;
    final previous = _deliveryTail;
    final completed = Completer<void>();
    // A failed capture may finish early, but later sends still wait for all
    // earlier submissions instead of overtaking a file upload.
    _deliveryTail = previous.then((_) => completed.future);
    drafts.beginSubmission(
      chatId,
      message.clientMessageId,
      AgentChatComposerDraft.fromMessage(message.text, message.attachments),
      hostId: hostId,
      workspaceId: workspaceId,
      createdAt: message.createdAt,
      model: model,
      reasoningEffort: reasoningEffort,
      interactionMode: interactionMode,
      delivery: delivery,
      messageAttachments: message.attachments,
    );
    try {
      await drafts.flushSubmission(
        chatId,
        hostId: hostId,
        workspaceId: workspaceId,
      );
      await previous;
      if (!owner.mounted) return;
      if (message.attachments.any(
        (attachment) =>
            attachment.localSourcePath != null &&
            attachment.attachmentId == null,
      )) {
        _setPreparing(message.clientMessageId, true);
        final attachments = await owner.read(
          agentChatPrepareAttachmentsProvider,
        )(_chat, message.attachments, message.clientMessageId);
        message = AgentChatOutgoingMessage(
          clientMessageId: message.clientMessageId,
          text: message.text,
          createdAt: message.createdAt,
          attachments: attachments,
        );
        drafts.beginSubmission(
          chatId,
          message.clientMessageId,
          AgentChatComposerDraft.fromMessage(message.text, attachments),
          hostId: hostId,
          workspaceId: workspaceId,
          preserveComposer: false,
          createdAt: message.createdAt,
          model: model,
          reasoningEffort: reasoningEffort,
          interactionMode: interactionMode,
          delivery: delivery,
          messageAttachments: attachments,
        );
        await drafts.flushSubmission(
          chatId,
          hostId: hostId,
          workspaceId: workspaceId,
        );
        if (owner.mounted) {
          _replaceOutgoing(message);
          _setPreparing(message.clientMessageId, false);
        }
      }
      if (!owner.mounted) return;
      await repository.send(
        AgentChatSendInput(
          chatId: chatId,
          workspaceId: workspaceId,
          clientMessageId: message.clientMessageId,
          text: message.text,
          attachments: message.attachments,
          model: model,
          reasoningEffort: reasoningEffort,
          interactionMode: interactionMode,
          delivery: delivery,
        ),
      );
      if (owner.mounted) {
        _settleDraftSubmission(message.clientMessageId, hostId: hostId);
      } else {
        drafts.settleSubmission(
          chatId,
          message.clientMessageId,
          hostId: hostId,
          workspaceId: workspaceId,
        );
      }
      await drafts.flush();
      if (!owner.mounted) return;
      if (firstSend) _rememberSelection();
      _replaceOutgoing(message.withStatus(AgentChatOutgoingStatus.accepted));
    } on Object catch (error) {
      if (!owner.mounted) return;
      _replaceOutgoing(
        message.withStatus(
          AgentChatOutgoingStatus.failed,
          error: agentChatErrorMessage(error),
        ),
      );
    } finally {
      completed.complete();
      if (owner.mounted) _setPreparing(message.clientMessageId, false);
      keepAlive.close();
    }
  }

  void _replaceOutgoing(AgentChatOutgoingMessage message) {
    final thread = state.thread;
    if (thread != null &&
        thread.containsClientMessage(message.clientMessageId)) {
      _setOutgoing(<AgentChatOutgoingMessage>[
        for (final other in state.outgoing)
          if (other.clientMessageId != message.clientMessageId) other,
      ]);
      return;
    }
    _setOutgoing(<AgentChatOutgoingMessage>[
      for (final other in state.outgoing)
        other.clientMessageId == message.clientMessageId ? message : other,
    ]);
  }

  /// Drops a failed message and returns it so the composer can edit it.
  AgentChatOutgoingMessage? discardSend(String clientMessageId) {
    final message = state.outgoing
        .where((message) => message.clientMessageId == clientMessageId)
        .firstOrNull;
    if (message == null || message.status != AgentChatOutgoingStatus.failed) {
      return null;
    }
    _settleDraftSubmission(clientMessageId);
    _setOutgoing(<AgentChatOutgoingMessage>[
      for (final other in state.outgoing)
        if (other.clientMessageId != clientMessageId) other,
    ]);
    return message;
  }
}
