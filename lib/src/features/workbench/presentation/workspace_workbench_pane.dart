part of 'workspace_workbench_view.dart';

class _WorkbenchPane extends StatelessWidget {
  const _WorkbenchPane({
    required this.workspace,
    required this.sourceControlScope,
    required this.tabs,
    required this.layout,
    required this.groupId,
    required this.terminalRuntime,
    required this.agentStatuses,
    required this.onCreateTab,
    required this.onOpenEditorTab,
    required this.onOpenMarkdownViewerTab,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseTabs,
    required this.onRenameTab,
    required this.onOpenEditor,
    required this.onOpenMermanPreview,
    required this.onMoveTab,
    required this.onSplitGroup,
    required this.onMergeGroup,
    required this.onActivateGroup,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout layout;
  final String groupId;
  final TerminalRuntime terminalRuntime;
  final Map<String, AgentStatusEntry> agentStatuses;
  final CreateTerminalTabCallback onCreateTab;
  final OpenFileTabCallback onOpenEditorTab;
  final OpenFileTabCallback onOpenMarkdownViewerTab;
  final SelectWorkspaceTabCallback onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<List<String>> onCloseTabs;
  final RenameWorkspaceTabCallback onRenameTab;
  final OpenWorkspaceFileCallback onOpenEditor;
  final OpenWorkspaceFileCallback onOpenMermanPreview;
  final MoveWorkspaceTabCallback onMoveTab;
  final SplitWorkbenchGroupCallback onSplitGroup;
  final MergeWorkbenchGroupCallback onMergeGroup;
  final ActivateWorkbenchGroupCallback onActivateGroup;

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _WorkspaceTabStrip(
                workspace: workspace,
                groupId: groupId,
                tabs: groupTabs,
                activeTabId: activeTab?.id,
                canCloseSplit: layout.paneGroupIds.length > 1,
                terminalRuntime: terminalRuntime,
                agentStatuses: agentStatuses,
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
                        onOpenEditorTab: (relativePath) {
                          unawaited(
                            onOpenEditorTab(
                              relativePath: relativePath,
                              targetGroupId: groupId,
                            ),
                          );
                        },
                        onOpenMarkdownViewerTab: (relativePath) {
                          unawaited(
                            onOpenMarkdownViewerTab(
                              relativePath: relativePath,
                              targetGroupId: groupId,
                            ),
                          );
                        },
                        onOpenMermanPreview: (relativePath) {
                          unawaited(onOpenMermanPreview(relativePath));
                        },
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

class _WorkspaceTabContent extends StatelessWidget {
  const _WorkspaceTabContent({
    required this.workspace,
    required this.sourceControlScope,
    required this.tab,
    required this.autofocus,
    required this.terminalRuntime,
    required this.onOpenEditorTab,
    required this.onOpenMarkdownViewerTab,
    required this.onOpenMermanPreview,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final WorkspaceTabRecord tab;
  final bool autofocus;
  final TerminalRuntime terminalRuntime;
  final ValueChanged<String> onOpenEditorTab;
  final ValueChanged<String> onOpenMarkdownViewerTab;
  final ValueChanged<String> onOpenMermanPreview;

  @override
  Widget build(BuildContext context) {
    return switch (tab.kind) {
      WorkspaceTabKind.terminal => TerminalSurface(
        session: terminalRuntime.sessionFor(workspace: workspace, tab: tab),
        autofocus: autofocus,
      ),
      WorkspaceTabKind.editor => _WorkspaceFileTabContent(
        workspace: workspace,
        sourceControlScope: sourceControlScope,
        tab: tab,
        autofocus: autofocus,
        onOpenEditor: onOpenEditorTab,
        onOpenMermanPreview: onOpenMermanPreview,
        onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
      ),
      WorkspaceTabKind.markdownViewer => WorkspaceMarkdownViewerSurface(
        workspace: workspace,
        tab: tab,
        onOpenEditorTab: onOpenEditorTab,
      ),
      WorkspaceTabKind.pdf => WorkspacePdfViewerSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
      ),
      WorkspaceTabKind.gitDiff => WorkspaceGitDiffSurface(
        workspace: workspace,
        tab: tab,
      ),
      WorkspaceTabKind.browser => const Center(
        child: CircularProgressIndicator(),
      ),
    };
  }
}

class _WorkspaceFileTabContent extends StatelessWidget {
  const _WorkspaceFileTabContent({
    required this.workspace,
    required this.sourceControlScope,
    required this.tab,
    required this.autofocus,
    required this.onOpenEditor,
    required this.onOpenMermanPreview,
    required this.onOpenMarkdownViewerTab,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final WorkspaceTabRecord tab;
  final bool autofocus;
  final ValueChanged<String> onOpenEditor;
  final ValueChanged<String> onOpenMermanPreview;
  final ValueChanged<String> onOpenMarkdownViewerTab;

  @override
  Widget build(BuildContext context) {
    final filePath = tab.filePath;
    if (filePath != null && isWorkspaceImageFilePath(filePath)) {
      return WorkspaceImagePreviewSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
      );
    }
    if (filePath != null &&
        tab.isMermanPreview &&
        isWorkspaceMermanFilePath(filePath)) {
      return WorkspaceMermanViewerSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
        onOpenEditor: onOpenEditor,
      );
    }
    return WorkspaceEditorSurface(
      workspace: workspace,
      sourceControlScope: sourceControlScope,
      tab: tab,
      autofocus: autofocus,
      onOpenMermanPreview: onOpenMermanPreview,
      onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
    );
  }
}

class _PaneDropTarget extends StatefulWidget {
  const _PaneDropTarget({
    required this.workspaceId,
    required this.groupId,
    required this.tabCount,
    required this.onMoveTab,
    required this.child,
  });

  final String workspaceId;
  final String groupId;
  final int tabCount;
  final MoveWorkspaceTabCallback onMoveTab;
  final Widget child;

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
          fit: StackFit.expand,
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

class _DropZoneOverlay extends StatelessWidget {
  const _DropZoneOverlay({required this.zone});

  final WorkbenchDropZone zone;

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
          fit: StackFit.expand,
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
