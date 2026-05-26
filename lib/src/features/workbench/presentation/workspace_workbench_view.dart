import 'dart:async';
import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';

typedef CreateTerminalTabCallback =
    Future<void> Function({String? targetGroupId});
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
typedef UpdateWorkbenchSplitRatioCallback =
    void Function({required List<int> nodePath, required double ratio});
typedef RenameWorkspaceTabCallback =
    Future<void> Function({required String tabId, required String title});

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
    required this.tabs,
    required this.layout,
    required this.terminalRuntime,
    required this.onCreateTab,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseTabs,
    required this.onRenameTab,
    required this.onMoveTab,
    required this.onSplitGroup,
    required this.onMergeGroup,
    required this.onUpdateSplitRatio,
  });

  final Project project;
  final Workspace workspace;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout? layout;
  final TerminalRuntime terminalRuntime;
  final CreateTerminalTabCallback onCreateTab;
  final SelectWorkspaceTabCallback onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<List<String>> onCloseTabs;
  final RenameWorkspaceTabCallback onRenameTab;
  final MoveWorkspaceTabCallback onMoveTab;
  final SplitWorkbenchGroupCallback onSplitGroup;
  final MergeWorkbenchGroupCallback onMergeGroup;
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
      tabs: tabs,
      layout: resolvedLayout,
      node: resolvedLayout.root,
      nodePath: const <int>[],
      terminalRuntime: terminalRuntime,
      onCreateTab: onCreateTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
  }
}

class _WorkbenchLayoutView extends StatelessWidget {
  const _WorkbenchLayoutView({
    required this.workspace,
    required this.tabs,
    required this.layout,
    required this.node,
    required this.nodePath,
    required this.terminalRuntime,
    required this.onCreateTab,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseTabs,
    required this.onRenameTab,
    required this.onMoveTab,
    required this.onSplitGroup,
    required this.onMergeGroup,
    required this.onUpdateSplitRatio,
  });

  final Workspace workspace;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout layout;
  final WorkbenchLayoutNode node;
  final List<int> nodePath;
  final TerminalRuntime terminalRuntime;
  final CreateTerminalTabCallback onCreateTab;
  final SelectWorkspaceTabCallback onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<List<String>> onCloseTabs;
  final RenameWorkspaceTabCallback onRenameTab;
  final MoveWorkspaceTabCallback onMoveTab;
  final SplitWorkbenchGroupCallback onSplitGroup;
  final MergeWorkbenchGroupCallback onMergeGroup;
  final UpdateWorkbenchSplitRatioCallback onUpdateSplitRatio;

  @override
  Widget build(BuildContext context) {
    final groupId = node.groupId;
    if (groupId != null) {
      return _WorkbenchPane(
        workspace: workspace,
        tabs: tabs,
        layout: layout,
        groupId: groupId,
        terminalRuntime: terminalRuntime,
        onCreateTab: onCreateTab,
        onSelectTab: onSelectTab,
        onCloseTab: onCloseTab,
        onCloseTabs: onCloseTabs,
        onRenameTab: onRenameTab,
        onMoveTab: onMoveTab,
        onSplitGroup: onSplitGroup,
        onMergeGroup: onMergeGroup,
      );
    }
    return _WorkbenchSplitView(
      workspace: workspace,
      tabs: tabs,
      layout: layout,
      node: node,
      nodePath: nodePath,
      terminalRuntime: terminalRuntime,
      onCreateTab: onCreateTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
  }
}

class _WorkbenchSplitView extends StatelessWidget {
  const _WorkbenchSplitView({
    required this.workspace,
    required this.tabs,
    required this.layout,
    required this.node,
    required this.nodePath,
    required this.terminalRuntime,
    required this.onCreateTab,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseTabs,
    required this.onRenameTab,
    required this.onMoveTab,
    required this.onSplitGroup,
    required this.onMergeGroup,
    required this.onUpdateSplitRatio,
  });

  final Workspace workspace;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout layout;
  final WorkbenchLayoutNode node;
  final List<int> nodePath;
  final TerminalRuntime terminalRuntime;
  final CreateTerminalTabCallback onCreateTab;
  final SelectWorkspaceTabCallback onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<List<String>> onCloseTabs;
  final RenameWorkspaceTabCallback onRenameTab;
  final MoveWorkspaceTabCallback onMoveTab;
  final SplitWorkbenchGroupCallback onSplitGroup;
  final MergeWorkbenchGroupCallback onMergeGroup;
  final UpdateWorkbenchSplitRatioCallback onUpdateSplitRatio;

  @override
  Widget build(BuildContext context) {
    final axis = node.axis!;
    final first = _WorkbenchLayoutView(
      workspace: workspace,
      tabs: tabs,
      layout: layout,
      node: node.first!,
      nodePath: <int>[...nodePath, 0],
      terminalRuntime: terminalRuntime,
      onCreateTab: onCreateTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
      onUpdateSplitRatio: onUpdateSplitRatio,
    );
    final second = _WorkbenchLayoutView(
      workspace: workspace,
      tabs: tabs,
      layout: layout,
      node: node.second!,
      nodePath: <int>[...nodePath, 1],
      terminalRuntime: terminalRuntime,
      onCreateTab: onCreateTab,
      onSelectTab: onSelectTab,
      onCloseTab: onCloseTab,
      onCloseTabs: onCloseTabs,
      onRenameTab: onRenameTab,
      onMoveTab: onMoveTab,
      onSplitGroup: onSplitGroup,
      onMergeGroup: onMergeGroup,
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

class _WorkbenchPane extends StatelessWidget {
  const _WorkbenchPane({
    required this.workspace,
    required this.tabs,
    required this.layout,
    required this.groupId,
    required this.terminalRuntime,
    required this.onCreateTab,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseTabs,
    required this.onRenameTab,
    required this.onMoveTab,
    required this.onSplitGroup,
    required this.onMergeGroup,
  });

  final Workspace workspace;
  final List<WorkspaceTabRecord> tabs;
  final WorkbenchLayout layout;
  final String groupId;
  final TerminalRuntime terminalRuntime;
  final CreateTerminalTabCallback onCreateTab;
  final SelectWorkspaceTabCallback onSelectTab;
  final ValueChanged<String> onCloseTab;
  final ValueChanged<List<String>> onCloseTabs;
  final RenameWorkspaceTabCallback onRenameTab;
  final MoveWorkspaceTabCallback onMoveTab;
  final SplitWorkbenchGroupCallback onSplitGroup;
  final MergeWorkbenchGroupCallback onMergeGroup;

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
    return _PaneDropTarget(
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
              onSelectTab: (tabId) =>
                  onSelectTab(groupId: groupId, tabId: tabId),
              onCloseTab: onCloseTab,
              onCloseTabs: onCloseTabs,
              onRenameTab: onRenameTab,
              onCreateTab: () => unawaited(onCreateTab(targetGroupId: groupId)),
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
                      tab: activeTab,
                      autofocus: layout.activeGroupId == groupId,
                      terminalRuntime: terminalRuntime,
                    ),
            ),
          ],
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
    required this.tab,
    required this.autofocus,
    required this.terminalRuntime,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final bool autofocus;
  final TerminalRuntime terminalRuntime;

  @override
  Widget build(BuildContext context) {
    return switch (tab.kind) {
      WorkspaceTabKind.terminal => TerminalSurface(
        session: terminalRuntime.sessionFor(workspace: workspace, tab: tab),
        autofocus: autofocus,
      ),
      WorkspaceTabKind.editor || WorkspaceTabKind.browser => const Center(
        child: CircularProgressIndicator(),
      ),
    };
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

class _WorkspaceTabStrip extends StatefulWidget {
  const _WorkspaceTabStrip({
    required this.workspace,
    required this.groupId,
    required this.tabs,
    required this.activeTabId,
    required this.canCloseSplit,
    required this.terminalRuntime,
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
      icon: Icons.more_horiz,
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
      icon: Icons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: onPressed,
    );
  }
}

class _DraggableWorkspaceTabChip extends StatelessWidget {
  const _DraggableWorkspaceTabChip({
    required this.workspace,
    required this.groupId,
    required this.tab,
    required this.active,
    required this.terminalRuntime,
    required this.groupTabs,
    required this.onSelect,
    required this.onClose,
    required this.onCloseTabs,
    required this.onRename,
    required this.onSplit,
  });

  final Workspace workspace;
  final String groupId;
  final WorkspaceTabRecord tab;
  final bool active;
  final TerminalRuntime terminalRuntime;
  final List<WorkspaceTabRecord> groupTabs;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<List<String>> onCloseTabs;
  final ValueChanged<String> onRename;
  final ValueChanged<WorkbenchDropZone> onSplit;

  @override
  Widget build(BuildContext context) {
    final session = tab.kind == WorkspaceTabKind.terminal
        ? terminalRuntime.sessionFor(workspace: workspace, tab: tab)
        : null;
    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space8),
      child: Draggable<_WorkspaceTabDragData>(
        data: _WorkspaceTabDragData(
          workspaceId: workspace.id,
          sourceGroupId: groupId,
          tabId: tab.id,
        ),
        feedback: _DraggedTabFeedback(
          title: session?.displayTitle ?? tab.title,
        ),
        childWhenDragging: Opacity(
          opacity: 0.45,
          child: _WorkspaceTabChip(
            tab: tab,
            terminalSession: session,
            active: active,
            groupTabs: groupTabs,
            onTap: onSelect,
            onClose: onClose,
            onCloseTabs: onCloseTabs,
            onRename: onRename,
            onSplit: onSplit,
          ),
        ),
        child: _WorkspaceTabChip(
          tab: tab,
          terminalSession: session,
          active: active,
          groupTabs: groupTabs,
          onTap: onSelect,
          onClose: onClose,
          onCloseTabs: onCloseTabs,
          onRename: onRename,
          onSplit: onSplit,
        ),
      ),
    );
  }
}

class _WorkspaceTabChip extends StatelessWidget {
  const _WorkspaceTabChip({
    required this.tab,
    required this.terminalSession,
    required this.active,
    required this.groupTabs,
    required this.onTap,
    required this.onClose,
    required this.onCloseTabs,
    required this.onRename,
    required this.onSplit,
  });

  final WorkspaceTabRecord tab;
  final TerminalSessionHandle? terminalSession;
  final bool active;
  final List<WorkspaceTabRecord> groupTabs;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<List<String>> onCloseTabs;
  final ValueChanged<String> onRename;
  final ValueChanged<WorkbenchDropZone> onSplit;

  @override
  Widget build(BuildContext context) {
    final session = terminalSession;
    if (session == null) {
      return _buildChip(context, tab.title);
    }
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => _buildChip(context, session.displayTitle),
    );
  }

  Future<void> _openContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final tabIndex = groupTabs.indexWhere(
      (candidate) => candidate.id == tab.id,
    );
    final closeOthers = <String>[
      for (final candidate in groupTabs)
        if (candidate.id != tab.id) candidate.id,
    ];
    final closeRight = tabIndex < 0
        ? const <String>[]
        : <String>[
            for (final candidate in groupTabs.skip(tabIndex + 1)) candidate.id,
          ];
    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_TabMenuAction>>[
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitUp,
          label: 'Split up',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.up),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitDown,
          label: 'Split down',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.down),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitLeft,
          label: 'Split left',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.left),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitRight,
          label: 'Split right',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.right),
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.close,
          label: 'Close',
          leading: Icon(Icons.close, size: 16),
        ),
        AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.closeOthers,
          label: 'Close others',
          leading: Icon(
            Icons.tab_unselected,
            size: 16,
            color: closeOthers.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeOthers.isNotEmpty,
        ),
        AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.closeRight,
          label: 'Close tabs to the right',
          leading: Icon(
            Icons.keyboard_tab,
            size: 16,
            color: closeRight.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeRight.isNotEmpty,
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.changeTitle,
          label: 'Change title',
          leading: Icon(Icons.edit_outlined, size: 16),
        ),
      ],
    );
    if (selected == null || !context.mounted) {
      return;
    }
    switch (selected) {
      case _TabMenuAction.splitUp:
        onSplit(WorkbenchDropZone.up);
      case _TabMenuAction.splitDown:
        onSplit(WorkbenchDropZone.down);
      case _TabMenuAction.splitLeft:
        onSplit(WorkbenchDropZone.left);
      case _TabMenuAction.splitRight:
        onSplit(WorkbenchDropZone.right);
      case _TabMenuAction.close:
        onClose();
      case _TabMenuAction.closeOthers:
        onCloseTabs(closeOthers);
      case _TabMenuAction.closeRight:
        onCloseTabs(closeRight);
      case _TabMenuAction.changeTitle:
        final title = await showRenameDialog(
          context,
          title: 'Change terminal title',
          labelText: 'Terminal title',
          initialValue: terminalSession?.displayTitle ?? tab.title,
          confirmLabel: 'Change title',
        );
        if (title != null) {
          onRename(title);
        }
    }
  }

  Widget _buildChip(BuildContext context, String title) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_openContextMenu(context, details.globalPosition)),
      child: Material(
        color: active ? AleraTokens.surfaceElevated : AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space6,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              border: Border.all(
                color: active ? AleraTokens.border : AleraTokens.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _iconForWorkspaceTabKind(tab.kind),
                  size: 12,
                  color: active
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                InkWell(
                  onTap: onClose,
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _TabMenuAction {
  splitUp,
  splitDown,
  splitLeft,
  splitRight,
  close,
  closeOthers,
  closeRight,
  changeTitle,
}

IconData _iconForWorkspaceTabKind(WorkspaceTabKind kind) {
  return switch (kind) {
    WorkspaceTabKind.terminal => Icons.terminal,
    WorkspaceTabKind.editor => Icons.description_outlined,
    WorkspaceTabKind.browser => Icons.public,
  };
}

class _DraggedTabFeedback extends StatelessWidget {
  const _DraggedTabFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(color: AleraTokens.border),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AleraTokens.shadowSoft,
              blurRadius: AleraTokens.space12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.terminal, size: 12, color: AleraTokens.foreground),
            const SizedBox(width: AleraTokens.space8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AleraTokens.monoStyle.copyWith(
                  fontSize: 11,
                  color: AleraTokens.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitResizeHandle extends StatefulWidget {
  const _SplitResizeHandle({required this.axis, required this.onRatioDelta});

  final WorkbenchSplitAxis axis;
  final ValueChanged<double> onRatioDelta;

  @override
  State<_SplitResizeHandle> createState() => _SplitResizeHandleState();
}

class _SplitResizeHandleState extends State<_SplitResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == WorkbenchSplitAxis.horizontal;
    final lineColor = _dragging
        ? AleraTokens.accent
        : (_hovered ? AleraTokens.foregroundFaint : AleraTokens.border);
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          widget.onRatioDelta(horizontal ? details.delta.dx : details.delta.dy);
        },
        onPanEnd: (_) => _stopDragging(),
        onPanCancel: _stopDragging,
        child: SizedBox(
          width: horizontal ? AleraTokens.space6 : null,
          height: horizontal ? null : AleraTokens.space6,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: AleraTokens.surface),
              Positioned(
                left: horizontal ? AleraTokens.space2 : 0,
                right: horizontal ? AleraTokens.space2 : 0,
                top: horizontal ? 0 : AleraTokens.space2,
                bottom: horizontal ? 0 : AleraTokens.space2,
                child: AnimatedContainer(
                  duration: AleraTokens.durationFast,
                  color: lineColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stopDragging() {
    setState(() => _dragging = false);
  }
}

class _WorkspaceTabDragData {
  const _WorkspaceTabDragData({
    required this.workspaceId,
    required this.sourceGroupId,
    required this.tabId,
  });

  final String workspaceId;
  final String sourceGroupId;
  final String tabId;
}

enum _PaneMenuAction { splitRight, splitDown, splitLeft, splitUp, closeSplit }

WorkspaceTabRecord? _activeTab(
  WorkbenchPaneGroup? group,
  List<WorkspaceTabRecord> tabs,
) {
  if (group == null || tabs.isEmpty) {
    return null;
  }
  for (final tab in tabs) {
    if (tab.id == group.activeTabId) {
      return tab;
    }
  }
  return tabs.first;
}
