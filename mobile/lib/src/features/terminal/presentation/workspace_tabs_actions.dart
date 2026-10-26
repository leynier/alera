part of 'workspace_tabs_screen.dart';

extension _WorkspaceTabsActions on _WorkspaceTabsScreenState {
  Future<void> _renameTab(WorkspaceTabSummary tab) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AleraRenameDialog(
        title: 'Rename Tab',
        labelText: 'Tab Title',
        initialValue: tab.displayTitle,
      ),
    );
    if (title == null || !mounted) return;
    try {
      final chatId = tab.agentChatId;
      if (tab.isAgentChat && chatId != null) {
        final actions = await ref.read(
          agentChatTabActionsProvider(widget.hostId).future,
        );
        await actions.rename(
          workspaceId: tab.workspaceId,
          chatId: chatId,
          title: title,
        );
        return;
      }
      await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .renameTab(tab, title);
    } on Object catch (error, stackTrace) {
      _WorkspaceTabsScreenState._logger.warning(
        'Could not rename workspace tab.',
        error,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(actionFailureMessage('rename tab', error))),
        );
      }
    }
  }

  Future<void> _showTabActions(
    WorkspaceTabSummary tab, {
    required bool canRename,
    required bool canGenerateTitle,
  }) async {
    final generating = tab.payload['agentTitleStatus'] == 'generating';
    final run = RunTabIdentity.fromPayload(tab.payload);
    final chatId = tab.agentChatId;
    final chatTasks =
        tab.isAgentChat &&
        chatId != null &&
        (ref.read(mobileChatTasksSupportedProvider(widget.hostId)).value ??
            false);
    final approvalHistory =
        tab.isAgentChat &&
        chatId != null &&
        (ref
                .read(
                  agentChatCapabilityProvider(
                    widget.hostId,
                    AgentChatWire.approvalHistoryCapability,
                  ),
                )
                .value ??
            false);
    final action = await showAleraActionSheet<_TabAction>(
      context,
      entries: <AleraActionSheetEntry<_TabAction>>[
        if (run != null)
          const AleraActionSheetEntry<_TabAction>(
            value: .viewRun,
            label: 'View Run',
            leading: Icon(AleraIcons.workspaceChildren),
          ),
        if (canRename || tab.isAgentChat)
          const AleraActionSheetEntry<_TabAction>(
            value: .rename,
            label: 'Rename Tab',
            leading: Icon(AleraIcons.edit),
          ),
        if (canGenerateTitle && tab.isTerminal)
          AleraActionSheetEntry<_TabAction>(
            value: .generateTitle,
            label: generating
                ? 'Generating title…'
                : tab.payload['agentTitleSource'] == 'generated'
                ? 'Regenerate Title'
                : 'Generate Title',
            leading: const Icon(AleraIcons.generate),
            enabled: !generating,
          ),
        if (approvalHistory)
          const AleraActionSheetEntry<_TabAction>(
            value: .approvalHistory,
            label: 'Approval History',
            leading: Icon(AleraIcons.restore),
          ),
        if (tab.isAgentChat && chatId != null)
          const AleraActionSheetEntry<_TabAction>(
            value: .lineage,
            label: 'Lineage',
            leading: Icon(AleraIcons.gitFork),
          ),
        if (chatTasks) ...const <AleraActionSheetEntry<_TabAction>>[
          AleraActionSheetEntry<_TabAction>(
            value: .delegateTask,
            label: 'Delegate Task',
            leading: Icon(AleraIcons.workspaceChildren),
          ),
          AleraActionSheetEntry<_TabAction>(
            value: .sendToChat,
            label: 'Send To Chat',
            leading: Icon(AleraIcons.send),
          ),
        ],
        if (tab.isTerminal || tab.isAgentChat)
          const AleraActionSheetEntry<_TabAction>(
            value: .close,
            label: 'Close Tab',
            leading: Icon(AleraIcons.close),
          ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _TabAction.viewRun:
        if (run != null) {
          await openRun(context, widget.hostId, run.runId);
        }
      case _TabAction.generateTitle:
        await _generateTitle(tab);
      case _TabAction.rename:
        await _renameTab(tab);
      case _TabAction.close:
        await _closeTab(tab);
      // Both push their own form and never select another workspace or chat.
      case _TabAction.delegateTask when chatId != null:
        await showDelegateChatTaskFromChat(
          context,
          hostId: widget.hostId,
          chatId: chatId,
          workspaceId: tab.workspaceId,
        );
      case _TabAction.sendToChat when chatId != null:
        await showSendToChatSheet(
          context,
          hostId: widget.hostId,
          fromChatId: chatId,
          workspaceId: tab.workspaceId,
        );
      case _TabAction.lineage when chatId != null:
        await showAgentChatLineageSheet(
          context,
          AgentChatSubagentChat(
            hostId: widget.hostId,
            workspaceId: tab.workspaceId,
            chatId: chatId,
          ),
        );
      case _TabAction.approvalHistory when chatId != null:
        await showAgentChatApprovalHistorySheet(
          context,
          load: () async =>
              (await ref.read(
                agentChatRepositoryProvider(widget.hostId).future,
              )).lifecycle.approvalHistory(
                AgentChatRef(chatId: chatId, workspaceId: tab.workspaceId),
              ),
        );
      case _TabAction.delegateTask ||
          _TabAction.sendToChat ||
          _TabAction.lineage ||
          _TabAction.approvalHistory:
        break;
      case null:
        break;
    }
  }

  Future<void> _generateTitle(WorkspaceTabSummary tab) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(
            tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
          )
          .generateTitle(tab);
    } on Object catch (error, stackTrace) {
      _WorkspaceTabsScreenState._logger.warning(
        'Could not generate agent title.',
        error,
        stackTrace,
      );
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(actionFailureMessage('generate title', error)),
          ),
        );
      }
    }
  }
}

enum _TabAction {
  viewRun,
  rename,
  generateTitle,
  approvalHistory,
  lineage,
  delegateTask,
  sendToChat,
  close,
}
