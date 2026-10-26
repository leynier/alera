part of 'agent_chat_tab_view.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AgentChatTabDrafts on _AgentChatTabViewState {
  void _persistDraft() {
    if (_restoring) return;
    typing.keystroke();
    _store.write(
      widget.hostId,
      widget.chatId,
      _keptDraft,
      workspaceId: widget.workspaceId,
    );
  }

  /// The chat's draft: while a queued message is edited, the one set aside
  /// plus any files added since.
  AgentChatComposerDraft get _keptDraft => switch (queuedEdit.held) {
    final held? => AgentChatComposerDraft(
      value: held.value,
      attachments: <AgentChatDraftAttachment>[
        ...held.attachments,
        ..._attachments,
      ],
    ),
    null => AgentChatComposerDraft(
      value: _composer.value,
      attachments: _attachments,
    ),
  };

  void _showDraft(AgentChatComposerDraft draft) {
    _restoring = true;
    _composer.value = draft.value;
    _restoring = false;
    setState(() => _attachments = draft.attachments);
    _store.write(
      widget.hostId,
      widget.chatId,
      _keptDraft,
      workspaceId: widget.workspaceId,
    );
  }

  void _beginQueuedEdit(AgentChatQueueEntry entry) {
    if (queuedEdit.saving) return;
    queuedEdit.begin(entry, _keptDraft);
    _showDraft(
      AgentChatComposerDraft(
        value: TextEditingValue(
          text: entry.text,
          selection: TextSelection.collapsed(offset: entry.text.length),
        ),
      ),
    );
    _focus.requestFocus();
  }

  void _endQueuedEdit() {
    final kept = _keptDraft;
    queuedEdit.end();
    _showDraft(kept);
  }

  Future<void> _saveQueuedEdit() async {
    final entry = queuedEdit.entry!;
    final text = _composer.text.trim();
    if (queuedEdit.saving || (text.isEmpty && entry.attachments.isEmpty)) {
      return;
    }
    queuedEdit.saving = true;
    try {
      final edited = await ref.read(_provider.notifier).editQueued(entry, text);
      if (!mounted) return;
      if (!edited) {
        _notify('This message already left the queue.');
      } else if (queuedEdit.queueId == entry.queueId) {
        queuedEdit.saving = false;
        _endQueuedEdit();
      }
    } on Object catch (error, stackTrace) {
      _report('Could not save the queued message.', error, stackTrace);
    } finally {
      queuedEdit.saving = false;
    }
  }

  /// The edited message ran, was steered or was removed elsewhere. A changed
  /// edit becomes the draft when the person had none; otherwise theirs wins.
  void _reconcileQueuedEdit(List<AgentChatQueueEntry> queue) {
    final entry = queuedEdit.entry;
    if (entry == null ||
        queuedEdit.saving ||
        queue.any((queued) => queued.queueId == entry.queueId)) {
      return;
    }
    final changed = _composer.text != entry.text;
    if (changed && (queuedEdit.held?.isEmpty ?? true)) {
      queuedEdit.end();
      _persistDraft();
      _notify('The message left the queue; your edit is now the draft.');
      return;
    }
    _endQueuedEdit();
    if (changed) {
      _notify('The message left the queue before your edit was saved.');
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));

  /// An upload finished or a refused prompt came back while this was shown.
  void _restoreStoredDraft() {
    if (!mounted) return;
    queuedEdit.end();
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
    if (queuedEdit.isEditing) return _saveQueuedEdit();
    final draft = AgentChatComposerDraft(
      value: _composer.value,
      attachments: _attachments,
    );
    if (!draft.canSubmit || _takeFeedback(draft)) return;
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
