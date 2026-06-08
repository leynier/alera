part of 'workspace_workbench_view.dart';

class _WorkspaceTabStrip extends StatefulWidget {
  const _WorkspaceTabStrip({
    required this.workspace,
    required this.groupId,
    required this.tabs,
    required this.activeTabId,
    required this.canCloseSplit,
    required this.terminalRuntime,
    required this.agentStatuses,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseTabs,
    required this.onRenameTab,
    required this.onCreateTab,
    required this.onSplitGroup,
    required this.onMergeGroup,
  });

  final Workspace workspace;
  final String groupId;
  final List<WorkspaceTabRecord> tabs;
  final String? activeTabId;
  final bool canCloseSplit;
  final TerminalRuntime terminalRuntime;
  final Map<String, AgentStatusEntry> agentStatuses;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<List<String>> onCloseTabs;
  final RenameWorkspaceTabCallback onRenameTab;
  final VoidCallback onCreateTab;
  final ValueChanged<WorkbenchDropZone> onSplitGroup;
  final VoidCallback onMergeGroup;

  @override
  State<_WorkspaceTabStrip> createState() => _WorkspaceTabStripState();
}

class _WorkspaceTabStripState extends State<_WorkspaceTabStrip> {
  final ScrollController _scrollController = ScrollController();
  bool _hasOverflow = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final overflow = _scrollController.position.maxScrollExtent > 0.5;
    if (overflow != _hasOverflow) {
      setState(() => _hasOverflow = overflow);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    final addButton = _NewTerminalButton(onPressed: widget.onCreateTab);
    return ColoredBox(
      color: AleraTokens.surface,
      child: SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Row(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                  vertical: AleraTokens.space6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final tab in widget.tabs)
                      _DraggableWorkspaceTabChip(
                        workspace: widget.workspace,
                        groupId: widget.groupId,
                        tab: tab,
                        active: tab.id == widget.activeTabId,
                        terminalRuntime: widget.terminalRuntime,
                        status: widget.agentStatuses[tab.terminalSessionId],
                        groupTabs: widget.tabs,
                        onSelect: () => widget.onSelectTab(tab.id),
                        onClose: () => widget.onCloseTab(tab.id),
                        onCloseTabs: widget.onCloseTabs,
                        onRename: (title) =>
                            widget.onRenameTab(tabId: tab.id, title: title),
                        onSplit: widget.onSplitGroup,
                      ),
                    if (!_hasOverflow) addButton,
                  ],
                ),
              ),
            ),
            if (_hasOverflow)
              Padding(
                padding: const EdgeInsets.only(right: AleraTokens.space8),
                child: addButton,
              ),
            _PaneMenuButton(
              canCloseSplit: widget.canCloseSplit,
              onSplitGroup: widget.onSplitGroup,
              onMergeGroup: widget.onMergeGroup,
            ),
            const SizedBox(width: AleraTokens.space4),
          ],
        ),
      ),
    );
  }
}

class _PaneMenuButton extends StatelessWidget {
  const _PaneMenuButton({
    required this.canCloseSplit,
    required this.onSplitGroup,
    required this.onMergeGroup,
  });

  final bool canCloseSplit;
  final ValueChanged<WorkbenchDropZone> onSplitGroup;
  final VoidCallback onMergeGroup;

  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_PaneMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_PaneMenuAction>>[
        const AleraDropdownEntry<_PaneMenuAction>(
          value: _PaneMenuAction.splitRight,
          label: 'Split right',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.right),
        ),
        const AleraDropdownEntry<_PaneMenuAction>(
          value: _PaneMenuAction.splitDown,
          label: 'Split down',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.down),
        ),
        const AleraDropdownEntry<_PaneMenuAction>(
          value: _PaneMenuAction.splitLeft,
          label: 'Split left',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.left),
        ),
        const AleraDropdownEntry<_PaneMenuAction>(
          value: _PaneMenuAction.splitUp,
          label: 'Split up',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.up),
        ),
        if (canCloseSplit) const PopupMenuDivider(height: AleraTokens.space8),
        if (canCloseSplit)
          const AleraDropdownEntry<_PaneMenuAction>(
            value: _PaneMenuAction.closeSplit,
            label: 'Close split',
          ),
      ],
    );

    if (selected == null) {
      return;
    }

    switch (selected) {
      case _PaneMenuAction.splitRight:
        onSplitGroup(WorkbenchDropZone.right);
      case _PaneMenuAction.splitDown:
        onSplitGroup(WorkbenchDropZone.down);
      case _PaneMenuAction.splitLeft:
        onSplitGroup(WorkbenchDropZone.left);
      case _PaneMenuAction.splitUp:
        onSplitGroup(WorkbenchDropZone.up);
      case _PaneMenuAction.closeSplit:
        onMergeGroup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'Pane actions',
      onPressed: () => unawaited(_openMenu(context)),
      icon: AleraIcons.more,
      minSize: 28,
    );
  }
}

class _SplitDirectionGlyph extends StatelessWidget {
  const _SplitDirectionGlyph({required this.zone});

  final WorkbenchDropZone zone;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(14),
      painter: _SplitDirectionPainter(zone: zone),
    );
  }
}

class _SplitDirectionPainter extends CustomPainter {
  const _SplitDirectionPainter({required this.zone});

  final WorkbenchDropZone zone;

  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const Radius.circular(AleraTokens.radiusSm),
    );

    final fillRect = splitDirectionFillRectForTesting(zone, size);

    if (!fillRect.isEmpty) {
      canvas
        ..save()
        ..clipRRect(outerRRect)
        ..drawRect(fillRect, Paint()..color = AleraTokens.foreground)
        ..restore();
    }

    canvas.drawRRect(
      outerRRect,
      Paint()
        ..color = AleraTokens.foregroundMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SplitDirectionPainter oldDelegate) {
    return splitDirectionShouldRepaintForTesting(oldDelegate.zone, zone);
  }
}

class _NewTerminalButton extends StatelessWidget {
  const _NewTerminalButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'New terminal',
      icon: AleraIcons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: onPressed,
    );
  }
}
