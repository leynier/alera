part of 'workspace_workbench_view.dart';

sealed class _NewTabMenuAction {
  const _NewTabMenuAction();
}

class const _NewTerminalMenuAction() extends _NewTabMenuAction {}

class const _NewAgentProfileMenuAction(final String profileId)
    extends _NewTabMenuAction {}

class const _NewTabButton({
  required final String groupId,
  required final VoidCallback onCreateTab,
  required final List<AgentProfile> profiles,
  required final ValueChanged<String>? onLaunchAgentProfile,
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
    final selected = await showMenu<_NewTabMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_NewTabMenuAction>>[
        const AleraDropdownEntry<_NewTabMenuAction>(
          value: _NewTerminalMenuAction(),
          label: 'New Terminal',
          leading: Icon(
            AleraIcons.terminal,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
        ),
        for (final profile in profiles)
          if (profile.showInNewTabMenu)
            AleraDropdownEntry<_NewTabMenuAction>(
              value: _NewAgentProfileMenuAction(profile.id),
              label: profile.name,
              leading: AgentIdentityIcon(
                agentType:
                    AgentType.tryParse(profile.agentType) ?? AgentType.codex,
                size: 16,
                showTooltip: false,
              ),
            ),
      ],
    );

    if (selected == null) {
      return;
    }

    switch (selected) {
      case _NewTerminalMenuAction():
        onCreateTab();
      case _NewAgentProfileMenuAction(:final profileId):
        onLaunchAgentProfile?.call(profileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'New Tab',
      icon: AleraIcons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: () => unawaited(_openMenu(context)),
    );
  }
}
