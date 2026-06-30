part of 'workspace_workbench_view.dart';

class _WorkbenchLayoutView extends StatelessWidget {
  const _WorkbenchLayoutView({
    required this.workspace,
    required this.sourceControlScope,
    required this.tabs,
    required this.layout,
    required this.node,
    required this.nodePath,
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
    required this.onUpdateSplitRatio,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout layout;
  final WorkbenchLayoutNode node;
  final List<int> nodePath;
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
  final UpdateWorkbenchSplitRatioCallback onUpdateSplitRatio;

  @override
  Widget build(BuildContext context) {
    final groupId = node.groupId;
    if (groupId != null) {
      return _WorkbenchPane(
        workspace: workspace,
        sourceControlScope: sourceControlScope,
        tabs: tabs,
        layout: layout,
        groupId: groupId,
        terminalRuntime: terminalRuntime,
        agentStatuses: agentStatuses,
        onCreateTab: onCreateTab,
        onOpenEditorTab: onOpenEditorTab,
        onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
        onSelectTab: onSelectTab,
        onCloseTab: onCloseTab,
        onCloseTabs: onCloseTabs,
        onRenameTab: onRenameTab,
        onOpenEditor: onOpenEditor,
        onOpenMermanPreview: onOpenMermanPreview,
        onMoveTab: onMoveTab,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onActivateGroup: onActivateGroup,
      );
    }
    return _WorkbenchSplitView(
      workspace: workspace,
      sourceControlScope: sourceControlScope,
      tabs: tabs,
      layout: layout,
      node: node,
      nodePath: nodePath,
      terminalRuntime: terminalRuntime,
      agentStatuses: agentStatuses,
      onCreateTab: onCreateTab,
      onOpenEditorTab: onOpenEditorTab,
      onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onOpenEditor: onOpenEditor,
      onOpenMermanPreview: onOpenMermanPreview,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onActivateGroup: onActivateGroup,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
  }
}

class _WorkbenchSplitView extends StatelessWidget {
  const _WorkbenchSplitView({
    required this.workspace,
    required this.sourceControlScope,
    required this.tabs,
    required this.layout,
    required this.node,
    required this.nodePath,
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
    required this.onUpdateSplitRatio,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout layout;
  final WorkbenchLayoutNode node;
  final List<int> nodePath;
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
  final UpdateWorkbenchSplitRatioCallback onUpdateSplitRatio;

  @override
  Widget build(BuildContext context) {
    final axis = node.axis!;
    final first = _WorkbenchLayoutView(
      workspace: workspace,
      sourceControlScope: sourceControlScope,
      tabs: tabs,
      layout: layout,
      node: node.first!,
      nodePath: <int>[...nodePath, 0],
      terminalRuntime: terminalRuntime,
      agentStatuses: agentStatuses,
      onCreateTab: onCreateTab,
      onOpenEditorTab: onOpenEditorTab,
      onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onOpenEditor: onOpenEditor,
      onOpenMermanPreview: onOpenMermanPreview,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onActivateGroup: onActivateGroup,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
    final second = _WorkbenchLayoutView(
      workspace: workspace,
      sourceControlScope: sourceControlScope,
      tabs: tabs,
      layout: layout,
      node: node.second!,
      nodePath: <int>[...nodePath, 1],
      terminalRuntime: terminalRuntime,
      agentStatuses: agentStatuses,
      onCreateTab: onCreateTab,
      onOpenEditorTab: onOpenEditorTab,
      onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onOpenEditor: onOpenEditor,
      onOpenMermanPreview: onOpenMermanPreview,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onActivateGroup: onActivateGroup,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = axis == WorkbenchSplitAxis.horizontal;
        final available = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        return buildSplitViewForAvailableSizeForTesting(
          available: available,
          axis: axis,
          ratio: node.ratio!,
          first: first,
          second: second,
          buildRegularView: () {
            final handleExtent = AleraTokens.space6;
            final contentExtent = available - handleExtent;
            final firstExtent = contentExtent * node.ratio!;
            final secondExtent = contentExtent - firstExtent;
            return Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              children: <Widget>[
                SizedBox(
                  width: horizontal ? firstExtent : null,
                  height: horizontal ? null : firstExtent,
                  child: first,
                ),
                _SplitResizeHandle(
                  axis: axis,
                  onRatioDelta: (delta) {
                    onUpdateSplitRatio(
                      nodePath: nodePath,
                      ratio: node.ratio! + (delta / contentExtent),
                    );
                  },
                ),
                SizedBox(
                  width: horizontal ? secondExtent : null,
                  height: horizontal ? null : secondExtent,
                  child: second,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
