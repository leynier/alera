part of 'workspace_tabs_screen.dart';

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selectedTabId,
    required this.creating,
    required this.onSelect,
    required this.onClose,
    required this.onActions,
    required this.onCreate,
    required this.onCreateCodex,
  });

  final List<WorkspaceTabSummary> tabs;
  final String? selectedTabId;
  final bool creating;
  final ValueChanged<WorkspaceTabSummary> onSelect;
  final ValueChanged<WorkspaceTabSummary> onClose;
  final ValueChanged<WorkspaceTabSummary> onActions;
  final VoidCallback onCreate;
  final VoidCallback onCreateCodex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.tabStripHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.spaceLg,
          vertical: AleraTokens.spaceSm,
        ),
        children: <Widget>[
          for (final tab in tabs) ...<Widget>[
            GestureDetector(
              onLongPress: () => onActions(tab),
              child: InputChip(
                avatar: tab.isCodex
                    ? const AgentIdentityIcon(
                        agentType: 'codex',
                        size: AleraTokens.space16,
                        color: AleraTokens.foreground,
                        showTooltip: false,
                      )
                    : null,
                label: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _tabTitleMaxWidth(tab.kind),
                  ),
                  child: Text(
                    tab.displayTitle,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                selected: tab.id == selectedTabId,
                // Non-terminal tabs remain disabled content surfaces, while
                // their metadata actions stay available through long press.
                onSelected: (tab.isTerminal || tab.isCodex)
                    ? (_) => onSelect(tab)
                    : null,
                onDeleted: (tab.isTerminal || tab.isCodex)
                    ? () => onClose(tab)
                    : null,
                deleteButtonTooltipMessage: 'Close Tab',
              ),
            ),
            const SizedBox(width: AleraTokens.spaceSm),
          ],
          IconButton.filledTonal(
            tooltip: 'New Terminal Tab',
            onPressed: creating ? null : onCreate,
            icon: creating
                ? const SizedBox.square(
                    dimension: AleraTokens.spaceLg,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                : const Icon(Icons.add),
          ),
          IconButton.filledTonal(
            tooltip: 'New Codex Chat',
            onPressed: creating ? null : onCreateCodex,
            icon: const AgentIdentityIcon(
              agentType: 'codex',
              size: AleraTokens.space20,
              color: AleraTokens.foreground,
              showTooltip: false,
            ),
          ),
        ],
      ),
    );
  }
}

double _tabTitleMaxWidth(String kind) {
  return switch (kind) {
    'editor' ||
    'markdownViewer' ||
    'pdf' ||
    'gitDiff' => AleraTokens.tabTitleMaxWidthEditor,
    'terminal' || 'browser' => AleraTokens.tabTitleMaxWidthTerminal,
    _ => AleraTokens.tabTitleMaxWidthTerminal,
  };
}

class _EmptyTabs extends StatelessWidget {
  const _EmptyTabs({
    required this.creating,
    required this.onCreate,
    this.targetUnavailable = false,
  });

  final bool creating;
  final VoidCallback onCreate;
  final bool targetUnavailable;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.terminal,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              targetUnavailable ? 'Terminal unavailable' : 'No tabs yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (targetUnavailable) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                'Choose another terminal above.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AleraTokens.spaceMd),
            FilledButton.icon(
              onPressed: creating ? null : onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Terminal'),
            ),
          ],
        ),
      ),
    );
  }
}
