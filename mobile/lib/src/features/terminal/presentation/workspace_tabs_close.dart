part of 'workspace_tabs_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _WorkspaceTabsClose on _WorkspaceTabsScreenState {
  Future<void> _closeTab(WorkspaceTabSummary tab) async {
    Map<String, Object?>? queue;
    MobileCodexClient? codex;
    var localPending = false;
    try {
      if (tab.isCodex) {
        final container = ProviderScope.containerOf(context, listen: false);
        final provider = mobileCodexControllerProvider(widget.hostId, tab.id);
        localPending =
            container.exists(provider) &&
            (container.read(provider).value?.queuedMessages.isNotEmpty ??
                false);
        final client = await ref.read(
          terminalClientProvider(widget.hostId).future,
        );
        if (client is MobileCodexClient) {
          codex = client as MobileCodexClient;
          final opened = await codex.codexRequest('codex.thread.snapshot', {
            'tabId': tab.id,
          });
          if (opened['queue'] is Map) {
            queue = await codex.codexRequest('codex.queue.get', {
              'tabId': tab.id,
            });
          }
        }
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not inspect queued messages: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Tab'),
        content: Text(
          (queue?['messages'] as List? ?? const []).isNotEmpty ||
                  (queue?['otherQueues'] as List? ?? const []).isNotEmpty
              ? 'Closing this tab cancels its queued messages for every connected client.'
              : localPending
              ? 'Closing this tab cancels its locally queued messages.'
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
    final draftStore = ref.read(mobileCodexComposerDraftStoreProvider);
    try {
      if ((queue?['messages'] as List? ?? const []).isNotEmpty ||
          (queue?['otherQueues'] as List? ?? const []).isNotEmpty) {
        await codex!.codexRequest('codex.queue.cancel', {
          'tabId': tab.id,
          'expectedThreadId': queue!['threadId'] == ''
              ? null
              : queue['threadId'],
          'expectedRevision': queue['revision'],
          'otherQueues': queue['otherQueues'],
        });
      }
      final closed = await tabsController.closeTab(tab);
      if (!closed) return;
      draftStore.remove(widget.hostId, tab.id);
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
