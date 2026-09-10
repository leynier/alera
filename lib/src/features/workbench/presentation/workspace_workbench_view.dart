import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera/src/features/ai_assist/application/agent_title_providers.dart';
import 'package:alera/src/features/ai_assist/application/agent_title_service.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';

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
import 'package:alera/src/features/workbench/presentation/mobile_driver_overlay.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_viewer_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_image_preview_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_merman_viewer_surface.dart';
import 'package:alera/src/features/workbench/presentation/workspace_pdf_viewer_surface.dart';
import 'package:alera/src/features/workbench/presentation/workbench_drop_zones.dart'
    as drop_zones;
import 'package:alera/src/features/workbench/presentation/workbench_split_glyphs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

part 'workspace_workbench_layout_view.dart';
part 'workspace_workbench_pane.dart';
part 'workspace_workbench_tab_content.dart';
part 'workspace_workbench_tab_strip.dart';
part 'workspace_workbench_new_tab_button.dart';
part 'workspace_workbench_tab_strip_drop.dart';
part 'workspace_workbench_tab_chips.dart';
part 'workspace_workbench_tab_menu.dart';
part 'workspace_workbench_resize_handle.dart';

typedef CreateTerminalTabCallback = Future<void> Function({
  String? targetGroupId,
});
typedef OpenFileTabCallback = Future<void> Function({
  required String relativePath,
  String? targetGroupId,
});
typedef SelectWorkspaceTabCallback = void Function({
  required String groupId,
  required String tabId,
});
typedef MoveWorkspaceTabCallback = Future<void> Function({
  required String tabId,
  required String targetGroupId,
  required WorkbenchDropZone zone,
  int? index,
});
typedef SplitWorkbenchGroupCallback = Future<void> Function({
  required String groupId,
  required WorkbenchDropZone zone,
});
typedef MergeWorkbenchGroupCallback = Future<void> Function({
  required String groupId,
});
typedef ActivateWorkbenchGroupCallback = void Function({
  required String groupId,
});
typedef UpdateWorkbenchSplitRatioCallback = void Function({
  required List<int> nodePath,
  required double ratio,
});
typedef RenameWorkspaceTabCallback = Future<void> Function({
  required String tabId,
  required String title,
});
typedef OpenWorkspaceFileCallback = Future<void> Function(String relativePath);

Widget buildSimpleWorkspaceTabChip({
  required WorkspaceTabRecord tab,
  required List<WorkspaceTabRecord> tabs,
  required bool active,
  required TerminalRuntime runtime,
  required AgentStatusEntry? status,
  required WorkbenchTabCompletionAcknowledgements acknowledgements,
  required VoidCallback onSelect,
  required ValueChanged<List<String>> onCloseTabs,
  required ValueChanged<String> onRename,
  required ValueChanged<String> onKeep,
  ValueChanged<WorkbenchDropZone>? onSplit,
}) {
  if (active) acknowledgements.acknowledge(status);
  return Padding(
    padding: const EdgeInsets.only(right: AleraTokens.space8),
    child: _KeepPreviewTabScope(
      onKeep: onKeep,
      child: _SimplePreviewKeepTap(
        tab: tab,
        onSelect: onSelect,
        onKeep: onKeep,
        builder: (onTap) => _WorkspaceTabChip(
          canSplit: onSplit != null,
          tab: tab,
          terminalSession: runtime.peekSession(tab.id),
          status: status,
          completionAcknowledged: acknowledgements.isAcknowledged(status),
          active: active,
          groupTabs: tabs,
          onTap: onTap,
          onClose: () => onCloseTabs(<String>[tab.id]),
          onCloseTabs: onCloseTabs,
          onRename: onRename,
          onSplit: onSplit ?? (_) {},
        ),
      ),
    ),
  );
}

@visibleForTesting
String workspaceTabTitleForTesting(WorkspaceTabRecord tab) =>
    _workspaceTabTitle(tab);

String _workspaceTabTitle(WorkspaceTabRecord tab) => tab.title;

@visibleForTesting
int splitRatioFlexForTesting(double ratio) =>
    (ratio * 1000).round().clamp(1, 1000).toInt();

@visibleForTesting
Rect splitDirectionFillRectForTesting(WorkbenchDropZone zone, Size size) {
  return workbenchSplitDirectionFillRect(zone, size);
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
  return WorkbenchSplitDirectionPainter(zone: nextZone)
      .shouldRepaint(WorkbenchSplitDirectionPainter(zone: previousZone));
}

class const WorkspaceWorkbenchView({
  super.key,
  required final Project project,
  required final Workspace workspace,
  final WorkspaceSourceControlScope? sourceControlScope,
  required final List<WorkspaceTabRecord> tabs,
  required final WorkbenchLayout? layout,
  required final TerminalRuntime terminalRuntime,
  final WorkbenchMobileDriverPresence? mobileDriverPresence,
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
  required final UpdateWorkbenchSplitRatioCallback onUpdateSplitRatio,
  final ValueChanged<String>? onKeepPreviewTab,
  final bool singleSurface = false,
  final String? singleTabId,
}) extends StatefulWidget {
  @override
  State<WorkspaceWorkbenchView> createState() => _WorkspaceWorkbenchViewState();
}

class _WorkspaceWorkbenchViewState extends State<WorkspaceWorkbenchView> {
  final _tabDragController = _WorkbenchTabDragController();

  @override
  void dispose() {
    _tabDragController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.singleSurface) {
      final tab = widget.tabs
          .where((tab) => tab.id == widget.singleTabId)
          .firstOrNull;
      if (tab == null) {
        return Center(
          child: TextButton(
            onPressed: () => unawaited(widget.onCreateTab()),
            child: const Text('New Terminal'),
          ),
        );
      }
      return Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          if (focused) widget.onSelectTab(groupId: '', tabId: tab.id);
        },
        child: _KeepPreviewTabScope(
          onKeep: widget.onKeepPreviewTab,
          child: _WorkspaceTabContent(
            workspace: widget.workspace,
            sourceControlScope: widget.sourceControlScope,
            tab: tab,
            autofocus: false,
            terminalRuntime: widget.terminalRuntime,
            mobileDriverPresence: widget.mobileDriverPresence,
            onOpenEditorTab: (path) => unawaited(widget.onOpenEditor(path)),
            onOpenMarkdownViewerTab: (path) =>
                unawaited(widget.onOpenMarkdownViewerTab(relativePath: path)),
            onOpenMermanPreview: (path) =>
                unawaited(widget.onOpenMermanPreview(path)),
          ),
        ),
      );
    }
    final resolvedLayout =
        widget.layout ??
        WorkbenchLayout.single(
          workspaceId: widget.workspace.id,
          tabIds: <String>[for (final tab in widget.tabs) tab.id],
        );
    return _WorkbenchTabDragScope(
      notifier: _tabDragController,
      child: _KeepPreviewTabScope(
        onKeep: widget.onKeepPreviewTab,
        child: _WorkbenchLayoutView(
          workspace: widget.workspace,
          sourceControlScope: widget.sourceControlScope,
          tabs: widget.tabs,
          layout: resolvedLayout,
          node: resolvedLayout.root,
          nodePath: const <int>[],
          terminalRuntime: widget.terminalRuntime,
          mobileDriverPresence: widget.mobileDriverPresence,
          agentStatuses: widget.agentStatuses,
          completionAcknowledgements: widget.completionAcknowledgements,
          onCreateTab: widget.onCreateTab,
          onOpenEditorTab: widget.onOpenEditorTab,
          onOpenMarkdownViewerTab: widget.onOpenMarkdownViewerTab,
          onSelectTab: widget.onSelectTab,
          onCloseTab: widget.onCloseTab,
          onCloseTabs: widget.onCloseTabs,
          onRenameTab: widget.onRenameTab,
          onOpenEditor: widget.onOpenEditor,
          onOpenMermanPreview: widget.onOpenMermanPreview,
          onMoveTab: widget.onMoveTab,
          onSplitGroup: widget.onSplitGroup,
          onMergeGroup: widget.onMergeGroup,
          onActivateGroup: widget.onActivateGroup,
          onUpdateSplitRatio: widget.onUpdateSplitRatio,
        ),
      ),
    );
  }
}

class _WorkbenchTabDragController() extends ValueNotifier<bool> {
  this : super(false);

  var _generation = 0;
  var _disposed = false;

  void begin() {
    if (_disposed) {
      return;
    }
    _generation += 1;
    value = true;
  }

  void finishAfterLayout() {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && generation == _generation) {
        value = false;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}

class const _WorkbenchTabDragScope({
  required super.notifier,
  required super.child,
}) extends InheritedNotifier<_WorkbenchTabDragController> {
  static _WorkbenchTabDragController controllerOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<_WorkbenchTabDragScope>();
    final scope = element?.widget as _WorkbenchTabDragScope?;
    return scope!.notifier!;
  }
}

class _SimplePreviewKeepTap extends StatefulWidget {
  const _SimplePreviewKeepTap({
    required this.tab,
    required this.onSelect,
    required this.onKeep,
    required this.builder,
  });

  final WorkspaceTabRecord tab;
  final VoidCallback onSelect;
  final ValueChanged<String> onKeep;
  final Widget Function(VoidCallback onTap) builder;

  @override
  State<_SimplePreviewKeepTap> createState() => _SimplePreviewKeepTapState();
}

class _SimplePreviewKeepTapState extends State<_SimplePreviewKeepTap> {
  String? _lastId;
  DateTime? _lastAt;

  void _handleTap() {
    widget.onSelect();
    if (!widget.tab.isPreview) {
      _lastId = null;
      _lastAt = null;
      return;
    }
    final now = DateTime.now();
    if (_lastId == widget.tab.id &&
        _lastAt != null &&
        now.difference(_lastAt!) <= kDoubleTapTimeout) {
      widget.onKeep(widget.tab.id);
      _lastId = null;
      _lastAt = null;
      return;
    }
    _lastId = widget.tab.id;
    _lastAt = now;
  }

  @override
  Widget build(BuildContext context) => widget.builder(_handleTap);
}

class const _KeepPreviewTabScope({
  required final ValueChanged<String>? onKeep,
  required super.child,
}) extends InheritedWidget {
  static ValueChanged<String>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_KeepPreviewTabScope>()
        ?.onKeep;
  }

  @override
  bool updateShouldNotify(_KeepPreviewTabScope oldWidget) =>
      onKeep != oldWidget.onKeep;
}
