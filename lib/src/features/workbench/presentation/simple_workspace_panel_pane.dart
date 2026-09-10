part of 'simple_workspace_panel_view.dart';

class const _SimplePanelPane({
  required final String workspaceId,
  required final SimpleWorkspacePanel panel,
  required final List<WorkspaceTabRecord> tabs,
  required final WorkbenchLayout layout,
  required final String groupId,
  required final bool showHide,
  required final ValueChanged<String> onSelect,
  required final ValueChanged<String> onClose,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
  final Widget Function(String key)? surfaceBuilder,
  final Widget Function(WorkspaceTabRecord tab, bool active, String groupId)?
  tabBuilder,
  final void Function(String groupId, String key)? onSelectInGroup,
  final void Function(String groupId)? onNewTerminalInGroup,
  final void Function(String groupId, WorkbenchDropZone zone)? onSplitGroup,
  final void Function(String groupId)? onMergeGroup,
  final void Function({
    required String key,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  })?
  onMoveTab,
}) extends StatefulWidget {
  @override
  State<_SimplePanelPane> createState() => _SimplePanelPaneState();
}

class _SimplePanelPaneState extends State<_SimplePanelPane> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _chipsKey = GlobalKey();
  bool _hasOverflow = false;
  WorkbenchDropZone? _hoverZone;
  int? _insertionGapIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static const double _addButtonReserve = 28 + AleraTokens.space8;

  void _syncOverflow() {
    if (!mounted) {
      return;
    }
    final chipsBox = _chipsKey.currentContext?.findRenderObject() as RenderBox?;
    if (chipsBox == null || !chipsBox.hasSize) {
      return;
    }
    final viewport = _scrollController.hasClients
        ? _scrollController.position.viewportDimension
        : chipsBox.size.width;
    final innerViewport = viewport - AleraTokens.space8 * 2;
    final chipsWidth = chipsBox.size.width;
    final overflow = _hasOverflow
        ? chipsWidth + _addButtonReserve > innerViewport + 0.5
        : chipsWidth > innerViewport + 0.5;
    if (overflow != _hasOverflow) {
      setState(() => _hasOverflow = overflow);
    }
  }

  List<String> get _keys =>
      widget.layout.groups[widget.groupId]?.tabIds ?? const <String>[];

  String? get _activeKey =>
      widget.layout.groups[widget.groupId]?.activeTabId ??
      widget.panel.activeKey;

  void _selectKey(String key) {
    if (widget.onSelectInGroup != null) {
      widget.onSelectInGroup!(widget.groupId, key);
      return;
    }
    widget.onSelect(key);
  }

  int? _resolvedDropIndex(SimplePaneTabDragData data, int gapIndex) {
    return resolveWorkbenchTabStripDropIndex(
      tabIds: _keys,
      sourceGroupId: data.sourceGroupId,
      targetGroupId: widget.groupId,
      draggedTabId: data.key,
      gapIndex: gapIndex,
    );
  }

  void _handleGapHover(SimplePaneTabDragData data, int gapIndex) {
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

  void _handleGapDrop(SimplePaneTabDragData data, int gapIndex) {
    setState(() => _insertionGapIndex = null);
    final index = _resolvedDropIndex(data, gapIndex);
    if (index == null) {
      return;
    }
    widget.onMoveTab?.call(
      key: data.key,
      targetGroupId: widget.groupId,
      zone: WorkbenchDropZone.center,
      index: index,
    );
  }

  Widget _tabChip(String key, int index) {
    final tab = widget.tabs
        .where((tab) => tab.id == SimpleWorkspacePanel.tabId(key))
        .firstOrNull;
    final Widget chip;
    if (tab != null && widget.tabBuilder != null) {
      chip = widget.tabBuilder!(tab, _activeKey == key, widget.groupId);
    } else {
      final tool = SimpleWorkspaceTool.forKey(key);
      final label = tool?.label ?? tab?.title ?? 'Terminal';
      chip = Padding(
        padding: const EdgeInsets.only(right: AleraTokens.space8),
        child: _SimplePanelToolChip(
          label: label,
          icon: _iconForTool(tool),
          active: _activeKey == key,
          groupKeys: _keys,
          tabKey: key,
          onSelect: () => _selectKey(key),
          onClose: () => widget.onClose(key),
          onCloseKeys: (keys) {
            for (final item in keys) {
              widget.onClose(item);
            }
          },
          onSplit: widget.onSplitGroup == null
              ? null
              : (zone) => widget.onSplitGroup!(widget.groupId, zone),
        ),
      );
    }
    var child = chip;
    if (widget.onMoveTab != null) {
      child = Draggable<SimplePaneTabDragData>(
        data: SimplePaneTabDragData(
          workspaceId: widget.workspaceId,
          sourceGroupId: widget.groupId,
          key: key,
        ),
        feedback: Material(color: Colors.transparent, child: chip),
        child: chip,
      );
    }
    if (widget.onMoveTab == null) {
      return child;
    }
    return _SimpleStripChipDropTarget(
      chipIndex: index,
      workspaceId: widget.workspaceId,
      showLeadingIndicator: index == 0 && _insertionGapIndex == 0,
      showTrailingIndicator: _insertionGapIndex == index + 1,
      onHoverGap: _handleGapHover,
      onLeave: _handleGapLeave,
      onDropGap: _handleGapDrop,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    final openKeys = widget.panel.tabKeys.toSet();
    final addButton = _SimplePanelAddButton(
      availableTools: <SimpleWorkspaceTool>[
        for (final tool in SimpleWorkspaceTool.values)
          if (!openKeys.contains(tool.key)) tool,
      ],
      onSelect: _selectKey,
      onNewTerminal: () {
        if (widget.onNewTerminalInGroup != null) {
          widget.onNewTerminalInGroup!(widget.groupId);
          return;
        }
        widget.onNewTerminal();
      },
    );
    final activeKey = _activeKey;
    final surface = activeKey == null
        ? widget.content
        : (widget.surfaceBuilder?.call(activeKey) ??
              (activeKey == widget.panel.activeKey
                  ? widget.content
                  : const SizedBox.shrink()));
    return _SimplePaneDropTarget(
      workspaceId: widget.workspaceId,
      groupId: widget.groupId,
      tabCount: _keys.length,
      hoverZone: _hoverZone,
      onHoverZone: (zone) {
        if (zone != _hoverZone) {
          setState(() => _hoverZone = zone);
        }
      },
      onMoveTab: widget.onMoveTab,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          SizedBox(
            height: AleraTokens.sidebarHeaderHeight,
            child: _SimpleStripAppendDropTarget(
              workspaceId: widget.workspaceId,
              tabCount: _keys.length,
              enabled: widget.onMoveTab != null,
              onHoverGap: _handleGapHover,
              onLeave: _handleGapLeave,
              onDropGap: _handleGapDrop,
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
                        key: _chipsKey,
                        mainAxisSize: .min,
                        children: <Widget>[
                          for (final (index, key) in _keys.indexed)
                            _tabChip(key, index),
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
                  if (widget.onSplitGroup != null)
                    _SimplePaneMenuButton(
                      canCloseSplit:
                          widget.layout.paneGroupIds.length > 1 &&
                          widget.onMergeGroup != null,
                      onSplitGroup: (zone) =>
                          widget.onSplitGroup!(widget.groupId, zone),
                      onMergeGroup: () =>
                          widget.onMergeGroup?.call(widget.groupId),
                    ),
                  if (widget.showHide)
                    AleraIconButton(
                      tooltip: 'Hide Panel',
                      icon: AleraIcons.chevronsRight,
                      onPressed: widget.onHide,
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: ClipRect(child: surface)),
        ],
      ),
    );
  }
}

class const _SimplePaneDropTarget({
  required final String workspaceId,
  required final String groupId,
  required final int tabCount,
  required final WorkbenchDropZone? hoverZone,
  required final ValueChanged<WorkbenchDropZone?> onHoverZone,
  required final void Function({
    required String key,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  })?
  onMoveTab,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (onMoveTab == null) {
      return child;
    }
    return DragTarget<SimplePaneTabDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data.workspaceId != workspaceId) {
          return false;
        }
        return data.sourceGroupId != groupId || tabCount > 1;
      },
      onMove: (details) {
        onHoverZone(_zoneFor(context, details.data, details.offset));
      },
      onLeave: (_) => onHoverZone(null),
      onAcceptWithDetails: (details) {
        final zone = _zoneFor(context, details.data, details.offset);
        onHoverZone(null);
        if (zone == null) {
          return;
        }
        onMoveTab!(key: details.data.key, targetGroupId: groupId, zone: zone);
      },
      builder: (context, _, _) {
        return Stack(
          fit: .expand,
          clipBehavior: .hardEdge,
          children: <Widget>[
            child,
            if (hoverZone != null)
              IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final rect = resolveWorkbenchDropOverlayRect(
                      zone: hoverZone!,
                      paneSize: constraints.biggest,
                    );
                    return Stack(
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: rect,
                          child: ColoredBox(
                            color: AleraTokens.accent.withValues(alpha: 0.16),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  WorkbenchDropZone? _zoneFor(
    BuildContext context,
    SimplePaneTabDragData data,
    Offset globalOffset,
  ) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return WorkbenchDropZone.center;
    }
    final zone = resolveWorkbenchPaneDropZone(
      paneSize: renderObject.size,
      localPosition: renderObject.globalToLocal(globalOffset),
    );
    if (!isWorkbenchPaneDropActionEnabled(
      sourceGroupId: data.sourceGroupId,
      targetGroupId: groupId,
      targetTabCount: tabCount,
      zone: zone,
    )) {
      return null;
    }
    return zone;
  }
}
