import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:flutter/material.dart';

class WorkspaceContextSidebar extends StatelessWidget {
  const WorkspaceContextSidebar({
    super.key,
    required this.workspace,
    required this.prefs,
    required this.onToggleVisible,
    required this.onResize,
    required this.onSetActiveContextPanelTab,
    required this.onSetExplorerMode,
    required this.onSetGitDiffViewMode,
    required this.onOpenFile,
    required this.onOpenGitDiff,
    required this.onPathMoved,
  });

  final Workspace workspace;
  final WorkbenchViewPrefs prefs;
  final VoidCallback onToggleVisible;
  final ValueChanged<double> onResize;
  final ValueChanged<WorkbenchContextPanelTab> onSetActiveContextPanelTab;
  final ValueChanged<WorkspaceExplorerMode> onSetExplorerMode;
  final ValueChanged<GitDiffViewMode> onSetGitDiffViewMode;
  final ValueChanged<String> onOpenFile;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final Future<void> Function(String oldRelativePath, String newRelativePath)
  onPathMoved;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(left: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: prefs.rightSidebarVisible
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _RightResizeHandle(
                  currentWidth: prefs.rightSidebarWidth,
                  onResize: onResize,
                ),
                SizedBox(
                  width: prefs.rightSidebarWidth,
                  child: Column(
                    children: <Widget>[
                      _ContextTabHeader(
                        activeTab: prefs.activeContextPanelTab,
                        onSetActiveContextPanelTab: onSetActiveContextPanelTab,
                        onToggleVisible: onToggleVisible,
                      ),
                      Expanded(
                        child: switch (prefs.activeContextPanelTab) {
                          WorkbenchContextPanelTab.explorer =>
                            WorkspaceExplorer(
                              workspace: workspace,
                              mode: prefs.explorerMode,
                              onModeChanged: onSetExplorerMode,
                              onOpenFile: onOpenFile,
                              onPathMoved: onPathMoved,
                            ),
                          WorkbenchContextPanelTab.gitDiff =>
                            WorkspaceGitDiffPanel(
                              workspace: workspace,
                              viewMode: prefs.gitDiffViewMode,
                              onViewModeChanged: onSetGitDiffViewMode,
                              onOpenGitDiff: onOpenGitDiff,
                            ),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            )
          : _CollapsedContextRail(
              activeTab: prefs.activeContextPanelTab,
              onActivateTab: (tab) {
                onSetActiveContextPanelTab(tab);
                onToggleVisible();
              },
              onToggleVisible: onToggleVisible,
            ),
    );
  }
}

class _CollapsedContextRail extends StatelessWidget {
  const _CollapsedContextRail({
    required this.activeTab,
    required this.onActivateTab,
    required this.onToggleVisible,
  });

  final WorkbenchContextPanelTab activeTab;
  final ValueChanged<WorkbenchContextPanelTab> onActivateTab;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AleraTokens.sidebarCollapsedWidth,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AleraTokens.space8),
          AleraIconButton(
            tooltip: 'Explorer',
            icon: Icons.file_copy_outlined,
            onPressed: () => onActivateTab(WorkbenchContextPanelTab.explorer),
            iconColor: activeTab == WorkbenchContextPanelTab.explorer
                ? AleraTokens.foreground
                : AleraTokens.foregroundMuted,
            backgroundColor: activeTab == WorkbenchContextPanelTab.explorer
                ? AleraTokens.surfaceElevated
                : Colors.transparent,
            borderColor: AleraTokens.borderSubtle,
          ),
          const SizedBox(height: AleraTokens.space6),
          AleraIconButton(
            tooltip: 'Git diff',
            icon: Icons.difference_outlined,
            onPressed: () => onActivateTab(WorkbenchContextPanelTab.gitDiff),
            iconColor: activeTab == WorkbenchContextPanelTab.gitDiff
                ? AleraTokens.foreground
                : AleraTokens.foregroundMuted,
            backgroundColor: activeTab == WorkbenchContextPanelTab.gitDiff
                ? AleraTokens.surfaceElevated
                : Colors.transparent,
            borderColor: AleraTokens.borderSubtle,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space8),
            child: AleraIconButton(
              tooltip: 'Expand panel',
              icon: Icons.keyboard_double_arrow_left,
              onPressed: onToggleVisible,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextTabHeader extends StatelessWidget {
  const _ContextTabHeader({
    required this.activeTab,
    required this.onSetActiveContextPanelTab,
    required this.onToggleVisible,
  });

  final WorkbenchContextPanelTab activeTab;
  final ValueChanged<WorkbenchContextPanelTab> onSetActiveContextPanelTab;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          child: Row(
            children: <Widget>[
              AleraIconButton(
                tooltip: 'Explorer',
                icon: Icons.file_copy_outlined,
                onPressed: () => onSetActiveContextPanelTab(
                  WorkbenchContextPanelTab.explorer,
                ),
                iconColor: activeTab == WorkbenchContextPanelTab.explorer
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
                backgroundColor: activeTab == WorkbenchContextPanelTab.explorer
                    ? AleraTokens.surfaceElevated
                    : Colors.transparent,
                borderColor: activeTab == WorkbenchContextPanelTab.explorer
                    ? AleraTokens.border
                    : AleraTokens.borderSubtle,
              ),
              const SizedBox(width: AleraTokens.space2),
              AleraIconButton(
                tooltip: 'Git diff',
                icon: Icons.difference_outlined,
                onPressed: () => onSetActiveContextPanelTab(
                  WorkbenchContextPanelTab.gitDiff,
                ),
                iconColor: activeTab == WorkbenchContextPanelTab.gitDiff
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
                backgroundColor: activeTab == WorkbenchContextPanelTab.gitDiff
                    ? AleraTokens.surfaceElevated
                    : Colors.transparent,
                borderColor: activeTab == WorkbenchContextPanelTab.gitDiff
                    ? AleraTokens.border
                    : AleraTokens.borderSubtle,
              ),
              const Spacer(),
              AleraIconButton(
                tooltip: 'Collapse panel',
                icon: Icons.keyboard_double_arrow_right,
                onPressed: onToggleVisible,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RightResizeHandle extends StatefulWidget {
  const _RightResizeHandle({
    required this.currentWidth,
    required this.onResize,
  });

  final double currentWidth;
  final ValueChanged<double> onResize;

  @override
  State<_RightResizeHandle> createState() => _RightResizeHandleState();
}

class _RightResizeHandleState extends State<_RightResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (details) {
          widget.onResize(widget.currentWidth - details.delta.dx);
        },
        child: SizedBox(
          width: AleraTokens.space6,
          child: Center(
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              width: active ? 2 : 1,
              color: active ? AleraTokens.border : AleraTokens.borderSubtle,
            ),
          ),
        ),
      ),
    );
  }
}
