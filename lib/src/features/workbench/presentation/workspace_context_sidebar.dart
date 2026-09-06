import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_requests_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/features/workbench/presentation/workspace_search_panel.dart';
import 'package:flutter/material.dart';

class const WorkspaceContextSidebar({
  super.key,
  required final Workspace workspace,
  required final WorkbenchViewPrefs prefs,
  final WorkspaceSourceControlScope? sourceControlScope,
  final String? focusedSourceControlRoot,
  required final VoidCallback onToggleVisible,
  required final ValueChanged<double> onResize,
  required final ValueChanged<WorkbenchContextPanelTab> onSetContextPanelTab,
  required final ValueChanged<WorkspaceExplorerMode> onSetExplorerMode,
  required final ValueChanged<GitDiffViewMode> onSetGitDiffViewMode,
  required final ValueChanged<GitDiffGroupMode> onSetGitDiffGroupMode,
  final Future<bool> Function(String relativePath)? onFocusSourceControlFolder,
  final VoidCallback? onClearSourceControlRoot,
  required final ValueChanged<String> onOpenFile,
  final ValueChanged<String>? onOpenFilePermanently,
  final ValueChanged<String>? onRevealInExplorer,
  required final OpenGitDiffTabCallback onOpenGitDiff,
  required final OpenGitCommitDiffTabCallback onOpenGitCommitDiff,
  required final ValueChanged<WorkspaceSearchMatchTarget> onOpenSearchMatch,
  required final Future<void> Function(
    String oldRelativePath,
    String newRelativePath,
  )
  onPathMoved,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sourceControlScope = this.sourceControlScope;
    final activeTab = prefs.activeContextPanelTab;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(left: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: prefs.rightSidebarVisible
          ? _ResizableRightSidebar(
              persistedWidth: prefs.rightSidebarWidth,
              onPersistWidth: onResize,
              child: Column(
                children: <Widget>[
                  _ContextTabHeader(
                    activeTab: activeTab,
                    onSetActiveTab: onSetContextPanelTab,
                    onToggleVisible: onToggleVisible,
                  ),
                  Expanded(
                    child: switch (activeTab) {
                      WorkbenchContextPanelTab.explorer => WorkspaceExplorer(
                        key: ValueKey<String>(
                          'workspace-explorer:${workspace.id}:${workspace.path}',
                        ),
                        workspace: workspace,
                        mode: prefs.explorerMode,
                        onModeChanged: onSetExplorerMode,
                        onOpenFile: onOpenFile,
                        onOpenFilePermanently: onOpenFilePermanently,
                        focusedSourceControlRoot: focusedSourceControlRoot,
                        onFocusSourceControlFolder: onFocusSourceControlFolder,
                        onClearSourceControlRoot: onClearSourceControlRoot,
                        onPathMoved: onPathMoved,
                      ),
                      WorkbenchContextPanelTab.search => WorkspaceSearchPanel(
                        workspace: workspace,
                        onOpenMatch: onOpenSearchMatch,
                      ),
                      WorkbenchContextPanelTab.gitDiff =>
                        sourceControlScope == null
                            ? const AleraEmptyState(
                                icon: AleraIcons.gitBranch,
                                title: 'Source Control Unavailable',
                                message: 'This workspace is not connected to a Git repository, so there are no changes to show.',
                              )
                            : WorkspaceGitDiffPanel(
                                workspace: workspace,
                                sourceControlScope: sourceControlScope,
                                viewMode: prefs.gitDiffViewMode,
                                onViewModeChanged: onSetGitDiffViewMode,
                                groupMode: prefs.gitDiffGroupMode,
                                onGroupModeChanged: onSetGitDiffGroupMode,
                                onOpenGitDiff: onOpenGitDiff,
                                onOpenGitCommitDiff: onOpenGitCommitDiff,
                                onOpenFile: onOpenFilePermanently ?? onOpenFile,
                                onRevealInExplorer: onRevealInExplorer,
                                onClearSourceControlRoot:
                                    sourceControlScope.isWorkspaceRoot
                                    ? null
                                    : onClearSourceControlRoot,
                              ),
                      WorkbenchContextPanelTab.pullRequests =>
                        sourceControlScope == null
                            ? const AleraEmptyState(
                                icon: AleraIcons.gitPullRequest,
                                title: 'Pull Request Unavailable',
                                message: 'This workspace is not connected to a Git repository, so there are no Pull Requests to show.',
                              )
                            : WorkspacePullRequestsPanel(
                                key: ValueKey<String>(
                                  'workspace-pull-requests:${workspace.id}:${sourceControlScope.path}',
                                ),
                                workspace: workspace,
                                repoPath: sourceControlScope.path,
                                gitDiffRoot: sourceControlScope.relativeRoot,
                              ),
                    },
                  ),
                ],
              ),
            )
          : _CollapsedContextRail(
              activeTab: activeTab,
              onOpenTab: (tab) {
                onSetContextPanelTab(tab);
                onToggleVisible();
              },
              onToggleVisible: onToggleVisible,
            ),
    );
  }
}

class const _ResizableRightSidebar({
  required final double persistedWidth,
  required final ValueChanged<double> onPersistWidth,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<_ResizableRightSidebar> createState() => _ResizableRightSidebarState();
}

class _ResizableRightSidebarState extends State<_ResizableRightSidebar> {
  double? _transientWidth;

  double get _width => _transientWidth ?? widget.persistedWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        _RightResizeHandle(
          currentWidth: _width,
          onResize: (width) {
            setState(() {
              _transientWidth = width.clamp(
                AleraTokens.sidebarMinWidth,
                AleraTokens.sidebarMaxWidth,
              );
            });
          },
          onResizeEnd: (width) {
            widget.onPersistWidth(width);
            setState(() => _transientWidth = null);
          },
        ),
        SizedBox(width: _width, child: widget.child),
      ],
    );
  }
}

class const _CollapsedContextRail({
  required final WorkbenchContextPanelTab activeTab,
  required final ValueChanged<WorkbenchContextPanelTab> onOpenTab,
  required final VoidCallback onToggleVisible,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AleraTokens.sidebarCollapsedWidth,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AleraTokens.space8),
          _ContextTabButton(
            tab: .explorer,
            activeTab: activeTab,
            tooltip: 'Explorer',
            icon: AleraIcons.copyFiles,
            onPressed: () => onOpenTab(.explorer),
          ),
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: .search,
            activeTab: activeTab,
            tooltip: 'Search',
            icon: AleraIcons.search,
            onPressed: () => onOpenTab(.search),
          ),
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: .gitDiff,
            activeTab: activeTab,
            tooltip: 'Source Control',
            icon: AleraIcons.gitBranch,
            onPressed: () => onOpenTab(.gitDiff),
          ),
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: .pullRequests,
            activeTab: activeTab,
            tooltip: 'Pull Request',
            icon: AleraIcons.gitPullRequest,
            onPressed: () => onOpenTab(.pullRequests),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space8),
            child: AleraIconButton(
              tooltip: 'Expand panel',
              icon: AleraIcons.chevronsLeft,
              onPressed: onToggleVisible,
            ),
          ),
        ],
      ),
    );
  }
}

class const _ContextTabHeader({
  required final WorkbenchContextPanelTab activeTab,
  required final ValueChanged<WorkbenchContextPanelTab> onSetActiveTab,
  required final VoidCallback onToggleVisible,
}) extends StatelessWidget {
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
                tab: .explorer,
                activeTab: activeTab,
                tooltip: 'Explorer',
                icon: AleraIcons.copyFiles,
                onPressed: () => onSetActiveTab(.explorer),
              ),
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: .search,
                activeTab: activeTab,
                tooltip: 'Search',
                icon: AleraIcons.search,
                onPressed: () => onSetActiveTab(.search),
              ),
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: .gitDiff,
                activeTab: activeTab,
                tooltip: 'Source Control',
                icon: AleraIcons.gitBranch,
                onPressed: () => onSetActiveTab(.gitDiff),
              ),
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: .pullRequests,
                activeTab: activeTab,
                tooltip: 'Pull Request',
                icon: AleraIcons.gitPullRequest,
                onPressed: () => onSetActiveTab(.pullRequests),
              ),
              const Spacer(),
              AleraIconButton(
                tooltip: 'Collapse panel',
                icon: AleraIcons.chevronsRight,
                onPressed: onToggleVisible,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _ContextTabButton({
  required final WorkbenchContextPanelTab tab,
  required final WorkbenchContextPanelTab activeTab,
  required final String tooltip,
  required final IconData icon,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
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

class const _RightResizeHandle({
  required final double currentWidth,
  required final ValueChanged<double> onResize,
  required final ValueChanged<double> onResizeEnd,
}) extends StatefulWidget {
  @override
  State<_RightResizeHandle> createState() => _RightResizeHandleState();
}

class _RightResizeHandleState extends State<_RightResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;
  double? _dragWidth;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: .translucent,
        onHorizontalDragStart: (_) {
          _dragWidth = widget.currentWidth;
          setState(() => _dragging = true);
        },
        onHorizontalDragEnd: (_) => _stopDragging(),
        onHorizontalDragCancel: _stopDragging,
        onHorizontalDragUpdate: (details) {
          final next = (_dragWidth ?? widget.currentWidth) - details.delta.dx;
          _dragWidth = next;
          widget.onResize(next);
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

  void _stopDragging() {
    final finalWidth = _dragWidth ?? widget.currentWidth;
    _dragWidth = null;
    setState(() => _dragging = false);
    widget.onResizeEnd(finalWidth);
  }
}
