import 'dart:async';
import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_tab_attention.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/application/workspace_file_preview_kind.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_viewer_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_image_preview_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_merman_viewer_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_pdf_viewer_surface.dart';
import 'package:flutter/material.dart';

part 'workspace_workbench_layout_view.dart';
part 'workspace_workbench_pane.dart';
part 'workspace_workbench_tab_strip.dart';
part 'workspace_workbench_tab_chips.dart';
part 'workspace_workbench_resize_handle.dart';

typedef CreateTerminalTabCallback =
    Future<void> Function({String? targetGroupId});
typedef OpenFileTabCallback =
    Future<void> Function({
      required String relativePath,
      String? targetGroupId,
    });
typedef SelectWorkspaceTabCallback =
    void Function({required String groupId, required String tabId});
typedef MoveWorkspaceTabCallback =
    Future<void> Function({
      required String tabId,
      required String targetGroupId,
      required WorkbenchDropZone zone,
    });
typedef SplitWorkbenchGroupCallback =
    Future<void> Function({
      required String groupId,
      required WorkbenchDropZone zone,
    });
typedef MergeWorkbenchGroupCallback =
    Future<void> Function({required String groupId});
typedef ActivateWorkbenchGroupCallback =
    void Function({required String groupId});
typedef UpdateWorkbenchSplitRatioCallback =
    void Function({required List<int> nodePath, required double ratio});
typedef RenameWorkspaceTabCallback =
    Future<void> Function({required String tabId, required String title});
typedef OpenWorkspaceFileCallback = Future<void> Function(String relativePath);

@visibleForTesting
int splitRatioFlexForTesting(double ratio) =>
    (ratio * 1000).round().clamp(1, 1000).toInt();

@visibleForTesting
Rect splitDirectionFillRectForTesting(WorkbenchDropZone zone, Size size) {
  return switch (zone) {
    WorkbenchDropZone.right => Rect.fromLTWH(
      size.width * 0.6,
      0,
      size.width * 0.4,
      size.height,
    ),
    WorkbenchDropZone.left => Rect.fromLTWH(
      0,
      0,
      size.width * 0.4,
      size.height,
    ),
    WorkbenchDropZone.down => Rect.fromLTWH(
      0,
      size.height * 0.6,
      size.width,
      size.height * 0.4,
    ),
    WorkbenchDropZone.up => Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
    WorkbenchDropZone.center => Rect.zero,
  };
}

@visibleForTesting
bool splitDirectionShouldRepaintForTesting(
  WorkbenchDropZone previousZone,
  WorkbenchDropZone nextZone,
) => previousZone != nextZone;

@visibleForTesting
Widget buildFallbackSplitViewForTesting({
  required WorkbenchSplitAxis axis,
  required double ratio,
  required Widget first,
  required Widget second,
}) {
  return Flex(
    direction: axis == WorkbenchSplitAxis.horizontal
        ? Axis.horizontal
        : Axis.vertical,
    children: <Widget>[
      Expanded(flex: splitRatioFlexForTesting(ratio), child: first),
      _SplitResizeHandle(axis: axis, onRatioDelta: (_) {}),
      Expanded(flex: splitRatioFlexForTesting(1 - ratio), child: second),
    ],
  );
}

@visibleForTesting
Widget buildSplitViewForAvailableSizeForTesting({
  required double available,
  required WorkbenchSplitAxis axis,
  required double ratio,
  required Widget first,
  required Widget second,
  required Widget Function() buildRegularView,
}) {
  if (!available.isFinite || available <= AleraTokens.space16) {
    return buildFallbackSplitViewForTesting(
      axis: axis,
      ratio: ratio,
      first: first,
      second: second,
    );
  }
  return buildRegularView();
}

@visibleForTesting
bool splitDirectionPainterShouldRepaintForTesting(
  WorkbenchDropZone previousZone,
  WorkbenchDropZone nextZone,
) {
  return _SplitDirectionPainter(
    zone: nextZone,
  ).shouldRepaint(_SplitDirectionPainter(zone: previousZone));
}

class WorkspaceWorkbenchView extends StatelessWidget {
  const WorkspaceWorkbenchView({
    super.key,
    required this.project,
    required this.workspace,
    this.sourceControlScope,
    required this.tabs,
    required this.layout,
    required this.terminalRuntime,
    required this.agentStatuses,
    required this.completionAcknowledgements,
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

  final Project project;
  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout? layout;
  final TerminalRuntime terminalRuntime;
  final Map<String, AgentStatusEntry> agentStatuses;
  final WorkbenchTabCompletionAcknowledgements completionAcknowledgements;
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
    final resolvedLayout =
        layout ??
        WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[for (final tab in tabs) tab.id],
        );
    return _WorkbenchLayoutView(
      workspace: workspace,
      sourceControlScope: sourceControlScope,
      tabs: tabs,
      layout: resolvedLayout,
      node: resolvedLayout.root,
      nodePath: const <int>[],
      terminalRuntime: terminalRuntime,
      agentStatuses: agentStatuses,
      completionAcknowledgements: completionAcknowledgements,
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
