part of 'workspace_tabs_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _WorkspaceTabsClose on _WorkspaceTabsScreenState {
  Future<void> _closeTab(WorkspaceTabSummary tab) async {
    if (!mounted) return;
    final chat = tab.isAgentChat;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chat ? 'Close Chat' : 'Close Tab'),
        content: Text(
          chat
              ? 'The agent stops and the chat is archived on the host. Its '
                    'history is kept.'
              : tab.displayTitle,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final tabsController = ref.read(
      tabsControllerProvider(widget.hostId, widget.workspace.id).notifier,
    );
    try {
      final chatId = tab.agentChatId;
      final bool closed;
      if (chat && chatId != null) {
        final actions = await ref.read(
          agentChatTabActionsProvider(widget.hostId).future,
        );
        await actions.close(workspaceId: tab.workspaceId, chatId: chatId);
        closed = true;
        if (mounted) {
          ref.invalidate(
            tabsControllerProvider(widget.hostId, widget.workspace.id),
          );
        }
      } else {
        closed = await tabsController.closeTab(tab);
      }
      if (!closed) return;
      if (mounted && _selectedTabId == tab.id) {
        setState(() {
          _selectedTabId = null;
        });
      }
    } on Object catch (error, stackTrace) {
      _WorkspaceTabsScreenState._logger.warning(
        'Could not close workspace tab.',
        error,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not close tab: $error')));
      }
    }
  }
}
