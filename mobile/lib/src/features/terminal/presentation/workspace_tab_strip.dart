part of 'workspace_tabs_screen.dart';

class const _TabStrip({
  required final List<WorkspaceTabSummary> tabs,
  required final String? selectedTabId,
  required final bool creating,
  required final Map<String, AgentPresenceSummary> presenceByTabId,
  required final ValueChanged<WorkspaceTabSummary> onSelect,
  required final ValueChanged<WorkspaceTabSummary> onClose,
  required final ValueChanged<WorkspaceTabSummary> onActions,
  required final ValueChanged<_NewTabAction> onNewTab,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.tabStripHeight,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              scrollDirection: .horizontal,
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
class const _NewTabButton({
  required final bool creating,
  required final ValueChanged<_NewTabAction> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NewTabAction>(
      tooltip: 'New Tab',
      enabled: !creating,
      position: .under,
      onSelected: onSelected,
      itemBuilder: (context) => <PopupMenuEntry<_NewTabAction>>[
        const PopupMenuItem<_NewTabAction>(
          value: .terminal,
          height: AleraTokens.minTapTarget,
          child: _NewTabMenuRow(
            leading: Icon(Icons.terminal, size: AleraTokens.space20),
            label: 'New Terminal',
          ),
        ),
        const PopupMenuItem<_NewTabAction>(
          value: .codex,
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

class const _NewTabMenuRow({
  required final Widget leading,
  required final String label,
}) extends StatelessWidget {
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

class const _TabChip({
  required final WorkspaceTabSummary tab,
  required final bool selected,
  required final AgentPresenceSummary? presence,
  required final ValueChanged<WorkspaceTabSummary> onSelect,
  required final ValueChanged<WorkspaceTabSummary> onClose,
  required final ValueChanged<WorkspaceTabSummary> onActions,
}) extends StatelessWidget {
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
          child: Row(
            mainAxisSize: .min,
            children: [
              Flexible(
                child: Text(
                  tab.displayTitle,
                  maxLines: 1,
                  softWrap: false,
                  overflow: .ellipsis,
                ),
              ),
              if (tab.payload['agentTitleStatus'] == 'generating') ...[
                const SizedBox(width: AleraTokens.space4),
                const Tooltip(
                  message: 'Generating title...',
                  child: Icon(
                    Icons.hourglass_top,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ],
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

class const _EmptyTabs({
  required final bool creating,
  required final VoidCallback onNewTab,
  final bool targetUnavailable = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: .min,
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
