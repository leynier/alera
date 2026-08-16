part of 'workspace_tabs_screen.dart';

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selectedTabId,
    required this.creating,
    required this.presenceByTabId,
    required this.onSelect,
    required this.onClose,
    required this.onActions,
    required this.onNewTab,
  });

  final List<WorkspaceTabSummary> tabs;
  final String? selectedTabId;
  final bool creating;
  final Map<String, AgentPresenceSummary> presenceByTabId;
  final ValueChanged<WorkspaceTabSummary> onSelect;
  final ValueChanged<WorkspaceTabSummary> onClose;
  final ValueChanged<WorkspaceTabSummary> onActions;
  final ValueChanged<_NewTabAction> onNewTab;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.tabStripHeight,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(
                left: AleraTokens.spaceSm,
                top: AleraTokens.spaceXs,
                bottom: AleraTokens.spaceXs,
              ),
              children: <Widget>[
                for (final tab in tabs) ...<Widget>[
                  _TabChip(
                    tab: tab,
                    selected: tab.id == selectedTabId,
                    presence: presenceByTabId[tab.id],
                    onSelect: onSelect,
                    onClose: onClose,
                    onActions: onActions,
                  ),
                  const SizedBox(width: AleraTokens.spaceSm),
                ],
              ],
            ),
          ),
          // Outside the scroll view: creating a tab must not depend on how far
          // the strip happens to be scrolled.
          // No right inset: the button's tap target reaches the edge, like the
          // overflow menu directly above it.
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.spaceSm),
            child: _NewTabButton(creating: creating, onSelected: onNewTab),
          ),
        ],
      ),
    );
  }
}

/// The single "+" for every kind of new tab. The menu is anchored under the
/// button rather than shown as a bottom sheet: the button lives at the top of
/// the screen, and a sheet would move the action half a screen away from it.
class _NewTabButton extends StatelessWidget {
  const _NewTabButton({required this.creating, required this.onSelected});

  final bool creating;
  final ValueChanged<_NewTabAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NewTabAction>(
      tooltip: 'New Tab',
      enabled: !creating,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<_NewTabAction>>[
        const PopupMenuItem<_NewTabAction>(
          value: _NewTabAction.terminal,
          height: AleraTokens.minTapTarget,
          child: _NewTabMenuRow(
            leading: Icon(Icons.terminal, size: AleraTokens.space20),
            label: 'New Terminal',
          ),
        ),
        const PopupMenuItem<_NewTabAction>(
          value: _NewTabAction.codex,
          height: AleraTokens.minTapTarget,
          child: _NewTabMenuRow(
            leading: AgentIdentityIcon(
              agentType: 'codex',
              size: AleraTokens.space20,
              color: AleraTokens.foreground,
              showTooltip: false,
            ),
            label: 'New Codex Chat',
          ),
        ),
      ],
      child: SizedBox.square(
        dimension: AleraTokens.minTapTarget,
        child: creating
            ? const Center(
                child: SizedBox.square(
                  dimension: AleraTokens.spaceLg,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                  ),
                ),
              )
            : const Icon(Icons.add),
      ),
    );
  }
}

class _NewTabMenuRow extends StatelessWidget {
  const _NewTabMenuRow({required this.leading, required this.label});

  final Widget leading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        leading,
        const SizedBox(width: AleraTokens.spaceMd),
        Text(label),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.selected,
    required this.presence,
    required this.onSelect,
    required this.onClose,
    required this.onActions,
  });

  final WorkspaceTabSummary tab;
  final bool selected;
  final AgentPresenceSummary? presence;
  final ValueChanged<WorkspaceTabSummary> onSelect;
  final ValueChanged<WorkspaceTabSummary> onClose;
  final ValueChanged<WorkspaceTabSummary> onActions;

  @override
  Widget build(BuildContext context) {
    final interactive = tab.isTerminal || tab.isCodex;
    final status = presence;
    return GestureDetector(
      onLongPress: () => onActions(tab),
      child: InputChip(
        // The fill already says which tab is active; a checkmark on top of it
        // spends width that the title needs on a phone.
        showCheckmark: false,
        avatar: status != null
            ? AgentRunStateIndicator(status: status)
            : tab.isCodex
            ? const AgentIdentityIcon(
                agentType: 'codex',
                size: AleraTokens.space16,
                color: AleraTokens.foreground,
                showTooltip: false,
              )
            : null,
        label: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _tabTitleMaxWidth(tab.kind)),
          child: Text(
            tab.displayTitle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        selected: selected,
        // Non-terminal tabs remain disabled content surfaces, while
        // their metadata actions stay available through long press.
        onSelected: interactive ? (_) => onSelect(tab) : null,
        // Only the open tab offers Close: on an unselected chip the target sits
        // next to the one that selects it, and the two are a thumb-width apart.
        onDeleted: interactive && selected ? () => onClose(tab) : null,
        deleteButtonTooltipMessage: 'Close Tab',
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
    required this.onNewTab,
    this.targetUnavailable = false,
  });

  final bool creating;
  final VoidCallback onNewTab;
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
              onPressed: creating ? null : onNewTab,
              icon: const Icon(Icons.add),
              label: const Text('New Tab'),
            ),
          ],
        ),
      ),
    );
  }
}
