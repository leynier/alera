import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/features/workbench/presentation/workspace_search_panel.dart';
import 'package:flutter/material.dart';

class WorkspaceContextSidebar extends StatelessWidget {
  const WorkspaceContextSidebar({
    super.key,
    required this.workspace,
    required this.prefs,
    required this.onToggleVisible,
    required this.onResize,
    required this.onSetContextPanelTab,
    required this.onSetExplorerMode,
    required this.onSetGitDiffViewMode,
    required this.onOpenFile,
    required this.onOpenGitDiff,
    required this.onOpenSearchMatch,
    required this.onPathMoved,
  });

  final Workspace workspace;
  final WorkbenchViewPrefs prefs;
  final VoidCallback onToggleVisible;
  final ValueChanged<double> onResize;
  final ValueChanged<WorkbenchContextPanelTab> onSetContextPanelTab;
  final ValueChanged<WorkspaceExplorerMode> onSetExplorerMode;
  final ValueChanged<GitDiffViewMode> onSetGitDiffViewMode;
  final ValueChanged<String> onOpenFile;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<WorkspaceSearchMatchTarget> onOpenSearchMatch;
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
                        onSetActiveTab: onSetContextPanelTab,
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
                          WorkbenchContextPanelTab.search =>
                            WorkspaceSearchPanel(
                              workspace: workspace,
                              onOpenMatch: onOpenSearchMatch,
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
              onOpenTab: (tab) {
                onSetContextPanelTab(tab);
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
    required this.onOpenTab,
    required this.onToggleVisible,
  });

  final WorkbenchContextPanelTab activeTab;
  final ValueChanged<WorkbenchContextPanelTab> onOpenTab;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AleraTokens.sidebarCollapsedWidth,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AleraTokens.space8),
          _ContextTabButton(
            tab: WorkbenchContextPanelTab.explorer,
            activeTab: activeTab,
            tooltip: 'Explorer',
            icon: Icons.file_copy_outlined,
            onPressed: () => onOpenTab(WorkbenchContextPanelTab.explorer),
          ),
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: WorkbenchContextPanelTab.search,
            activeTab: activeTab,
            tooltip: 'Search',
            icon: Icons.search_rounded,
            onPressed: () => onOpenTab(WorkbenchContextPanelTab.search),
          ),
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: WorkbenchContextPanelTab.gitDiff,
            activeTab: activeTab,
            tooltip: 'Source Control',
            icon: Icons.account_tree_outlined,
            onPressed: () => onOpenTab(WorkbenchContextPanelTab.gitDiff),
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
    required this.onSetActiveTab,
    required this.onToggleVisible,
  });

  final WorkbenchContextPanelTab activeTab;
  final ValueChanged<WorkbenchContextPanelTab> onSetActiveTab;
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
              _ContextTabButton(
                tab: WorkbenchContextPanelTab.explorer,
                activeTab: activeTab,
                tooltip: 'Explorer',
                icon: Icons.file_copy_outlined,
                onPressed: () =>
                    onSetActiveTab(WorkbenchContextPanelTab.explorer),
              ),
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: WorkbenchContextPanelTab.search,
                activeTab: activeTab,
                tooltip: 'Search',
                icon: Icons.search_rounded,
                onPressed: () =>
                    onSetActiveTab(WorkbenchContextPanelTab.search),
              ),
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: WorkbenchContextPanelTab.gitDiff,
                activeTab: activeTab,
                tooltip: 'Source Control',
                icon: Icons.account_tree_outlined,
                onPressed: () =>
                    onSetActiveTab(WorkbenchContextPanelTab.gitDiff),
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

class _ContextTabButton extends StatelessWidget {
  const _ContextTabButton({
    required this.tab,
    required this.activeTab,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final WorkbenchContextPanelTab tab;
  final WorkbenchContextPanelTab activeTab;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = tab == activeTab;
    return AleraIconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      iconColor: active ? AleraTokens.foreground : AleraTokens.foregroundMuted,
      backgroundColor: active ? AleraTokens.surfaceElevated : null,
      borderColor: active ? AleraTokens.border : AleraTokens.borderSubtle,
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
