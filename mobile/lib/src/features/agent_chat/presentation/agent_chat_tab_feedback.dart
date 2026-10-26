part of 'agent_chat_tab_view.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AgentChatTabFeedback on _AgentChatTabViewState {
  /// Runs `/feedback` alone as Codex's command, as T3 Code does. Returns
  /// whether it took the send; the draft stays until the person confirms.
  bool _takeFeedback(AgentChatComposerDraft draft) {
    final view = ref.read(_provider).value;
    if (view == null || draft.attachments.isNotEmpty) return false;
    final supported =
        ref
            .read(
              agentChatCapabilityProvider(
                widget.hostId,
                AgentChatWire.feedbackCapability,
              ),
            )
            .value ??
        false;
    if (!agentChatFeedbackAvailable(
      supported: supported,
      commands: view.session.commands,
    )) {
      return false;
    }
    final command = parseAgentChatFeedbackCommand(draft.text);
    if (command == null) return false;
    if (view.neverSent) {
      _notify(agentChatFeedbackNeedsConversationMessage);
      return true;
    }
    final submissions = ref.read(agentChatFeedbackSubmissionsProvider.notifier);
    if (!submissions.claim(widget.hostId, widget.chatId)) return true;
    unawaited(_confirmFeedback(submissions, command, draft));
    return true;
  }

  Future<void> _confirmFeedback(
    AgentChatFeedbackSubmissions submissions,
    AgentChatFeedbackCommand command,
    AgentChatComposerDraft draft,
  ) async {
    final (hostId, chat) = (
      widget.hostId,
      AgentChatRef(chatId: widget.chatId, workspaceId: widget.workspaceId),
    );
    final AgentChatLifecycleRepository lifecycle;
    try {
      lifecycle = (await ref.read(agentChatRepositoryProvider(hostId).future))
          .lifecycle;
    } on Object catch (error, stackTrace) {
      submissions.release(hostId, chat.chatId);
      _report('Could not send feedback.', error, stackTrace);
      return;
    }
    if (!mounted) {
      submissions.release(hostId, chat.chatId);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: agentChatFeedbackConsentTitle,
        message: agentChatFeedbackConsentMessage(command),
        confirmLabel: agentChatFeedbackConsentConfirmLabel,
      ),
    );
    if (confirmed != true) {
      submissions.release(hostId, chat.chatId);
      return;
    }
    if (mounted && _composer.text == draft.value.text) {
      typing.settle();
      _restoring = true;
      _composer.clear();
      _restoring = false;
      _store.write(
        hostId,
        chat.chatId,
        const AgentChatComposerDraft(),
        workspaceId: chat.workspaceId,
      );
    }
    await submissions.submit(
      hostId: hostId,
      chat: chat,
      lifecycle: lifecycle,
      command: command,
      text: draft.text,
    );
  }
}
