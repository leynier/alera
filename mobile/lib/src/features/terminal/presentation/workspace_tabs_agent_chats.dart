part of 'workspace_tabs_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Agent chats on the tab strip. New Chat opens a chat at once with the
/// resolved default agent; the agent and model change from its composer.
extension _WorkspaceTabsAgentChats on _WorkspaceTabsScreenState {
  String? get _remoteHostId =>
      widget.workspace.isOnRemoteHost ? widget.workspace.hostId : null;

  /// Keeps the catalog and preferences warm while chats are offered, so New
  /// Chat resolves its default without waiting on a round trip.
  void _preloadAgentChatDefaults() {
    ref
      ..listen(
        agentChatProvidersProvider(widget.hostId, widget.workspace.id),
        (_, _) {},
      )
      ..listen(
        agentChatPreferencesProvider(widget.hostId, _remoteHostId),
        (_, _) {},
      )
      ..listen(mobileChatTasksSupportedProvider(widget.hostId), (_, _) {})
      ..listen(
        agentChatCapabilityProvider(
          widget.hostId,
          AgentChatWire.approvalHistoryCapability,
        ),
        (_, _) {},
      )
      ..listen(
        agentChatCapabilityProvider(
          widget.hostId,
          AgentChatWire.unselectedDraftCapability,
        ),
        (_, _) {},
      );
  }

  /// The chat the person is looking at, when New Chat starts from one, so
  /// the new chat can start with the same agent.
  AgentChatSelection? _launchingSelection() {
    final tabs = ref
        .read(tabsControllerProvider(widget.hostId, widget.workspace.id))
        .value;
    final tab = tabs == null ? null : _selectedTab(tabs);
    final chatId = tab?.agentChatId;
    if (tab == null || !tab.isAgentChat || chatId == null) return null;
    return ref
        .read(
          agentChatControllerProvider(widget.hostId, tab.workspaceId, chatId),
        )
        .value
        ?.selection;
  }

  /// The person asked for a chat, so its tab opens and its composer takes
  /// focus. [text] seeds the draft, for a chat removed elsewhere whose unsent
  /// text this phone kept.
  Future<void> _createAgentChat({String? text}) async {
    if (_creating) return;
    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final launcher = await agentChatLauncherFor(
        ref.read,
        hostId: widget.hostId,
        workspaceId: widget.workspace.id,
        remoteHostId: _remoteHostId,
      );
      final outcome = await launcher.open(
        workspaceId: widget.workspace.id,
        projectId: widget.workspace.projectId,
        launchingSelection: _launchingSelection(),
        launchingWorkspaceId: widget.workspace.id,
      );
      switch (outcome) {
        case AgentChatLaunchOpened(:final chatId, :final tabId):
          if (text != null && text.isNotEmpty) {
            ref
                .read(agentChatDraftStoreProvider)
                .restore(
                  widget.hostId,
                  chatId,
                  AgentChatComposerDraft.fromMessage(
                    text,
                    const <AgentChatAttachment>[],
                  ),
                  workspaceId: widget.workspace.id,
                );
          }
          if (!mounted || tabId == null) return;
          ref.invalidate(
            tabsControllerProvider(widget.hostId, widget.workspace.id),
          );
          setState(() {
            _selectedTabId = tabId;
            _focusTabId = tabId;
          });
        case AgentChatLaunchNoAgent():
          messenger.showSnackBar(
            SnackBar(
              content: const Text(agentChatNoAgentLabel),
              action: SnackBarAction(
                label: agentChatOpenProviderSettingsLabel,
                onPressed: _openProviderSettings,
              ),
            ),
          );
      }
    } on Object catch (error, stackTrace) {
      _WorkspaceTabsScreenState._logger.warning(
        'Could not start a chat.',
        error,
        stackTrace,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(agentChatErrorMessage(error)),
          action: SnackBarAction(
            label: agentChatTryAgainLabel,
            onPressed: () => unawaited(_createAgentChat(text: text)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openArchivedChats() async {
    final tabId = await showAgentChatArchivedChatsSheet(
      context,
      hostId: widget.hostId,
      workspaceId: widget.workspace.id,
    );
    if (tabId == null || !mounted) return;
    ref.invalidate(tabsControllerProvider(widget.hostId, widget.workspace.id));
    setState(() => _selectedTabId = tabId);
  }

  void _openProviderSettings() {
    if (!mounted) return;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AgentProvidersScreen(
            hostId: widget.hostId,
            initialRemoteHostId: _remoteHostId,
          ),
        ),
      ),
    );
  }

  /// A chat that left the tab list while this phone still held unsent text
  /// for it was closed or discarded on another device. The text is offered
  /// back; the person stays where they are.
  void _watchRemovedChats(
    List<WorkspaceTabSummary>? previous,
    List<WorkspaceTabSummary>? next,
  ) {
    if (previous == null || next == null) return;
    final remaining = <String>{for (final tab in next) ?tab.agentChatId};
    final drafts = ref.read(agentChatDraftStoreProvider);
    for (final tab in previous) {
      final chatId = tab.agentChatId;
      if (chatId == null || remaining.contains(chatId)) continue;
      final text = drafts
          .read(widget.hostId, chatId, workspaceId: tab.workspaceId)
          .value
          .text;
      if (text.trim().isEmpty) continue;
      _offerRemovedDraft(text);
    }
  }

  void _offerRemovedDraft(String text) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'A chat was closed on another device before your text was sent.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              messenger.hideCurrentMaterialBanner();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(_createAgentChat(text: text));
            },
            child: const Text('Start New Chat With This Text'),
          ),
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  /// A never-sent chat with nothing typed closes without a question: the
  /// host discards it, so there is nothing to keep.
  Future<bool> _confirmChatClose(WorkspaceTabSummary tab) async {
    final chatId = tab.agentChatId;
    final view = chatId == null
        ? null
        : ref
              .read(
                agentChatControllerProvider(
                  widget.hostId,
                  tab.workspaceId,
                  chatId,
                ),
              )
              .value;
    final draft = chatId == null
        ? ''
        : ref
              .read(agentChatDraftStoreProvider)
              .read(widget.hostId, chatId, workspaceId: tab.workspaceId)
              .value
              .text;
    final neverSent = view?.neverSent ?? false;
    if (neverSent && draft.trim().isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AleraConfirmDialog(
        title: neverSent ? 'Discard Chat?' : 'Close Chat',
        message: neverSent
            ? 'Nothing was sent in this chat, so it is discarded along with '
                  'your unsent text.'
            : 'The agent stops and the chat is archived on the host. Its '
                  'history is kept.',
        confirmLabel: neverSent ? 'Discard' : 'Close',
        destructive: neverSent,
      ),
    );
    return confirmed == true;
  }
}
