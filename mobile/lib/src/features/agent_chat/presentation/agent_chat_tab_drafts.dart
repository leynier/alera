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
}
