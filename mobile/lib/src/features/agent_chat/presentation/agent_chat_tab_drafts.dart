part of 'agent_chat_tab_view.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AgentChatTabDrafts on _AgentChatTabViewState {
  void _persistDraft() {
    if (_restoring) return;
    typing.keystroke();
    _store.write(
      widget.hostId,
      widget.chatId,
      AgentChatComposerDraft(value: _composer.value, attachments: _attachments),
      workspaceId: widget.workspaceId,
    );
  }

  /// An upload finished or a refused prompt came back while this was shown.
  void _restoreStoredDraft() {
    if (!mounted) return;
    final draft = _store.read(
      widget.hostId,
      widget.chatId,
      workspaceId: widget.workspaceId,
    );
    _restoring = true;
    _composer.value = draft.value;
    _restoring = false;
    setState(() => _attachments = draft.attachments);
  }

  Future<void> _sendDraft({bool steer = false}) async {
    final draft = AgentChatComposerDraft(
      value: _composer.value,
      attachments: _attachments,
    );
    if (!draft.canSubmit) return;
    final plan = switch (ref.read(_provider).value) {
      final AgentChatViewState view => agentChatApprovalSend(
        view.timeline.requests,
      ),
      null => null,
    };
    if (plan != null) return _sendOverApprovals(plan, draft, steer: steer);
    final clientMessageId = _store
        .submissionIds(
          widget.hostId,
          widget.chatId,
          workspaceId: widget.workspaceId,
        )
        .claim(draft.signature, _uuid.v4);
    _store.beginSubmission(
      widget.hostId,
      widget.chatId,
      clientMessageId,
      draft,
      workspaceId: widget.workspaceId,
    );
    typing.settle();
    _restoring = true;
    _composer.clear();
    _restoring = false;
    setState(() => _attachments = const <AgentChatDraftAttachment>[]);
    _store.write(
      widget.hostId,
      widget.chatId,
      const AgentChatComposerDraft(),
      workspaceId: widget.workspaceId,
    );
    scrollToEnd.value += 1;
    try {
      await ref.read(_provider.notifier).send(draft, steer: steer);
    } on Object catch (error, stackTrace) {
      _store.restore(
        widget.hostId,
        widget.chatId,
        draft,
        workspaceId: widget.workspaceId,
      );
      _report('Could not send the message.', error, stackTrace);
    }
  }

  /// The draft stays in the composer until the approvals are answered and
  /// the message is taken, and clears only if it is still what was sent.
  Future<void> _sendOverApprovals(
    AgentChatApprovalSend plan,
    AgentChatComposerDraft draft, {
    required bool steer,
  }) async {
    bool draftChanged() =>
        !mounted ||
        AgentChatComposerDraft(
              value: _composer.value,
              attachments: _attachments,
            ).signature !=
            draft.signature;
    typing.settle();
    try {
      final outcome = await ref
          .read(_provider.notifier)
          .sendOverApprovals(
            plan,
            draft,
            steer: steer,
            draftChanged: draftChanged,
          );
      if (!mounted) return;
      if (outcome.error ?? outcome.notice case final String message) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(message)));
      }
      if (!outcome.sent || draftChanged()) return;
      _restoring = true;
      _composer.clear();
      _restoring = false;
      setState(() => _attachments = const <AgentChatDraftAttachment>[]);
      _store.write(
        widget.hostId,
        widget.chatId,
        const AgentChatComposerDraft(),
        workspaceId: widget.workspaceId,
      );
      scrollToEnd.value += 1;
    } on Object catch (error, stackTrace) {
      _report('Could not send the message.', error, stackTrace);
    }
  }
}
