part of 'workspace_panel_view.dart';

class const _WorkspacePanelEmpty({
  required final ValueChanged<String> onSelect,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
  final String workspaceId = WorkspacePanel.fallbackLayoutWorkspaceId,
  final List<AgentProfile> newTabMenuProfiles = const <AgentProfile>[],
  final void Function({required String profileId, String? targetGroupId})?
  onLaunchAgentProfile,
}) extends StatelessWidget {
  Future<void> _openAgentPicker(BuildContext context) async {
    final launch = onLaunchAgentProfile;
    if (launch == null) {
      return;
    }
    final selection = await showAgentTaskDispatchPicker(
      context,
      request: AgentTaskDispatchRequest(
        workspaceId: workspaceId,
        prompt: '',
        title: 'Agents',
        message: 'Choose an agent profile to start in this panel.',
      ),
      catalog: AgentTaskDispatchCatalog(profiles: newTabMenuProfiles),
      includeRunningAgents: false,
      emptyMessage: 'Add an agent profile in Settings, then start it here.',
    );
    if (!context.mounted || selection is! AgentTaskDispatchNewTabSelection) {
      return;
    }
    launch(profileId: selection.profileId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        SizedBox(
          height: AleraTokens.sidebarHeaderHeight,
          child: Row(
            children: <Widget>[
              const Spacer(),
              AleraIconButton(
                tooltip: 'Hide Panel',
                icon: AleraIcons.chevronsRight,
                onPressed: onHide,
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: AleraEmptyState(
                    // Narrow side panel: the default inset wraps every
                    // choice's description onto a second line.
                    padding: const EdgeInsets.all(AleraTokens.space12),
                    icon: AleraIcons.tabUnselected,
                    title: 'Panel is empty',
                    message: 'Open a tool or start a terminal in this panel.',
                    action: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AleraTokens.emptyStateActionMaxWidth,
                      ),
                      child: Column(
                        mainAxisSize: .min,
                        spacing: AleraTokens.space8,
                        children: <Widget>[
                          for (final tool in WorkspaceTool.values)
                            _WorkspacePanelEmptyChoice(
                              icon: _iconForTool(tool),
                              label: tool.label,
                              description: _descriptionForTool(tool),
                              onTap: () => onSelect(tool.key),
                            ),
                          _WorkspacePanelEmptyChoice(
                            icon: AleraIcons.terminal,
                            label: 'Terminal',
                            description: 'Start a new terminal tab.',
                            onTap: onNewTerminal,
                          ),
                          if (onLaunchAgentProfile != null)
                            _WorkspacePanelEmptyChoice(
                              icon: AleraIcons.agent,
                              label: 'Agents',
                              description:
                                  'Start an agent profile in a new tab.',
                              onTap: () => unawaited(_openAgentPicker(context)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String _descriptionForTool(WorkspaceTool tool) {
  return switch (tool) {
    WorkspaceTool.explorer => 'Browse files in this workspace.',
    WorkspaceTool.search => 'Find text across the workspace.',
    WorkspaceTool.sourceControl => 'Review git changes and commits.',
    WorkspaceTool.pullRequest => 'Open and review pull requests.',
  };
}

class const _WorkspacePanelEmptyChoice({
  required final IconData icon,
  required final String label,
  required final String description,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AleraTokens.surfaceVariant,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.borderSubtle),
        ),
        child: HoverContainer(
          borderRadius: 0,
          hoverColor: AleraTokens.surfaceElevated,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space12,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: AleraTokens.iconLg,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(label, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AleraTokens.space2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
