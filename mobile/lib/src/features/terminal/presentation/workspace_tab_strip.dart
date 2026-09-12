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
  required final Future<List<AgentProfileSummary>> Function()
  loadNewTabProfiles,
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
            child: _NewTabButton(
              creating: creating,
              onSelected: onNewTab,
              loadProfiles: loadNewTabProfiles,
            ),
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
  required final Future<List<AgentProfileSummary>> Function() loadProfiles,
}) extends StatefulWidget {
  @override
  State<_NewTabButton> createState() => _NewTabButtonState();
}

class _NewTabButtonState extends State<_NewTabButton> {
  bool _openingMenu = false;

  Future<void> _openMenu() async {
    if (widget.creating || _openingMenu) {
      return;
    }
    _openingMenu = true;
    List<AgentProfileSummary> profiles = const <AgentProfileSummary>[];
    try {
      profiles = await widget.loadProfiles();
    } on Object {
      profiles = const <AgentProfileSummary>[];
    }
    if (!mounted || widget.creating) {
      _openingMenu = false;
      return;
    }
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
    final selected = await showMenu<_NewTabAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_NewTabAction>>[
        const PopupMenuItem<_NewTabAction>(
          value: _NewTerminalTabAction(),
          height: AleraTokens.minTapTarget,
          child: _NewTabMenuRow(
            leading: Icon(Icons.terminal, size: AleraTokens.space20),
            label: 'New Terminal',
          ),
        ),
        for (final profile in profiles)
          PopupMenuItem<_NewTabAction>(
            value: _NewAgentProfileTabAction(profile.id),
            height: AleraTokens.minTapTarget,
            child: _NewTabMenuRow(
              leading: Icon(Icons.smart_toy, size: AleraTokens.space20),
              label: profile.name,
            ),
          ),
      ],
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _openingMenu = false;
    });
    if (selected != null) {
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New Tab',
      child: InkWell(
        onTap: widget.creating || _openingMenu
            ? null
            : () => unawaited(_openMenu()),
        child: SizedBox.square(
          dimension: AleraTokens.minTapTarget,
          child: widget.creating
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
    final interactive = tab.isTerminal;
    final status = presence;
    return GestureDetector(
      onLongPress: () => onActions(tab),
      child: InputChip(
        // The fill already says which tab is active; a checkmark on top of it
        // spends width that the title needs on a phone.
        showCheckmark: false,
        avatar: status != null ? AgentRunStateIndicator(status: status) : null,
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
    return AleraEmptyState(
      icon: AleraIcons.terminal,
      title: targetUnavailable ? 'Terminal unavailable' : 'No terminals',
      message: targetUnavailable
          ? 'Choose another terminal above.'
          : 'Open a terminal to start working in this workspace.',
      action: targetUnavailable
          ? null
          : FilledButton.icon(
              onPressed: creating ? null : onNewTab,
              icon: const Icon(AleraIcons.add),
              label: const Text('New Terminal'),
            ),
    );
  }
}
