part of 'experimental_workspace_panel_view.dart';

class const _ExperimentalPanelEmpty({
  required final ValueChanged<String> onSelect,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
  final List<AgentProfile> newTabMenuProfiles = const <AgentProfile>[],
  final void Function({required String profileId, String? targetGroupId})?
  onLaunchAgentProfile,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                padding: const EdgeInsets.all(AleraTokens.space16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        mainAxisSize: .min,
                        children: <Widget>[
                          Icon(
                            AleraIcons.add,
                            size: 28,
                            color: AleraTokens.foregroundFaint,
                          ),
                          const SizedBox(height: AleraTokens.space12),
                          Text(
                            'Panel is Empty',
                            textAlign: .center,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AleraTokens.space8),
                          Text(
                            'Open a tool or start a terminal in this panel.',
                            textAlign: .center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                          const SizedBox(height: AleraTokens.space16),
                          for (final tool
                              in ExperimentalWorkspaceTool.values) ...<Widget>[
                            _ExperimentalPanelEmptyChoice(
                              icon: _iconForTool(tool),
                              label: tool.label,
                              description: _descriptionForTool(tool),
                              onTap: () => onSelect(tool.key),
                            ),
                            const SizedBox(height: AleraTokens.space8),
                          ],
                          _ExperimentalPanelEmptyChoice(
                            icon: AleraIcons.terminal,
                            label: 'Terminal',
                            description: 'Start a new terminal tab.',
                            onTap: onNewTerminal,
                          ),
                          for (final profile in newTabMenuProfiles)
                            if (profile.showInNewTabMenu) ...<Widget>[
                              const SizedBox(height: AleraTokens.space8),
                              _ExperimentalPanelEmptyChoice(
                                icon: AleraIcons.agent,
                                label: profile.name,
                                description:
                                    'Start this agent profile in a new tab.',
                                leading: AgentIdentityIcon(
                                  agentType:
                                      AgentType.tryParse(profile.agentType) ??
                                      AgentType.codex,
                                  size: 16,
                                  showTooltip: false,
                                ),
                                onTap: () => onLaunchAgentProfile?.call(
                                  profileId: profile.id,
                                ),
                              ),
                            ],
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

String _descriptionForTool(ExperimentalWorkspaceTool tool) {
  return switch (tool) {
    ExperimentalWorkspaceTool.explorer => 'Browse files in this workspace.',
    ExperimentalWorkspaceTool.search => 'Find text across the workspace.',
    ExperimentalWorkspaceTool.sourceControl =>
      'Review git changes and commits.',
    ExperimentalWorkspaceTool.pullRequest => 'Open and review pull requests.',
  };
}

class const _ExperimentalPanelEmptyChoice({
  required final IconData icon,
  required final String label,
  required final String description,
  required final VoidCallback onTap,
  final Widget? leading,
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
              leading ??
                  Icon(icon, size: 16, color: AleraTokens.foregroundMuted),
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
