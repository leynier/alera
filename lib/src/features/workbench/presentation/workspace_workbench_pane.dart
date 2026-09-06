part of 'workspace_workbench_view.dart';

class const _WorkbenchPane({
  required final Workspace workspace,
  required final WorkspaceSourceControlScope? sourceControlScope,
  required final List<WorkspaceTabRecord> tabs,
  required final WorkbenchLayout layout,
  required final String groupId,
  required final TerminalRuntime terminalRuntime,
  required final WorkbenchMobileDriverPresence? mobileDriverPresence,
  required final Map<String, AgentStatusEntry> agentStatuses,
  required final WorkbenchTabCompletionAcknowledgements
  completionAcknowledgements,
  required final CreateTerminalTabCallback onCreateTab,
  required final OpenFileTabCallback onOpenEditorTab,
  required final OpenFileTabCallback onOpenMarkdownViewerTab,
  required final SelectWorkspaceTabCallback onSelectTab,
  required final ValueChanged<String> onCloseTab,
  required final ValueChanged<List<String>> onCloseTabs,
  required final RenameWorkspaceTabCallback onRenameTab,
  required final OpenWorkspaceFileCallback onOpenEditor,
  required final OpenWorkspaceFileCallback onOpenMermanPreview,
  required final MoveWorkspaceTabCallback onMoveTab,
  required final SplitWorkbenchGroupCallback onSplitGroup,
  required final MergeWorkbenchGroupCallback onMergeGroup,
  required final ActivateWorkbenchGroupCallback onActivateGroup,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final group = layout.groups[groupId];
    final tabsById = <String, WorkspaceTabRecord>{
      for (final tab in tabs) tab.id: tab,
    };
    final groupTabs = <WorkspaceTabRecord>[
      for (final tabId in group?.tabIds ?? const <String>[])
        if (tabsById[tabId] case final WorkspaceTabRecord tab) tab,
    ];
    final activeTab = _activeTab(group, groupTabs);
    // Promote this pane to the workbench's active group whenever any descendant
    // widget (terminal view, tab strip controls, etc.) gains real focus, so
    // keyboard shortcuts like split-right/down act on the focused pane.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          onActivateGroup(groupId: groupId);
        }
      },
      child: _PaneDropTarget(
        workspaceId: workspace.id,
        groupId: groupId,
        tabCount: groupTabs.length,
        onMoveTab: onMoveTab,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AleraTokens.bg,
            border: Border(
              right: BorderSide(color: AleraTokens.borderSubtle),
              bottom: BorderSide(color: AleraTokens.borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              _WorkspaceTabStrip(
                workspace: workspace,
                groupId: groupId,
                tabs: groupTabs,
                activeTabId: activeTab?.id,
                canCloseSplit: layout.paneGroupIds.length > 1,
                terminalRuntime: terminalRuntime,
                agentStatuses: agentStatuses,
                completionAcknowledgements: completionAcknowledgements,
                onSelectTab: (tabId) =>
                    onSelectTab(groupId: groupId, tabId: tabId),
                onCloseTab: onCloseTab,
                onCloseTabs: onCloseTabs,
                onRenameTab: onRenameTab,
                onCreateTab: () =>
                    unawaited(onCreateTab(targetGroupId: groupId)),
                onSplitGroup: (zone) =>
                    unawaited(onSplitGroup(groupId: groupId, zone: zone)),
                onMergeGroup: () => unawaited(onMergeGroup(groupId: groupId)),
                onMoveTab: onMoveTab,
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              Expanded(
                child: activeTab == null
                    ? const Center(child: CircularProgressIndicator())
                    : _WorkspaceTabContent(
                        workspace: workspace,
                        sourceControlScope: sourceControlScope,
                        tab: activeTab,
                        autofocus: layout.activeGroupId == groupId,
                        terminalRuntime: terminalRuntime,
                        mobileDriverPresence: mobileDriverPresence,
                        onOpenEditorTab: (relativePath) => unawaited(
                          onOpenEditorTab(
                            relativePath: relativePath,
                            targetGroupId: groupId,
                          ),
                        ),
                        onOpenMarkdownViewerTab: (relativePath) => unawaited(
                          onOpenMarkdownViewerTab(
                            relativePath: relativePath,
                            targetGroupId: groupId,
                          ),
                        ),
                        onOpenMermanPreview: (relativePath) =>
                            unawaited(onOpenMermanPreview(relativePath)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
WorkbenchDropZone resolveWorkbenchPaneDropZone({
  required Size paneSize,
  required Offset localPosition,
}) {
  if (paneSize.width <= 0 || paneSize.height <= 0) {
    return WorkbenchDropZone.center;
  }
  final localX = localPosition.dx.clamp(0, paneSize.width);
  final localY = localPosition.dy.clamp(0, paneSize.height);
  final centerRect = _centerDropRect(paneSize);
  final local = Offset(localX.toDouble(), localY.toDouble());
  if (centerRect.contains(local)) {
    return WorkbenchDropZone.center;
  }

  final horizontalOverflow = local.dx < centerRect.left
      ? centerRect.left - local.dx
      : math.max(0, local.dx - centerRect.right);
  final verticalOverflow = local.dy < centerRect.top
      ? centerRect.top - local.dy
      : math.max(0, local.dy - centerRect.bottom);

  if (horizontalOverflow >= verticalOverflow) {
    return local.dx < paneSize.width / 2
        ? WorkbenchDropZone.left
        : WorkbenchDropZone.right;
  }
  return local.dy < paneSize.height / 2
      ? WorkbenchDropZone.up
      : WorkbenchDropZone.down;
}

@visibleForTesting
Rect resolveWorkbenchDropOverlayRect({
  required WorkbenchDropZone zone,
  required Size paneSize,
}) {
  return switch (zone) {
    WorkbenchDropZone.left => Rect.fromLTWH(
      0,
      0,
      paneSize.width / 2,
      paneSize.height,
    ),
    WorkbenchDropZone.right => Rect.fromLTWH(
      paneSize.width / 2,
      0,
      paneSize.width / 2,
      paneSize.height,
    ),
    WorkbenchDropZone.up => Rect.fromLTWH(
      0,
      0,
      paneSize.width,
      paneSize.height / 2,
    ),
    WorkbenchDropZone.down => Rect.fromLTWH(
      0,
      paneSize.height / 2,
      paneSize.width,
      paneSize.height / 2,
    ),
    WorkbenchDropZone.center => _centerDropRect(paneSize),
  };
}

@visibleForTesting
bool isWorkbenchPaneDropActionEnabled({
  required String sourceGroupId,
  required String targetGroupId,
  required int targetTabCount,
  required WorkbenchDropZone zone,
}) {
  if (sourceGroupId != targetGroupId) {
    return true;
  }
  if (targetTabCount <= 1) {
    return false;
  }
  return zone != WorkbenchDropZone.center;
}

@visibleForTesting
bool workspaceTabUsesImagePreviewForTesting(WorkspaceTabRecord tab) {
  final filePath = tab.filePath;
  return filePath != null && isWorkspaceImageFilePath(filePath);
}

@visibleForTesting
bool workspaceTabUsesMermanPreviewForTesting(WorkspaceTabRecord tab) {
  final filePath = tab.filePath;
  return filePath != null &&
      tab.isMermanPreview &&
      isWorkspaceMermanFilePath(filePath);
}

@visibleForTesting
bool workspaceTabUsesPdfViewerForTesting(WorkspaceTabRecord tab) {
  return tab.kind == WorkspaceTabKind.pdf;
}

Rect _centerDropRect(Size paneSize) {
  const centerWidthFactor = 0.36;
  const centerHeightFactor = 0.36;
  final width = math.min(
    paneSize.width,
    math.max(AleraTokens.space48 * 2, paneSize.width * centerWidthFactor),
  );
  final height = math.min(
    paneSize.height,
    math.max(AleraTokens.space48 * 2, paneSize.height * centerHeightFactor),
  );
  return Rect.fromLTWH(
    (paneSize.width - width) / 2,
    (paneSize.height - height) / 2,
    width,
    height,
  );
}

class const _PaneDropTarget({
  required final String workspaceId,
  required final String groupId,
  required final int tabCount,
  required final MoveWorkspaceTabCallback onMoveTab,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<_PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends State<_PaneDropTarget> {
  WorkbenchDropZone? _hoverZone;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_WorkspaceTabDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data.workspaceId != widget.workspaceId) {
          return false;
        }
        return data.sourceGroupId != widget.groupId || widget.tabCount > 1;
      },
      onMove: (details) {
        final zone = _dropActionZoneForOffset(details.data, details.offset);
        if (zone != _hoverZone) {
          setState(() => _hoverZone = zone);
        }
      },
      onLeave: (_) => setState(() => _hoverZone = null),
      onAcceptWithDetails: (details) {
        final zone = _dropActionZoneForOffset(details.data, details.offset);
        setState(() => _hoverZone = null);
        if (zone == null) {
          return;
        }
        unawaited(
          widget.onMoveTab(
            tabId: details.data.tabId,
            targetGroupId: widget.groupId,
            zone: zone,
          ),
        );
      },
      builder: (context, _, _) {
        return Stack(
          fit: .expand,
          children: <Widget>[
            widget.child,
            if (_hoverZone != null)
              IgnorePointer(child: _DropZoneOverlay(zone: _hoverZone!)),
          ],
        );
      },
    );
  }

  WorkbenchDropZone? _dropActionZoneForOffset(
    _WorkspaceTabDragData data,
    Offset globalOffset,
  ) {
    final zone = _zoneForOffset(globalOffset);
    if (!isWorkbenchPaneDropActionEnabled(
      sourceGroupId: data.sourceGroupId,
      targetGroupId: widget.groupId,
      targetTabCount: widget.tabCount,
      zone: zone,
    )) {
      return null;
    }
    return zone;
  }

  WorkbenchDropZone _zoneForOffset(Offset globalOffset) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return WorkbenchDropZone.center;
    }
    final local = renderObject.globalToLocal(globalOffset);
    return resolveWorkbenchPaneDropZone(
      paneSize: renderObject.size,
      localPosition: local,
    );
  }
}

class const _DropZoneOverlay({required final WorkbenchDropZone zone})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        final rect = resolveWorkbenchDropOverlayRect(
          zone: zone,
          paneSize: size,
        );
        return Stack(
          fit: .expand,
          children: <Widget>[
            Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AleraTokens.accentSubtle,
                  border: Border.all(color: AleraTokens.accent),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
