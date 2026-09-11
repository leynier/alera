import 'dart:async';
import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/workbench/domain/experimental_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_drop_zones.dart';
import 'package:alera/src/features/workbench/presentation/workbench_split_glyphs.dart';
import 'package:flutter/material.dart';

part 'experimental_workspace_panel_pane.dart';
part 'experimental_workspace_panel_split.dart';
part 'experimental_workspace_panel_menus.dart';
part 'experimental_workspace_panel_empty.dart';

class const ExperimentalMainDropSurface({
  super.key,
  required final String workspaceId,
  required final String groupId,
  required final Widget child,
  required final void Function({
    required String key,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    required ExperimentalPanelTree source,
    int? index,
  })
  onMoveTab,
}) extends StatefulWidget {
  @override
  State<ExperimentalMainDropSurface> createState() =>
      _ExperimentalMainDropSurfaceState();
}

class _ExperimentalMainDropSurfaceState
    extends State<ExperimentalMainDropSurface> {
  WorkbenchDropZone? _hoverZone;

  @override
  Widget build(BuildContext context) {
    return _ExperimentalPaneDropTarget(
      workspaceId: widget.workspaceId,
      groupId: widget.groupId,
      tabCount: 1,
      hoverZone: _hoverZone,
      onHoverZone: (zone) {
        if (zone != _hoverZone) {
          setState(() => _hoverZone = zone);
        }
      },
      onMoveTab: widget.onMoveTab,
      tree: ExperimentalPanelTree.main,
      child: widget.child,
    );
  }
}

class const ExperimentalPaneTabDragData({
  required final String workspaceId,
  required final String sourceGroupId,
  required final String key,
  final ExperimentalPanelTree tree = ExperimentalPanelTree.right,
});

class const ExperimentalWorkspacePanelView({
  super.key,
  final String workspaceId =
      ExperimentalWorkspacePanel.fallbackLayoutWorkspaceId,
  required final ExperimentalWorkspacePanel panel,
  required final List<WorkspaceTabRecord> tabs,
  required final ValueChanged<String> onSelect,
  required final ValueChanged<String> onClose,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
  final List<AgentProfile> newTabMenuProfiles = const <AgentProfile>[],
  final void Function({required String profileId, String? targetGroupId})?
  onLaunchAgentProfile,
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
    required ExperimentalPanelTree source,
    int? index,
  })?
  onMoveTab,
  final void Function(List<int> path, double ratio)? onUpdateSplitRatio,
  final ExperimentalPanelTree tree = ExperimentalPanelTree.right,
  final bool showHide = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final layout = tree == ExperimentalPanelTree.main
        ? panel.ensuredMainLayout(workspaceId)
        : panel.ensuredLayout(workspaceId);
    if (tree == ExperimentalPanelTree.right && panel.tabKeys.isEmpty) {
      return _ExperimentalPanelEmpty(
        onSelect: onSelect,
        onNewTerminal: onNewTerminal,
        onHide: onHide,
        content: content,
        workspaceId: workspaceId,
        newTabMenuProfiles: newTabMenuProfiles,
        onLaunchAgentProfile: onLaunchAgentProfile,
      );
    }
    return _ExperimentalPanelLayoutNode(
      workspaceId: workspaceId,
      panel: panel,
      tabs: tabs,
      layout: layout,
      node: layout.root,
      nodePath: const <int>[],
      onSelect: onSelect,
      onClose: onClose,
      onNewTerminal: onNewTerminal,
      onSelectInGroup: onSelectInGroup,
      onNewTerminalInGroup: onNewTerminalInGroup,
      newTabMenuProfiles: newTabMenuProfiles,
      onLaunchAgentProfile: onLaunchAgentProfile,
      onHide: onHide,
      content: content,
      surfaceBuilder: surfaceBuilder,
      tabBuilder: tabBuilder,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onMoveTab: onMoveTab,
      onUpdateSplitRatio: onUpdateSplitRatio,
      tree: tree,
      showHide: showHide,
    );
  }
}

class const _ExperimentalPanelLayoutNode({
  required final String workspaceId,
  required final ExperimentalWorkspacePanel panel,
  required final List<WorkspaceTabRecord> tabs,
  required final WorkbenchLayout layout,
  required final WorkbenchLayoutNode node,
  required final List<int> nodePath,
  required final ValueChanged<String> onSelect,
  required final ValueChanged<String> onClose,
  required final VoidCallback onNewTerminal,
  required final VoidCallback onHide,
  required final Widget content,
  final List<AgentProfile> newTabMenuProfiles = const <AgentProfile>[],
  final void Function({required String profileId, String? targetGroupId})?
  onLaunchAgentProfile,
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
    required ExperimentalPanelTree source,
    int? index,
  })?
  onMoveTab,
  final void Function(List<int> path, double ratio)? onUpdateSplitRatio,
  final ExperimentalPanelTree tree = ExperimentalPanelTree.right,
  final bool showHide = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final groupId = node.groupId;
    if (groupId != null) {
      return _ExperimentalPanelPane(
        workspaceId: workspaceId,
        panel: panel,
        tabs: tabs,
        layout: layout,
        groupId: groupId,
        showHide: showHide && groupId == layout.topRightPaneGroupId,
        tree: tree,
        onSelect: onSelect,
        onClose: onClose,
        onNewTerminal: onNewTerminal,
        onSelectInGroup: onSelectInGroup,
        onNewTerminalInGroup: onNewTerminalInGroup,
        newTabMenuProfiles: newTabMenuProfiles,
        onLaunchAgentProfile: onLaunchAgentProfile,
        onHide: onHide,
        content: content,
        surfaceBuilder: surfaceBuilder,
        tabBuilder: tabBuilder,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onMoveTab: onMoveTab,
      );
    }
    return _ExperimentalPanelSplitLayout(
      axis: node.axis!,
      persistedRatio: node.ratio!,
      first: _ExperimentalPanelLayoutNode(
        workspaceId: workspaceId,
        panel: panel,
        tabs: tabs,
        layout: layout,
        node: node.first!,
        nodePath: <int>[...nodePath, 0],
        onSelect: onSelect,
        onClose: onClose,
        onNewTerminal: onNewTerminal,
        onSelectInGroup: onSelectInGroup,
        onNewTerminalInGroup: onNewTerminalInGroup,
        newTabMenuProfiles: newTabMenuProfiles,
        onLaunchAgentProfile: onLaunchAgentProfile,
        onHide: onHide,
        content: content,
        surfaceBuilder: surfaceBuilder,
        tabBuilder: tabBuilder,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onMoveTab: onMoveTab,
        onUpdateSplitRatio: onUpdateSplitRatio,
        tree: tree,
        showHide: showHide,
      ),
      second: _ExperimentalPanelLayoutNode(
        workspaceId: workspaceId,
        panel: panel,
        tabs: tabs,
        layout: layout,
        node: node.second!,
        nodePath: <int>[...nodePath, 1],
        onSelect: onSelect,
        onClose: onClose,
        onNewTerminal: onNewTerminal,
        onSelectInGroup: onSelectInGroup,
        onNewTerminalInGroup: onNewTerminalInGroup,
        newTabMenuProfiles: newTabMenuProfiles,
        onLaunchAgentProfile: onLaunchAgentProfile,
        onHide: onHide,
        content: content,
        surfaceBuilder: surfaceBuilder,
        tabBuilder: tabBuilder,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onMoveTab: onMoveTab,
        onUpdateSplitRatio: onUpdateSplitRatio,
        tree: tree,
        showHide: showHide,
      ),
      onPersistRatio: (ratio) => onUpdateSplitRatio?.call(nodePath, ratio),
    );
  }
}

IconData _iconForTool(ExperimentalWorkspaceTool? tool) {
  return switch (tool) {
    ExperimentalWorkspaceTool.explorer => AleraIcons.folder,
    ExperimentalWorkspaceTool.search => AleraIcons.search,
    ExperimentalWorkspaceTool.sourceControl => AleraIcons.gitBranch,
    ExperimentalWorkspaceTool.pullRequest => AleraIcons.gitPullRequest,
    null => AleraIcons.terminal,
  };
}
