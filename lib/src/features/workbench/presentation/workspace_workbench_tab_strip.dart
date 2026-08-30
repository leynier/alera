part of 'workspace_workbench_view.dart';

class const _WorkspaceTabStrip({
  required final Workspace workspace,
  required final String groupId,
  required final List<WorkspaceTabRecord> tabs,
  required final String? activeTabId,
  required final bool canCloseSplit,
  required final TerminalRuntime terminalRuntime,
  required final Map<String, AgentStatusEntry> agentStatuses,
  required final WorkbenchTabCompletionAcknowledgements
  completionAcknowledgements,
  required final ValueChanged<String> onSelectTab,
  required final ValueChanged<String> onCloseTab,
  required final ValueChanged<List<String>> onCloseTabs,
  required final RenameWorkspaceTabCallback onRenameTab,
  required final VoidCallback onCreateTab,
  required final VoidCallback? onCreateBrowserTab,
  required final VoidCallback? onCreateCodexTab,
  required final ValueChanged<WorkbenchDropZone> onSplitGroup,
  required final VoidCallback onMergeGroup,
  required final MoveWorkspaceTabCallback onMoveTab,
}) extends StatefulWidget {
  @override
  State<_WorkspaceTabStrip> createState() => _WorkspaceTabStripState();
}

class _WorkspaceTabStripState extends State<_WorkspaceTabStrip> {
  final ScrollController _scrollController = ScrollController();
  bool _hasOverflow = false;
  int? _insertionGapIndex;
  String? _lastSelectedPreviewTabId;
  DateTime? _lastSelectedPreviewAt;

  @override
  void initState() {
    super.initState();
    _syncCompletionAcknowledgement();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCompletionAcknowledgement();
  }

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

  void _syncCompletionAcknowledgement() {
    final activeTabId = widget.activeTabId;
    if (activeTabId == null) {
      return;
    }
    WorkspaceTabRecord? activeTab;
    for (final tab in widget.tabs) {
      if (tab.id == activeTabId) {
        activeTab = tab;
        break;
      }
    }
    if (activeTab == null) {
      return;
    }
    widget.completionAcknowledgements.acknowledge(
      widget.agentStatuses[activeTab.terminalSessionId],
    );
  }

  int? _resolvedDropIndex(_WorkspaceTabDragData data, int gapIndex) {
    return resolveWorkbenchTabStripDropIndex(
      tabIds: <String>[for (final tab in widget.tabs) tab.id],
      sourceGroupId: data.sourceGroupId,
      targetGroupId: widget.groupId,
      draggedTabId: data.tabId,
      gapIndex: gapIndex,
    );
  }

  void _handleGapHover(_WorkspaceTabDragData data, int gapIndex) {
    final next = _resolvedDropIndex(data, gapIndex) == null ? null : gapIndex;
    if (next != _insertionGapIndex) {
      setState(() => _insertionGapIndex = next);
    }
  }

  void _handleGapLeave() {
    if (_insertionGapIndex != null) {
      setState(() => _insertionGapIndex = null);
    }
  }

  void _maybeKeepPreviewTab(WorkspaceTabRecord tab) {
    final onKeep = _KeepPreviewTabScope.maybeOf(context);
    if (onKeep == null || !tab.isPreview) {
      _lastSelectedPreviewTabId = null;
      _lastSelectedPreviewAt = null;
      return;
    }
    final now = DateTime.now();
    if (_lastSelectedPreviewTabId == tab.id &&
        _lastSelectedPreviewAt != null &&
        now.difference(_lastSelectedPreviewAt!) <= kDoubleTapTimeout) {
      onKeep(tab.id);
      _lastSelectedPreviewTabId = null;
      _lastSelectedPreviewAt = null;
      return;
    }
    _lastSelectedPreviewTabId = tab.id;
    _lastSelectedPreviewAt = now;
  }

  void _handleGapDrop(_WorkspaceTabDragData data, int gapIndex) {
    setState(() => _insertionGapIndex = null);
    final index = _resolvedDropIndex(data, gapIndex);
    if (index == null) {
      return;
    }
    unawaited(
      widget.onMoveTab(
        tabId: data.tabId,
        targetGroupId: widget.groupId,
        zone: .center,
        index: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    final addButton = _NewTabButton(
      groupId: widget.groupId,
      onCreateTab: widget.onCreateTab,
      onCreateBrowserTab: widget.onCreateBrowserTab,
      onCreateCodexTab: widget.onCreateCodexTab,
    );
    return ColoredBox(
      color: AleraTokens.surface,
      child: _TabStripAppendDropTarget(
        workspaceId: widget.workspace.id,
        tabCount: widget.tabs.length,
        onHoverGap: _handleGapHover,
        onLeave: _handleGapLeave,
        onDropGap: _handleGapDrop,
        child: SizedBox(
          height: AleraTokens.sidebarHeaderHeight,
          child: Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: .horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                    vertical: AleraTokens.space6,
                  ),
                  child: Row(
                    mainAxisSize: .min,
                    children: <Widget>[
                      for (final (index, tab) in widget.tabs.indexed)
                        _TabStripChipDropTarget(
                          chipIndex: index,
                          workspaceId: widget.workspace.id,
                          showLeadingIndicator:
                              index == 0 && _insertionGapIndex == 0,
                          showTrailingIndicator:
                              _insertionGapIndex == index + 1,
                          onHoverGap: _handleGapHover,
                          onLeave: _handleGapLeave,
                          onDropGap: _handleGapDrop,
                          child: _DraggableWorkspaceTabChip(
                            workspace: widget.workspace,
                            groupId: widget.groupId,
                            tab: tab,
                            active: tab.id == widget.activeTabId,
                            terminalRuntime: widget.terminalRuntime,
                            status: widget.agentStatuses[tab.terminalSessionId],
                            completionAcknowledged: widget
                                .completionAcknowledgements
                                .isAcknowledged(
                                  widget.agentStatuses[tab.terminalSessionId],
                                ),
                            groupTabs: widget.tabs,
                            onSelect: () {
                              setState(() {
                                widget.completionAcknowledgements.acknowledge(
                                  widget.agentStatuses[tab.terminalSessionId],
                                );
                              });
                              widget.onSelectTab(tab.id);
                              _maybeKeepPreviewTab(tab);
                            },
                            onClose: () => widget.onCloseTab(tab.id),
                            onCloseTabs: widget.onCloseTabs,
                            onRename: (title) =>
                                widget.onRenameTab(tabId: tab.id, title: title),
                            onSplit: widget.onSplitGroup,
                          ),
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
      ),
    );
  }
}

class const _PaneMenuButton({
  required final bool canCloseSplit,
  required final ValueChanged<WorkbenchDropZone> onSplitGroup,
  required final VoidCallback onMergeGroup,
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
    final selected = await showMenu<_PaneMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_PaneMenuAction>>[
        const AleraDropdownEntry<_PaneMenuAction>(
          value: .splitRight,
          label: 'Split Right',
          leading: _SplitDirectionGlyph(zone: .right),
        ),
        const AleraDropdownEntry<_PaneMenuAction>(
          value: .splitDown,
          label: 'Split Down',
          leading: _SplitDirectionGlyph(zone: .down),
        ),
        const AleraDropdownEntry<_PaneMenuAction>(
          value: .splitLeft,
          label: 'Split Left',
          leading: _SplitDirectionGlyph(zone: .left),
        ),
        const AleraDropdownEntry<_PaneMenuAction>(
          value: .splitUp,
          label: 'Split Up',
          leading: _SplitDirectionGlyph(zone: .up),
        ),
        if (canCloseSplit) const PopupMenuDivider(height: AleraTokens.space8),
        if (canCloseSplit)
          const AleraDropdownEntry<_PaneMenuAction>(
            value: .closeSplit,
            label: 'Close Split',
          ),
      ],
    );

    if (selected == null) {
      return;
    }

    switch (selected) {
      case _PaneMenuAction.splitRight:
        onSplitGroup(.right);
      case _PaneMenuAction.splitDown:
        onSplitGroup(.down);
      case _PaneMenuAction.splitLeft:
        onSplitGroup(.left);
      case _PaneMenuAction.splitUp:
        onSplitGroup(.up);
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

class const _SplitDirectionGlyph({required final WorkbenchDropZone zone})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const .square(14),
      painter: _SplitDirectionPainter(zone: zone),
    );
  }
}

class const _SplitDirectionPainter({required final WorkbenchDropZone zone})
    extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const .circular(AleraTokens.radiusSm),
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
