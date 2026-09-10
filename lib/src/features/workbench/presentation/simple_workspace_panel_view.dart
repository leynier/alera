import 'dart:async';
import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/workbench/domain/simple_workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_drop_zones.dart';
import 'package:alera/src/features/workbench/presentation/workbench_split_glyphs.dart';
import 'package:flutter/material.dart';

part 'simple_workspace_panel_pane.dart';
part 'simple_workspace_panel_split.dart';
part 'simple_workspace_panel_menus.dart';
part 'simple_workspace_panel_empty.dart';

class const SimplePaneTabDragData({
  required final String workspaceId,
  required final String sourceGroupId,
  required final String key,
});

class const SimpleWorkspacePanelView({
  super.key,
  final String workspaceId = SimpleWorkspacePanel.fallbackLayoutWorkspaceId,
  required final SimpleWorkspacePanel panel,
  required final List<WorkspaceTabRecord> tabs,
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
  final void Function(List<int> path, double ratio)? onUpdateSplitRatio,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final layout = panel.ensuredLayout(workspaceId);
    if (panel.tabKeys.isEmpty) {
      return _SimplePanelEmpty(
        onSelect: onSelect,
        onNewTerminal: onNewTerminal,
        onHide: onHide,
        content: content,
      );
    }
    return _SimplePanelLayoutNode(
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
      onHide: onHide,
      content: content,
      surfaceBuilder: surfaceBuilder,
      tabBuilder: tabBuilder,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onMoveTab: onMoveTab,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
  }
}

class const _SimplePanelLayoutNode({
  required final String workspaceId,
  required final SimpleWorkspacePanel panel,
  required final List<WorkspaceTabRecord> tabs,
  required final WorkbenchLayout layout,
  required final WorkbenchLayoutNode node,
  required final List<int> nodePath,
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
  final void Function(List<int> path, double ratio)? onUpdateSplitRatio,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final groupId = node.groupId;
    if (groupId != null) {
      return _SimplePanelPane(
        workspaceId: workspaceId,
        panel: panel,
        tabs: tabs,
        layout: layout,
        groupId: groupId,
        showHide: groupId == layout.paneGroupIds.first,
        onSelect: onSelect,
        onClose: onClose,
        onNewTerminal: onNewTerminal,
        onSelectInGroup: onSelectInGroup,
        onNewTerminalInGroup: onNewTerminalInGroup,
        onHide: onHide,
        content: content,
        surfaceBuilder: surfaceBuilder,
        tabBuilder: tabBuilder,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onMoveTab: onMoveTab,
      );
    }
    return _SimplePanelSplitLayout(
      axis: node.axis!,
      persistedRatio: node.ratio!,
      first: _SimplePanelLayoutNode(
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
        onHide: onHide,
        content: content,
        surfaceBuilder: surfaceBuilder,
        tabBuilder: tabBuilder,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onMoveTab: onMoveTab,
        onUpdateSplitRatio: onUpdateSplitRatio,
      ),
      second: _SimplePanelLayoutNode(
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
        onHide: onHide,
        content: content,
        surfaceBuilder: surfaceBuilder,
        tabBuilder: tabBuilder,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
        onMoveTab: onMoveTab,
        onUpdateSplitRatio: onUpdateSplitRatio,
      ),
      onPersistRatio: (ratio) => onUpdateSplitRatio?.call(nodePath, ratio),
    );
  }
}

IconData _iconForTool(SimpleWorkspaceTool? tool) {
  return switch (tool) {
    SimpleWorkspaceTool.explorer => AleraIcons.folder,
    SimpleWorkspaceTool.search => AleraIcons.search,
    SimpleWorkspaceTool.sourceControl => AleraIcons.gitBranch,
    SimpleWorkspaceTool.pullRequest => AleraIcons.gitPullRequest,
    null => AleraIcons.terminal,
  };
}
