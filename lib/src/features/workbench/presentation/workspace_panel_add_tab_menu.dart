part of 'workspace_panel_view.dart';

sealed class _WorkspaceAddTabMenuAction {
  const _WorkspaceAddTabMenuAction();
}

class const _WorkspaceAddToolMenuAction(final String key)
    extends _WorkspaceAddTabMenuAction {}

class const _WorkspaceAddAgentChatMenuAction()
    extends _WorkspaceAddTabMenuAction {}

class const _WorkspaceArchivedChatsMenuAction()
    extends _WorkspaceAddTabMenuAction {}

class const _WorkspaceAddTerminalMenuAction()
    extends _WorkspaceAddTabMenuAction {}

class const _WorkspaceAddAgentProfileMenuAction(final String profileId)
    extends _WorkspaceAddTabMenuAction {}

class const _WorkspacePanelAddButton({
  required final List<WorkspaceTool> availableTools,
  required final List<AgentProfile> profiles,
  required final ValueChanged<String> onSelect,
  required final VoidCallback onNewTerminal,
  required final ValueChanged<String>? onLaunchAgentProfile,
  final VoidCallback? onNewAgentChat,
  final VoidCallback? onOpenArchivedChats,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_WorkspaceAddTabMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_WorkspaceAddTabMenuAction>>[
        for (final tool in availableTools)
          AleraDropdownEntry(
            value: _WorkspaceAddToolMenuAction(tool.key),
            label: tool.label,
            leading: Icon(
              _iconForTool(tool),
              size: AleraTokens.iconLg,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        const AleraDropdownEntry(
          value: _WorkspaceAddTerminalMenuAction(),
          label: 'Terminal',
          leading: Icon(
            AleraIcons.terminal,
            size: AleraTokens.iconLg,
            color: AleraTokens.foregroundMuted,
          ),
        ),
        if (onNewAgentChat != null)
          const AleraDropdownEntry(
            value: _WorkspaceAddAgentChatMenuAction(),
            label: 'Agent Chat',
            leading: Icon(
              AleraIcons.agent,
              size: AleraTokens.iconLg,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        if (onOpenArchivedChats != null)
          const AleraDropdownEntry(
            value: _WorkspaceArchivedChatsMenuAction(),
            label: 'Archived Chats',
            leading: Icon(
              AleraIcons.archive,
              size: AleraTokens.iconLg,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        for (final profile in profiles)
          if (profile.showInNewTabMenu)
            AleraDropdownEntry(
              value: _WorkspaceAddAgentProfileMenuAction(profile.id),
              label: profile.name,
              leading: AgentIdentityIcon(
                agentType:
                    AgentType.tryParse(profile.agentType) ?? AgentType.codex,
                size: AleraTokens.iconLg,
                showTooltip: false,
              ),
            ),
      ],
    );
    if (selected == null) {
      return;
    }
    switch (selected) {
      case _WorkspaceAddToolMenuAction(:final key):
        onSelect(key);
      case _WorkspaceAddTerminalMenuAction():
        onNewTerminal();
      case _WorkspaceAddAgentChatMenuAction():
        onNewAgentChat?.call();
      case _WorkspaceArchivedChatsMenuAction():
        onOpenArchivedChats?.call();
      case _WorkspaceAddAgentProfileMenuAction(:final profileId):
        onLaunchAgentProfile?.call(profileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'Add Tab',
      icon: AleraIcons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: () => unawaited(_openMenu(context)),
    );
  }
}
