part of 'simple_workspace_panel_view.dart';

class const _SimplePanelEmpty({
  required final ValueChanged<String> onSelect,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
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
                              in SimpleWorkspaceTool.values) ...<Widget>[
                            _SimplePanelEmptyChoice(
                              icon: _iconForTool(tool),
                              label: tool.label,
                              description: _descriptionForTool(tool),
                              onTap: () => onSelect(tool.key),
                            ),
                            const SizedBox(height: AleraTokens.space8),
                          ],
                          _SimplePanelEmptyChoice(
                            icon: AleraIcons.terminal,
                            label: 'Terminal',
                            description: 'Start a new terminal tab.',
                            onTap: onNewTerminal,
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

String _descriptionForTool(SimpleWorkspaceTool tool) {
  return switch (tool) {
    SimpleWorkspaceTool.explorer => 'Browse files in this workspace.',
    SimpleWorkspaceTool.search => 'Find text across the workspace.',
    SimpleWorkspaceTool.sourceControl => 'Review git changes and commits.',
    SimpleWorkspaceTool.pullRequest => 'Open and review pull requests.',
  };
}

class const _SimplePanelEmptyChoice({
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
